//! File rotation: the handoff between the collector and the importer.
//!
//! The collector appends to `LogStaging/syslog.<epoch>`; when the clock passes
//! the boundary it closes that file and `rename`s it into `LogsToProcess`, which
//! is the only directory `import_syslog.rb` reads. The rename *is* the handoff --
//! there is no queue and no socket between the two processes.
//!
//! Rotation is driven by incoming traffic, not a timer: `ensure_open` is called
//! from the per-message path, so with no traffic the open file is never moved.
//! That is deliberate (it matches the Perl collector) and it is what makes a
//! single probe packet into a quiet stack sit in `LogStaging` until a *second*
//! packet arrives after the boundary.
//!
//! The clock is a parameter rather than a call to `SystemTime::now()` so the
//! boundary is testable without sleeping.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;

/// Seconds a staging file stays open. Matches the Perl collector's `+= 60`,
/// and is what production runs.
pub const ROTATE_INTERVAL: u64 = 60;

pub struct Rotator {
    interval: u64,
    staging_dir: PathBuf,
    processing_dir: PathBuf,
    /// The instant after which the next message triggers a rotation. 0 means
    /// "nothing open yet", which is what makes the first message rotate.
    next_rotate_at: u64,
    current_name: Option<String>,
    current: Option<File>,
}

impl Rotator {
    /// `interval` is a seam for the integration test, which cannot sleep 60s per
    /// case. Production always passes `ROTATE_INTERVAL`.
    pub fn with_interval(
        interval: u64,
        staging_dir: impl Into<PathBuf>,
        processing_dir: impl Into<PathBuf>,
    ) -> Self {
        Self {
            interval,
            staging_dir: staging_dir.into(),
            processing_dir: processing_dir.into(),
            next_rotate_at: 0,
            current_name: None,
            current: None,
        }
    }

    /// Opens a staging file if the current one has passed its boundary.
    ///
    /// `now` is epoch seconds. The comparison is `now > next_rotate_at`, strictly
    /// greater, matching Perl's `mktime(localtime()) > $RotateTime`.
    pub fn ensure_open(&mut self, now: u64) {
        if now <= self.next_rotate_at {
            return;
        }

        // Nothing to move on the very first call; there is no open file yet.
        if self.next_rotate_at > 0 {
            self.close_current();
            if let Some(name) = &self.current_name {
                let from = self.staging_dir.join(name);
                let to = self.processing_dir.join(name);
                // Perl leaves a failed rename unchecked and silent, which strands
                // a file nothing will ever read. Reporting it costs nothing and is
                // the only way an operator would learn the pipeline stalled here.
                if let Err(e) = std::fs::rename(&from, &to) {
                    eprintln!(
                        "syslog_collector: cannot rotate {} -> {}: {}",
                        from.display(),
                        to.display(),
                        e
                    );
                }
            }
        }

        let name = format!("syslog.{}", now);
        let path = self.staging_dir.join(&name);
        self.current_name = Some(name);

        match OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(&path)
        {
            Ok(f) => self.current = Some(f),
            Err(e) => {
                // Perl prints the same diagnostic and keeps running. The next
                // rotation boundary retries; until then messages are dropped.
                eprintln!("syslog_collector: cannot open {}: {}", path.display(), e);
            }
        }

        self.next_rotate_at = now + self.interval;
    }

    /// Appends one record. Silently does nothing when no file is open, which is
    /// the same observable behaviour as Perl printing to a failed handle.
    pub fn write(&mut self, record: &[u8]) -> std::io::Result<()> {
        if let Some(f) = self.current.as_mut() {
            f.write_all(record)?;
            // Deliberate deviation from Perl, which block-buffers stdio: I
            // measured 0 bytes on disk after 2000 bytes written, so a SIGKILL or
            // crash loses everything not yet flushed. A network-facing intake
            // process should not hold received packets only in memory. This
            // cannot change file *contents*, only how soon they appear.
            f.flush()?;
        }
        Ok(())
    }

    fn close_current(&mut self) {
        if let Some(f) = self.current.take() {
            // Best-effort durability before the rename; the file is about to
            // become the importer's input.
            let _ = f.sync_all();
            drop(f);
        }
    }

    /// Moves files a previous process left in `LogStaging` into `LogsToProcess`.
    ///
    /// This closes the loss path that neither a signal handler nor Perl's design
    /// covers. `import_syslog.rb` reads only `LogsToProcess`, so a file stranded
    /// in `LogStaging` is never read by anything, ever. The Perl collector left
    /// one behind on every restart: it block-buffers stdio, so the messages in
    /// the open file die with the process, and the file itself is orphaned.
    /// Measured: 40 messages sent, 0 bytes durable after SIGTERM *and* after
    /// SIGKILL.
    ///
    /// Doing this at startup rather than on SIGTERM is deliberate. A signal
    /// handler only covers a clean stop; it cannot run on SIGKILL, OOM kill, or
    /// power loss. Startup recovery covers all of them, because the orphan is
    /// still on disk the next time the collector starts.
    ///
    /// Safe because a file in `LogStaging` at startup cannot be open: this is the
    /// only writer, and it has not opened anything yet.
    pub fn recover_orphans(&self) {
        let entries = match std::fs::read_dir(&self.staging_dir) {
            Ok(e) => e,
            Err(_) => return, // the open path reports this on the first message
        };

        let mut names: Vec<_> = entries
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.is_file())
            .collect();
        // Oldest first, so recovery order matches collection order.
        names.sort();

        for path in names {
            let name = match path.file_name() {
                Some(n) => n.to_owned(),
                None => continue,
            };
            let dest = self.processing_dir.join(&name);
            // Never clobber: an existing destination means something already
            // claimed this name, and overwriting it would destroy data we were
            // trying to save.
            if dest.exists() {
                eprintln!(
                    "syslog_collector: refusing to recover {}: {} already exists",
                    path.display(),
                    dest.display()
                );
                continue;
            }
            match std::fs::rename(&path, &dest) {
                Ok(()) => eprintln!(
                    "syslog_collector: recovered orphaned {} into LogsToProcess",
                    name.to_string_lossy()
                ),
                Err(e) => eprintln!("syslog_collector: cannot recover {}: {}", path.display(), e),
            }
        }
    }

    /// Name of the file currently being written. Test-only: the production path
    /// never needs to know its own filename, so it is not compiled into the
    /// binary.
    #[cfg(test)]
    pub fn current_name(&self) -> Option<&str> {
        self.current_name.as_deref()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    /// Scratch dirs per test; the real paths are only used in production.
    struct Dirs {
        root: PathBuf,
        staging: PathBuf,
        processing: PathBuf,
    }

    impl Dirs {
        fn new(tag: &str) -> Self {
            let root = std::env::temp_dir().join(format!("dad_rot_{}_{}", tag, std::process::id()));
            let staging = root.join("LogStaging");
            let processing = root.join("LogsToProcess");
            let _ = std::fs::remove_dir_all(&root);
            std::fs::create_dir_all(&staging).unwrap();
            std::fs::create_dir_all(&processing).unwrap();
            Self {
                root,
                staging,
                processing,
            }
        }
    }

    impl Drop for Dirs {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.root);
        }
    }

    fn listing(dir: &Path) -> Vec<String> {
        let mut v: Vec<String> = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        v.sort();
        v
    }

    #[test]
    fn first_message_opens_a_file_and_moves_nothing() {
        let d = Dirs::new("first");
        let mut r = Rotator::with_interval(60, &d.staging, &d.processing);
        r.ensure_open(1_000_000);
        assert_eq!(r.current_name(), Some("syslog.1000000"));
        assert_eq!(listing(&d.staging), vec!["syslog.1000000"]);
        assert!(listing(&d.processing).is_empty());
    }

    #[test]
    fn file_stays_open_until_the_boundary_passes() {
        let d = Dirs::new("stay");
        let mut r = Rotator::with_interval(60, &d.staging, &d.processing);
        r.ensure_open(1_000_000);
        // Boundary is now+60; equal is not greater, so no rotation at +60.
        for t in [1_000_001, 1_000_030, 1_000_060] {
            r.ensure_open(t);
            assert_eq!(r.current_name(), Some("syslog.1000000"));
            assert_eq!(listing(&d.staging), vec!["syslog.1000000"]);
        }
        r.ensure_open(1_000_061);
        assert_eq!(r.current_name(), Some("syslog.1000061"));
    }

    #[test]
    fn rotation_moves_the_previous_file_into_processing() {
        let d = Dirs::new("move");
        let mut r = Rotator::with_interval(60, &d.staging, &d.processing);
        r.ensure_open(1_000_000);
        r.write(b"1.1.1.1 one\n").unwrap();
        r.ensure_open(1_000_061);
        assert_eq!(listing(&d.staging), vec!["syslog.1000061"]);
        assert_eq!(listing(&d.processing), vec!["syslog.1000000"]);
        let body = std::fs::read(d.processing.join("syslog.1000000")).unwrap();
        assert_eq!(body, b"1.1.1.1 one\n");
    }

    #[test]
    fn rotated_file_is_never_written_to_again() {
        let d = Dirs::new("never");
        let mut r = Rotator::with_interval(60, &d.staging, &d.processing);
        r.ensure_open(1_000_000);
        r.write(b"a\n").unwrap();
        r.ensure_open(1_000_061);
        r.write(b"b\n").unwrap();
        assert_eq!(
            std::fs::read(d.processing.join("syslog.1000000")).unwrap(),
            b"a\n"
        );
        assert_eq!(
            std::fs::read(d.staging.join("syslog.1000061")).unwrap(),
            b"b\n"
        );
    }

    #[test]
    fn several_rotations_in_sequence() {
        let d = Dirs::new("seq");
        let mut r = Rotator::with_interval(60, &d.staging, &d.processing);
        let mut t = 2_000_000;
        for _ in 0..4 {
            r.ensure_open(t);
            r.write(format!("line at {t}\n").as_bytes()).unwrap();
            t += 61;
        }
        r.ensure_open(t);
        // Four opens inside the loop plus one after it: the first opens with
        // nothing to move, each later one rotates its predecessor, so 4 files
        // land in processing and the newest is still staging.
        assert_eq!(listing(&d.processing).len(), 4);
        assert_eq!(listing(&d.staging).len(), 1);
        // Every rotated file kept exactly its own line.
        for name in listing(&d.processing) {
            let ts = name.trim_start_matches("syslog.");
            let body = std::fs::read(d.processing.join(&name)).unwrap();
            assert_eq!(body, format!("line at {ts}\n").into_bytes());
        }
    }

    #[test]
    fn clock_skew_backwards_does_not_rotate() {
        // A NTP correction must not cause a rename or a new file, and must not
        // wedge the collector: the condition is simply false.
        let d = Dirs::new("skew");
        let mut r = Rotator::with_interval(60, &d.staging, &d.processing);
        r.ensure_open(1_000_000);
        r.write(b"one\n").unwrap();
        r.ensure_open(999_000);
        assert_eq!(r.current_name(), Some("syslog.1000000"));
        assert!(listing(&d.processing).is_empty());
        r.write(b"two\n").unwrap();
        assert_eq!(
            std::fs::read(d.staging.join("syslog.1000000")).unwrap(),
            b"one\ntwo\n"
        );
    }

    #[test]
    fn large_clock_jump_rotates_once() {
        let d = Dirs::new("jump");
        let mut r = Rotator::with_interval(60, &d.staging, &d.processing);
        r.ensure_open(1_000_000);
        r.ensure_open(5_000_000);
        assert_eq!(listing(&d.processing), vec!["syslog.1000000"]);
        assert_eq!(r.current_name(), Some("syslog.5000000"));
    }

    #[test]
    fn open_failure_is_reported_and_the_loop_survives() {
        // Staging dir does not exist: Perl printed to STDERR and kept running,
        // retrying at the next boundary. Same here.
        let d = Dirs::new("openfail");
        let missing = d.root.join("nope");
        let mut r = Rotator::with_interval(60, &missing, &d.processing);
        r.ensure_open(1_000_000);
        // No panic, and writes are dropped rather than crashing the process.
        r.write(b"dropped\n").unwrap();
        assert_eq!(listing(&d.staging), Vec::<String>::new());
        // Once the directory exists, the next boundary recovers.
        std::fs::create_dir_all(&missing).unwrap();
        r.ensure_open(1_000_061);
        r.write(b"recovered\n").unwrap();
        assert_eq!(
            std::fs::read(missing.join("syslog.1000061")).unwrap(),
            b"recovered\n"
        );
    }

    #[test]
    fn rename_failure_does_not_stop_collection() {
        // Processing dir missing: the rename fails, but the new staging file must
        // still open so intake continues.
        let d = Dirs::new("renamefail");
        std::fs::remove_dir_all(&d.processing).unwrap();
        let mut r = Rotator::with_interval(60, &d.staging, &d.processing);
        r.ensure_open(1_000_000);
        r.write(b"one\n").unwrap();
        r.ensure_open(1_000_061);
        r.write(b"two\n").unwrap();
        assert_eq!(
            std::fs::read(d.staging.join("syslog.1000061")).unwrap(),
            b"two\n"
        );
    }
}
