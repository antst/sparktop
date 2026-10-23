import Foundation

/// Compact, platform-neutral formatting for sparkDash values.
public enum Fmt {
    /// sparkDash reports memory and storage in MB.
    public static func gb(_ mb: Double?) -> String {
        guard let mb else { return "—" }
        let v = mb / 1024
        return v >= 100 ? String(format: "%.0f GB", v) : String(format: "%.1f GB", v)
    }

    public static func pct(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))%"
    }

    public static func temp(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))°"
    }

    public static func watts(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded())) W"
    }

    public static func tps(_ v: Double?) -> String {
        guard let v, v > 0 else { return "—" }
        if v >= 1000 { return String(format: "%.1fk tok/s", v / 1000) }
        return String(format: "%.0f tok/s", v)
    }

    /// Compact tok/s for stat blocks: "0", "82", "1.2k".
    public static func tpsShort(_ v: Double?) -> String {
        guard let v else { return "0" }
        if v >= 1000 { return String(format: "%.1fk", v / 1000) }
        return String(format: "%.0f", v)
    }

    /// Compact token counts: "0", "515k", "3.2M".
    public static func tok(_ v: Int?) -> String {
        guard let v else { return "0" }
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1e6) }
        if v >= 1_000 { return String(format: "%.0fk", Double(v) / 1e3) }
        return "\(v)"
    }

    /// sparkDash reports network speeds in bytes/sec.
    public static func speed(_ bps: Double?) -> String {
        guard let bps else { return "—" }
        if bps >= 1_000_000 { return String(format: "%.1f MB/s", bps / 1e6) }
        if bps >= 1_000 { return String(format: "%.0f KB/s", bps / 1e3) }
        return "\(Int(bps)) B/s"
    }

    public static func uptime(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let s = Int(seconds)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    public static func relativeTime(_ epochMs: Double?) -> String {
        guard let epochMs, epochMs > 0 else { return "" }
        let date = Date(timeIntervalSince1970: epochMs / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
