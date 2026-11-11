//! DAD UDP syslog collector.
//!
//! Listens on UDP/514, strips the RFC 3164 priority, and appends
//! `<source-ip> <message>` to a staging file that `import_syslog.rb` consumes.
//! Files rotate into `LogsToProcess` once a minute, which is what makes them
//! visible to the importer.
//!
//! Port 514 is privileged, so this needs root or `CAP_NET_BIND_SERVICE` (the
//! systemd unit grants only the latter).
//!
//! This is a byte-for-byte rewrite of `syslog.pl`. The record format, the
//! priority stripping, the 60-second traffic-driven rotation, and the staging
//! filenames are all identical, so the importer cannot tell which collector
//! wrote a file. See `parse.rs` for why the transform is byte-oriented.

mod parse;
mod rotate;
mod runtime;

use std::io::Write;
use std::net::{SocketAddr, UdpSocket};

/// Largest datagram accepted: the maximum UDP payload (65535 IP total minus a
/// 20-byte IP header and an 8-byte UDP header).
///
/// Perl used `recv($buf, 1540)`, which silently discarded everything past 1540
/// bytes -- verified: a 3000-byte packet yielded exactly 1540. 1540 is the old
/// RFC 3164 "should" size, not a protocol limit. Raising it loses nothing:
/// `events.hunks` is a `:text` column (unbounded on Postgres), and a short
/// packet still reads identically because `recv` returns only the bytes sent.
/// This is a deliberate departure from Perl, made because truncation is data
/// loss. Documented as RECOMMENDATIONS 5.8.
pub const MAX_DATAGRAM: usize = 65_507;

fn main() {
    let cfg = match runtime::Config::from_env() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("syslog_collector: {e}");
            std::process::exit(1);
        }
    };

    let sock = match UdpSocket::bind((runtime::BIND_ADDR, cfg.port)) {
        Ok(s) => s,
        Err(e) => {
            // Perl died here: `die("Socket: $@")`. Failing loudly is correct --
            // a collector that cannot bind collects nothing.
            eprintln!(
                "syslog_collector: cannot bind {}:{}: {}",
                runtime::BIND_ADDR,
                cfg.port,
                e
            );
            std::process::exit(1);
        }
    };

    // Heap, not stack: at 65507 bytes this is larger than a typical thread
    // guard page, and the collector would be one recursion away from a fault if
    // the buffer lived in a frame. It is allocated once, before the loop.
    let mut buf = vec![0u8; MAX_DATAGRAM];
    let mut rotator =
        rotate::Rotator::with_interval(cfg.rotate_secs, &cfg.staging_dir, &cfg.processing_dir);

    // Anything a previous collector left in LogStaging is invisible to the
    // importer, so claim it before binding: those messages have been waiting on
    // disk already, and re-reading them is cheaper than losing them.
    rotator.recover_orphans();
    loop {
        let (len, peer) = match sock.recv_from(&mut buf) {
            Ok(v) => v,
            Err(e) => {
                // Deviation from Perl, which ignored recv's return value and
                // logged a blank record (verified: a failed recv leaves $buf
                // empty, not at its previous value). Skipping is strictly
                // better and cannot lose a packet that was never delivered.
                eprintln!("syslog_collector: recv failed: {e}");
                continue;
            }
        };

        let host = peer_host(&peer);
        let message = parse::chomp(parse::strip_priority(&buf[..len]));
        let record = parse::format_record(&host, message);

        rotator.ensure_open(runtime::now_epoch());
        if let Err(e) = rotator.write(&record) {
            eprintln!("syslog_collector: write failed: {e}");
        }

        if cfg.debug {
            // Same bytes as the staging record, to stdout (the journal, under
            // systemd). Opt-in via DAD_SYSLOG_DEBUG.
            let _ = std::io::stdout().write_all(&record);
            let _ = std::io::stdout().flush();
        }
    }
}

/// The source address as a dotted quad.
///
/// The socket is bound to IPv4 `0.0.0.0`, so in practice `peer` is always V4 and
/// this is Perl's `join(".", unpack("C4", sockaddr_in(...))`. The V6 arm exists
/// only so an unexpected address cannot produce a malformed record; IPv6 intake
/// is not supported by either collector.
fn peer_host(peer: &SocketAddr) -> String {
    match peer {
        SocketAddr::V4(v4) => v4.ip().to_string(),
        SocketAddr::V6(v6) => v6.ip().to_string(),
    }
}
