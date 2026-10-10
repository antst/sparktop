import SwiftUI

// sparkDash's amber accent (#e8a830)
let sparkAccent = Color(red: 0.910, green: 0.659, blue: 0.188)

enum Fmt {
    /// sparkDash reports memory and storage in MB.
    static func gb(_ mb: Double?) -> String {
        guard let mb else { return "—" }
        let v = mb / 1024
        return v >= 100 ? String(format: "%.0f GB", v) : String(format: "%.1f GB", v)
    }

    static func pct(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))%"
    }

    static func temp(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))°"
    }

    static func watts(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded())) W"
    }

    static func tps(_ v: Double?) -> String {
        guard let v, v > 0 else { return "—" }
        if v >= 1000 { return String(format: "%.1fk tok/s", v / 1000) }
        return String(format: "%.0f tok/s", v)
    }

    /// sparkDash reports network speeds in bytes/sec.
    static func speed(_ bps: Double?) -> String {
        guard let bps else { return "—" }
        if bps >= 1_000_000 { return String(format: "%.1f MB/s", bps / 1e6) }
        if bps >= 1_000 { return String(format: "%.0f KB/s", bps / 1e3) }
        return "\(Int(bps)) B/s"
    }

    static func uptime(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let s = Int(seconds)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    /// Compact tok/s for stat blocks: "0", "82", "1.2k".
    static func tpsShort(_ v: Double?) -> String {
        guard let v else { return "0" }
        if v >= 1000 { return String(format: "%.1fk", v / 1000) }
        return String(format: "%.0f", v)
    }

    /// Compact token counts: "0", "515k", "3.2M".
    static func tok(_ v: Int?) -> String {
        guard let v else { return "0" }
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1e6) }
        if v >= 1_000 { return String(format: "%.0fk", Double(v) / 1e3) }
        return "\(v)"
    }

    static func relativeTime(_ epochMs: Double?) -> String {
        guard let epochMs, epochMs > 0 else { return "" }
        let date = Date(timeIntervalSince1970: epochMs / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Color for fleet event severities.
func severityColor(_ severity: String?) -> Color {
    switch severity {
    case "success": return Color(nsColor: .systemGreen)
    case "warn": return Color(nsColor: .systemYellow)
    case "error", "critical": return Color(nsColor: .systemRed)
    default: return Color(nsColor: .systemGray)
    }
}

// MARK: - Bars

/// Horizontal bar split into proportional colored segments.
struct SegmentedBar: View {
    let segments: [(Double, Color)]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments.indices, id: \.self) { i in
                    let frac = min(1, max(0, segments[i].0))
                    Capsule()
                        .fill(segments[i].1)
                        .frame(width: max(frac > 0 ? 2 : 0, geo.size.width * frac))
                }
            }
            .frame(height: 6, alignment: .leading)
        }
        .frame(height: 6)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

/// "GPU  [====]  94%" style row.
struct MetricRow: View {
    let label: String
    let fraction: Double
    let color: Color
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            SegmentedBar(segments: [(fraction, color)])
            Text(value)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(minWidth: 52, alignment: .trailing)
        }
    }
}

// MARK: - Chips

struct RoleChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .tracking(0.5)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(sparkAccent.opacity(0.16)))
            .foregroundStyle(sparkAccent)
    }
}

struct HealthDot: View {
    let severity: String?

    var body: some View {
        Circle()
            .fill(severity == "critical" ? Color(nsColor: .systemRed) : Color(nsColor: .systemYellow))
            .frame(width: 6, height: 6)
    }
}

struct StatusDot: View {
    let online: Bool

    var body: some View {
        Circle()
            .fill(online ? Color(nsColor: .systemGreen) : Color(nsColor: .systemGray))
            .frame(width: 8, height: 8)
    }
}

/// Small icon-over-value stat block for the fleet summary strip.
struct StatBlock: View {
    let icon: String
    let value: String
    let label: String
    var help: String = ""

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .help(help.isEmpty ? label : help)
    }
}
