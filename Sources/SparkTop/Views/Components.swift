import SwiftUI
import SparkTopCore

// sparkDash's amber accent (#e8a830)
let sparkAccent = Color(red: 0.910, green: 0.659, blue: 0.188)


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
