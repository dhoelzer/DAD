//! Process-level configuration and the clock.
//!
//! The defaults are the production paths, hardcoded exactly as `syslog.pl`
//! hardcodes them. The overrides exist for one reason: a test that drives the
//! real binary needs a port above 1024 (tests do not run as root) and a scratch
//! directory. Without them the only way to exercise the socket loop would be to
//! install to /var/DAD and bind 514, which is not something a CI job can do.

use std::path::PathBuf;

use crate::rotate::ROTATE_INTERVAL;

/// Bound to IPv4 `0.0.0.0`, matching Perl's `IO::Socket::INET` default. IPv6
/// intake is not supported by either collector.
pub const BIND_ADDR: &str = "0.0.0.0";

pub const DEFAULT_PORT: u16 = 514;

/// The paths the collector writes. Absolute, not relative to the working
/// directory.
///
/// This is the coupling that the Dockerfile comment calls out: `syslog.pl`
/// hardcodes these, while `import_syslog.rb` uses paths relative to its working
/// directory (`Dir.chdir('Logs/LogsToProcess')`). They line up only because
/// every systemd unit sets `WorkingDirectory=/var/DAD`. Nothing validates it, so
/// changing one side without the other silently writes into a directory the
/// importer never reads.
pub const DEFAULT_STAGING: &str = "/var/DAD/Logs/LogStaging";
pub const DEFAULT_PROCESSING: &str = "/var/DAD/Logs/LogsToProcess";

pub struct Config {
    pub port: u16,
    pub rotate_secs: u64,
    pub staging_dir: PathBuf,
    pub processing_dir: PathBuf,
    pub debug: bool,
}

impl Config {
    pub fn from_env() -> Result<Self, String> {
        let port = match std::env::var("DAD_SYSLOG_PORT") {
            Ok(v) => v
                .parse::<u16>()
                .map_err(|_| format!("DAD_SYSLOG_PORT is not a port number: {v}"))?,
            Err(_) => DEFAULT_PORT,
        };
        let rotate_secs = match std::env::var("DAD_SYSLOG_ROTATE_SECS") {
            Ok(v) => v
                .parse::<u64>()
                .map_err(|_| format!("DAD_SYSLOG_ROTATE_SECS is not a number: {v}"))?,
            Err(_) => ROTATE_INTERVAL,
        };
        Ok(Self {
            port,
            rotate_secs,
            staging_dir: env_path("DAD_SYSLOG_STAGING", DEFAULT_STAGING),
            processing_dir: env_path("DAD_SYSLOG_PROCESSING", DEFAULT_PROCESSING),
            // Opt-in echo, same variable name the Perl collector used.
            debug: std::env::var("DAD_SYSLOG_DEBUG").is_ok(),
        })
    }
}

fn env_path(key: &str, default: &str) -> PathBuf {
    std::env::var(key)
        .ok()
        .filter(|v| !v.is_empty())
        .map_or_else(|| PathBuf::from(default), PathBuf::from)
}

/// Epoch seconds, local time.
///
/// Perl used `mktime(localtime())`, which is a round trip through `struct tm`
/// and equals `time()` (verified). `SystemTime::now()` is the direct equivalent.
/// Local vs UTC does not matter here: the value is only ever compared against
/// itself for the 60-second boundary, and used as a filename suffix.
pub fn now_epoch() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        // A clock set before 1970 would underflow; treating that as 0 keeps the
        // collector running rather than panicking on a misconfigured host.
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_are_the_production_paths() {
        // Guards against a refactor quietly changing where the collector writes,
        // which would break the importer coupling without any test noticing.
        assert_eq!(DEFAULT_STAGING, "/var/DAD/Logs/LogStaging");
        assert_eq!(DEFAULT_PROCESSING, "/var/DAD/Logs/LogsToProcess");
        assert_eq!(DEFAULT_PORT, 514);
        assert_eq!(BIND_ADDR, "0.0.0.0");
    }

    #[test]
    fn clock_is_sane() {
        let t = now_epoch();
        // After 2020-01-01 and before 2100. Enough to catch a unit mistake.
        assert!(t > 1_577_836_800 && t < 4_102_444_800, "got {t}");
    }
}
