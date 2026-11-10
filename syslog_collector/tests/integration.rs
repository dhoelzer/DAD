//! Drives the real binary over a real UDP socket.
//!
//! These tests spawn the compiled `syslog_collector` with a high port and scratch
//! directories, send packets, and read back what landed on disk. That covers what
//! unit tests cannot: the bind, the recv loop, peer-address formatting, and the
//! interaction between rotation and writing.
//!
//! `DAD_SYSLOG_ROTATE_SECS` shortens the rotation boundary so a test can observe
//! a rotation without sleeping a minute. Production never sets it.

use std::net::UdpSocket;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

struct Harness {
    dir: PathBuf,
    child: Child,
    port: u16,
}

impl Harness {
    /// `rotate_secs` shortens the rotation boundary; `port` must be free.
    fn start(port: u16, rotate_secs: u64) -> Self {
        let dir = std::env::temp_dir().join(format!("dad_e2e_{}_{}", port, std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("LogStaging")).unwrap();
        std::fs::create_dir_all(dir.join("LogsToProcess")).unwrap();

        let bin = binary_path();
        let child = Command::new(&bin)
            .env("DAD_SYSLOG_PORT", port.to_string())
            .env("DAD_SYSLOG_STAGING", dir.join("LogStaging"))
            .env("DAD_SYSLOG_PROCESSING", dir.join("LogsToProcess"))
            .env("DAD_SYSLOG_ROTATE_SECS", rotate_secs.to_string())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .unwrap_or_else(|e| panic!("cannot spawn {}: {e}", bin.display()));

        let mut h = Harness { dir, child, port };
        h.wait_until_listening();
        h
    }

    /// Readiness without sending anything.
    ///
    /// A UDP `connect` always succeeds whether or not anything is listening, and
    /// sending a probe would write a record into the staging file and break the
    /// exact-byte assertions below. Instead: if the collector has bound
    /// 0.0.0.0:port, binding that same port ourselves fails with AddrInUse. That
    /// is the signal, and it leaves no trace on disk.
    fn wait_until_listening(&mut self) {
        let deadline = Instant::now() + Duration::from_secs(10);
        loop {
            if let Some(status) = self.child.try_wait().unwrap() {
                panic!("collector exited early with {status}");
            }
            match UdpSocket::bind(("127.0.0.1", self.port)) {
                // Port is taken, so the collector owns it.
                Err(e) if e.kind() == std::io::ErrorKind::AddrInUse => return,
                // Still free: the collector has not bound yet. Release and retry.
                Ok(_) | Err(_) => {}
            }
            if Instant::now() > deadline {
                panic!("collector never bound port {}", self.port);
            }
            std::thread::sleep(Duration::from_millis(25));
        }
    }

    fn send(&self, payload: &[u8]) {
        let sock = UdpSocket::bind("127.0.0.1:0").unwrap();
        sock.connect(format!("127.0.0.1:{}", self.port)).unwrap();
        sock.send(payload).unwrap();
    }

    fn staging(&self) -> PathBuf {
        self.dir.join("LogStaging")
    }

    fn processing(&self) -> PathBuf {
        self.dir.join("LogsToProcess")
    }

    /// All bytes currently in every staging file, concatenated in name order.
    fn staging_bytes(&self) -> Vec<u8> {
        gather(&self.staging())
    }

    fn processing_bytes(&self) -> Vec<u8> {
        gather(&self.processing())
    }

    /// Waits until the staging files contain `needle`, or fails. UDP is
    /// unreliable and the collector is a separate process, so polling is the only
    /// correct way to synchronise.
    fn wait_for_staging(&self, needle: &[u8]) {
        let deadline = Instant::now() + Duration::from_secs(10);
        loop {
            let body = self.staging_bytes();
            if body.windows(needle.len()).any(|w| w == needle) {
                return;
            }
            if Instant::now() > deadline {
                panic!(
                    "never saw {:?} on disk; staging is {:?}",
                    String::from_utf8_lossy(needle),
                    String::from_utf8_lossy(&body)
                );
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }
}

/// The binary under test is the one cargo just built for this target.
fn binary_path() -> PathBuf {
    let mut p = std::env::current_exe()
        .expect("current_exe")
        .parent() // target/debug/deps
        .expect("deps dir")
        .parent() // target/debug
        .expect("target/debug")
        .to_path_buf();
    p.push("syslog_collector");
    assert!(
        p.exists(),
        "expected the collector binary at {}",
        p.display()
    );
    p
}

fn gather(dir: &Path) -> Vec<u8> {
    let mut names: Vec<_> = std::fs::read_dir(dir)
        .unwrap_or_else(|_| panic!("cannot read {}", dir.display()))
        .map(|e| e.unwrap().path())
        .collect();
    names.sort();
    let mut out = Vec::new();
    for n in names {
        out.extend(std::fs::read(&n).unwrap_or_default());
    }
    out
}

impl Drop for Harness {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

/// Unique high port per test so they can run concurrently.
///
/// The pid is reduced before any arithmetic so the sum cannot exceed u16::MAX;
/// casting first would silently truncate a pid above 65535.
fn free_port(tag: u16) -> u16 {
    20_000 + (std::process::id() % 8_000) as u16 + tag
}

#[test]
fn writes_the_expected_record_for_a_normal_syslog_line() {
    let h = Harness::start(free_port(1), 3600);
    h.send(b"<34>Nov 10 12:00:00 cihost sshd[1]: Accepted password for admin\n");
    h.wait_for_staging(b"Accepted password for admin");

    // Exactly one record, priority gone, source IP first.
    assert_eq!(
        h.staging_bytes(),
        b"127.0.0.1 Nov 10 12:00:00 cihost sshd[1]: Accepted password for admin\n"
    );
}

#[test]
fn strips_the_priority_and_keeps_an_embedded_one() {
    let h = Harness::start(free_port(2), 3600);
    h.send(b"<191>body with <13> embedded priority");
    h.wait_for_staging(b"embedded priority");
    assert_eq!(
        h.staging_bytes(),
        b"127.0.0.1 body with <13> embedded priority\n"
    );
}

#[test]
fn leaves_a_packet_with_no_priority_untouched() {
    let h = Harness::start(free_port(3), 3600);
    h.send(b"no priority at all");
    h.wait_for_staging(b"no priority at all");
    assert_eq!(h.staging_bytes(), b"127.0.0.1 no priority at all\n");
}

#[test]
fn normalises_a_trailing_newline_but_keeps_interior_ones() {
    // Perl's chomp removes one trailing $/ and nothing else, so an interior
    // newline still splits the staging file into two lines. Replicating that
    // exactly is what makes this a drop-in replacement.
    let h = Harness::start(free_port(4), 3600);
    h.send(b"<13>first\nsecond\n");
    h.wait_for_staging(b"second");
    assert_eq!(h.staging_bytes(), b"127.0.0.1 first\nsecond\n");
}

#[test]
fn passes_non_utf8_bytes_through_unchanged() {
    // The reason the transform is byte-oriented. Perl never decoded, so these
    // bytes reach hunks verbatim; a rewrite using String would corrupt them.
    let h = Harness::start(free_port(5), 3600);
    h.send(b"<34>raw \xff\xfe\x80 bytes\n");
    h.wait_for_staging(b"raw \xff\xfe\x80 bytes");
    assert_eq!(h.staging_bytes(), b"127.0.0.1 raw \xff\xfe\x80 bytes\n");
}

#[test]
fn keeps_a_datagram_far_larger_than_perl_could_read() {
    // Perl capped at 1540 and silently dropped the rest. The Rust collector
    // accepts a full UDP datagram, so a 4000-byte message survives intact --
    // this is a case where the rewrite deliberately does NOT match Perl,
    // because matching would mean throwing data away.
    let h = Harness::start(free_port(6), 3600);
    let payload = vec![b'A'; 4000];
    h.send(&payload);
    h.wait_for_staging(&payload);
    let body = h.staging_bytes();
    assert_eq!(body.len(), 10 + 4000 + 1, "record was {} bytes", body.len());
    assert_eq!(&body[10..10 + 4000], payload.as_slice());
}

#[test]
fn recovers_a_file_a_previous_process_left_behind() {
    // The importer reads only LogsToProcess, so a file stranded in LogStaging is
    // invisible forever. Perl left one behind on every restart. A new collector
    // must claim it.
    let port = free_port(12);
    let dir = std::env::temp_dir().join(format!("dad_orphan_{}_{}", port, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("LogStaging")).unwrap();
    std::fs::create_dir_all(dir.join("LogsToProcess")).unwrap();
    // An orphan from a previous run, with content already flushed to disk.
    std::fs::write(
        dir.join("LogStaging/syslog.1000000"),
        b"127.0.0.1 stranded\n",
    )
    .unwrap();

    let mut child = Command::new(binary_path())
        .env("DAD_SYSLOG_PORT", port.to_string())
        .env("DAD_SYSLOG_STAGING", dir.join("LogStaging"))
        .env("DAD_SYSLOG_PROCESSING", dir.join("LogsToProcess"))
        .env("DAD_SYSLOG_ROTATE_SECS", "3600")
        .spawn()
        .unwrap();
    std::thread::sleep(Duration::from_millis(500));

    let recovered = std::fs::read(dir.join("LogsToProcess/syslog.1000000"))
        .expect("orphan was not moved into LogsToProcess");
    assert_eq!(recovered, b"127.0.0.1 stranded\n");
    assert!(
        !dir.join("LogStaging/syslog.1000000").exists(),
        "orphan still sitting in LogStaging"
    );

    let _ = child.kill();
    let _ = child.wait();
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn rotates_when_the_boundary_passes() {
    let h = Harness::start(free_port(7), 1);
    h.send(b"<13>one\n");
    h.wait_for_staging(b"one");
    let staged = h.staging_bytes();

    // The boundary is compared in whole seconds and is strictly greater-than, so
    // with interval=1 the wait must exceed 2s: the first message can land at any
    // point inside its second. Sleeping 1.1s made this test flaky.
    std::thread::sleep(Duration::from_millis(2200));
    h.send(b"<13>two\n");
    h.wait_for_staging(b"two");

    // The first file moved to processing with its contents intact; the second is
    // still staging.
    assert_eq!(h.processing_bytes(), staged);
    assert_eq!(h.staging_bytes(), b"127.0.0.1 two\n");
}

#[test]
fn rotated_files_are_named_syslog_dot_epoch() {
    let h = Harness::start(free_port(8), 1);
    h.send(b"<13>one\n");
    h.wait_for_staging(b"one");
    // The boundary is compared in whole seconds and is strictly greater-than, so
    // with interval=1 the wait must exceed 2s: the first message can land at any
    // point inside its second. Sleeping 1.1s made this test flaky.
    std::thread::sleep(Duration::from_millis(2200));
    h.send(b"<13>two\n");
    h.wait_for_staging(b"two");

    let names: Vec<String> = std::fs::read_dir(h.processing())
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    assert_eq!(names.len(), 1);
    let ts = names[0]
        .strip_prefix("syslog.")
        .unwrap_or_else(|| panic!("unexpected name {}", names[0]));
    let ts: u64 = ts.parse().expect("suffix should be epoch seconds");
    // Within the last minute: proves it is a real timestamp, not a counter.
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    assert!(now - ts < 60, "suffix {ts} is not recent (now {now})");
}

#[test]
fn does_not_rotate_without_traffic() {
    // Rotation is driven by incoming messages, not a timer. With the interval at
    // 1s and no further packets, nothing moves for several seconds.
    let h = Harness::start(free_port(9), 1);
    h.send(b"<13>only\n");
    h.wait_for_staging(b"only");
    std::thread::sleep(Duration::from_millis(2500));
    assert!(
        h.processing_bytes().is_empty(),
        "file rotated with no traffic: {:?}",
        String::from_utf8_lossy(&h.processing_bytes())
    );
    assert_eq!(h.staging_bytes(), b"127.0.0.1 only\n");
}

#[test]
fn keeps_running_when_the_staging_directory_disappears() {
    // Perl printed to STDERR and kept going, retrying at the next boundary.
    // Deleting the directory mid-run reproduces that without needing root.
    let mut h = Harness::start(free_port(10), 1);
    h.send(b"<13>before\n");
    h.wait_for_staging(b"before");
    std::fs::remove_dir_all(h.staging()).unwrap();

    // The boundary is compared in whole seconds and is strictly greater-than, so
    // with interval=1 the wait must exceed 2s: the first message can land at any
    // point inside its second. Sleeping 1.1s made this test flaky.
    std::thread::sleep(Duration::from_millis(2200));
    h.send(b"<13>after\n");
    // The collector must still be alive: a dropped packet is survivable, a dead
    // collector stops the whole pipeline.
    assert!(
        h.child.try_wait().unwrap().is_none(),
        "collector exited after a failed open"
    );
}

#[test]
fn debug_mode_echoes_the_record_to_stdout() {
    let port = free_port(11);
    let dir = std::env::temp_dir().join(format!("dad_dbg_{}_{}", port, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("LogStaging")).unwrap();
    std::fs::create_dir_all(dir.join("LogsToProcess")).unwrap();

    let mut child = Command::new(binary_path())
        .env("DAD_SYSLOG_PORT", port.to_string())
        .env("DAD_SYSLOG_STAGING", dir.join("LogStaging"))
        .env("DAD_SYSLOG_PROCESSING", dir.join("LogsToProcess"))
        .env("DAD_SYSLOG_DEBUG", "1")
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();

    std::thread::sleep(Duration::from_millis(500));
    let sock = UdpSocket::bind("127.0.0.1:0").unwrap();
    sock.connect(format!("127.0.0.1:{port}")).unwrap();
    sock.send(b"<34>echoed me\n").unwrap();
    std::thread::sleep(Duration::from_millis(500));

    let _ = child.kill();
    let out = child.wait_with_output().unwrap();
    let _ = std::fs::remove_dir_all(&dir);

    assert_eq!(out.stdout, b"127.0.0.1 echoed me\n");
}

#[test]
fn rejects_a_non_numeric_port_instead_of_guessing() {
    let out = Command::new(binary_path())
        .env("DAD_SYSLOG_PORT", "not-a-port")
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .output()
        .unwrap();
    assert!(!out.status.success());
    assert!(
        String::from_utf8_lossy(&out.stderr).contains("not a port number"),
        "stderr was {:?}",
        String::from_utf8_lossy(&out.stderr)
    );
}
