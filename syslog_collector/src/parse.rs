//! The per-message transform, as pure functions over bytes.
//!
//! Everything here operates on `&[u8]` rather than `&str` deliberately. Perl is
//! byte-oriented: `s/^<[0-9]+>//` and `chomp` never decode, so a payload holding
//! invalid UTF-8 round-trips through the collector unchanged. Decoding to `String`
//! here would either reject such a packet or replace bytes with U+FFFD, changing
//! what lands in `events.hunks`. The importer downstream does its own UTF-8
//! scrubbing (see `EventIngestor`), which is where that decision belongs.

/// Strips a leading RFC 3164 priority, i.e. `<` + ASCII digits + `>`.
///
/// Mirrors Perl `s/^<[0-9]+>//`: anchored at the front, at least one digit,
/// ASCII digits only, and only the first occurrence. A packet with no priority,
/// or a non-numeric one like `<abc>`, is returned untouched.
pub fn strip_priority(buf: &[u8]) -> &[u8] {
    if buf.first() != Some(&b'<') {
        return buf;
    }
    let mut i = 1;
    while i < buf.len() && buf[i].is_ascii_digit() {
        i += 1;
    }
    // `i == 1` means no digits were consumed, so `<` alone is not a priority.
    if i == 1 || i >= buf.len() || buf[i] != b'>' {
        return buf;
    }
    &buf[i + 1..]
}

/// Removes one trailing newline, mirroring Perl `chomp`.
///
/// `chomp` deletes at most one `$/`, so `"a\n\n"` becomes `"a\n"`, and a
/// `"a\r\n"` payload keeps its `\r`. The caller re-adds the newline, so the
/// net effect is that only the packet's own trailing newline is normalised.
pub fn chomp(msg: &[u8]) -> &[u8] {
    match msg.last() {
        Some(&b'\n') => &msg[..msg.len() - 1],
        _ => msg,
    }
}

/// The staging-file record: `<source-ip> <message>\n`.
///
/// This is the contract the whole ingest side depends on. `EventIngestor` stores
/// the line whole in `events.hunks`, and `Event#event_fields` splits it on
/// spaces, which makes the source IP field 1 and puts the syslog timestamp at
/// field 2 (or fields 2-4 for the year-less RFC 3164 form).
pub fn format_record(host: &str, message: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(host.len() + message.len() + 2);
    out.extend_from_slice(host.as_bytes());
    out.push(b' ');
    out.extend_from_slice(message);
    out.push(b'\n');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_a_standard_priority() {
        assert_eq!(strip_priority(b"<34>host sshd: ok"), b"host sshd: ok");
    }

    #[test]
    fn strips_multi_digit_priority() {
        assert_eq!(strip_priority(b"<191>x"), b"x");
    }

    #[test]
    fn strips_zero_priority() {
        assert_eq!(strip_priority(b"<0>x"), b"x");
    }

    #[test]
    fn leaves_missing_priority_alone() {
        assert_eq!(strip_priority(b"no priority here"), b"no priority here");
    }

    #[test]
    fn leaves_non_numeric_priority_alone() {
        // Perl's [0-9]+ does not match, so the whole `<abc>` stays in the body.
        assert_eq!(strip_priority(b"<abc>x"), b"<abc>x");
    }

    #[test]
    fn leaves_angle_bracket_without_digits() {
        assert_eq!(strip_priority(b"<x"), b"<x");
        assert_eq!(strip_priority(b"<12"), b"<12");
        assert_eq!(strip_priority(b"<12x>"), b"<12x>");
    }

    #[test]
    fn strips_only_the_first_priority() {
        // A forged second priority inside the body survives, exactly as in Perl
        // (no /g on the substitution).
        assert_eq!(strip_priority(b"<13>a\n<14>b"), b"a\n<14>b");
    }

    #[test]
    fn empty_input_is_empty() {
        assert!(strip_priority(b"").is_empty());
    }

    #[test]
    fn chomp_removes_one_trailing_newline() {
        assert_eq!(chomp(b"abc\n"), b"abc");
    }

    #[test]
    fn chomp_removes_only_one_of_several() {
        assert_eq!(chomp(b"abc\n\n"), b"abc\n");
    }

    #[test]
    fn chomp_keeps_carriage_return() {
        assert_eq!(chomp(b"abc\r\n"), b"abc\r");
    }

    #[test]
    fn chomp_is_a_noop_without_newline() {
        assert_eq!(chomp(b"abc"), b"abc");
        assert_eq!(chomp(b""), b"");
    }

    #[test]
    fn record_is_ip_space_message_newline() {
        assert_eq!(format_record("192.0.2.7", b"hi"), b"192.0.2.7 hi\n");
    }

    #[test]
    fn empty_message_yields_ip_space_newline() {
        assert_eq!(format_record("10.0.0.1", b""), b"10.0.0.1 \n");
    }

    #[test]
    fn non_utf8_payload_passes_through_unchanged() {
        // The reason this module is byte-oriented. A 0x80 byte is invalid UTF-8
        // on its own; Perl would pass it through, so we must too.
        let raw = b"<34>bad \xff\xfe byte";
        let stripped = strip_priority(raw);
        assert_eq!(stripped, b"bad \xff\xfe byte");
        let rec = format_record("1.2.3.4", chomp(stripped));
        assert_eq!(rec, b"1.2.3.4 bad \xff\xfe byte\n");
    }
}
