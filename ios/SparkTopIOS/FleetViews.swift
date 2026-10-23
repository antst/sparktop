import SwiftUI

// iOS counterparts of the macOS card components.

func severityColor(_ severity: String?) -> Color {
    switch severity {
    case "success": return Color(uiColor: .systemGreen)
    case "warn": return Color(uiColor: .systemYellow)
    case "error", "critical": return Color(uiColor: .systemRed)
    default: return Color(uiColor: .systemGray)
    }
}

let sparkAccent = Color(red: 0.910, green: 0.659, blue: 0.188)

struct StatusDot: View {
    let online: Bool

    var body: some View {
        Circle()
            .fill(online ? Color(uiColor: .systemGreen) : Color(uiColor: .systemGray))
            .frame(width: 8, height: 8)
    }
}

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

/// "GPU [====] 94%" style row.
struct MetricRow: View {
    let label: String
    let fraction: Double
    let color: Color
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            SegmentedBar(segments: [(fraction, color)])
            Text(value)
                .font(.caption2.monospacedDigit())
                .frame(minWidth: 52, alignment: .trailing)
        }
    }
}

/// Fleet summary strip: power · decode · memory · tokens today.
struct FleetStripView: View {
    let store: SnapshotStore

    var body: some View {
        let summary = SnapshotStore.summarize(store.sparks)
        let online = store.sparks.filter { $0.isOnline }
        var decodeTps = 0.0
        for s in online {
            for l in s.metrics?.llm ?? [] where l.available == true {
                decodeTps += l.generationTps ?? 0
            }
        }
        var memUsed = 0.0
        for s in online { memUsed += s.metrics?.unifiedMemory?.used ?? s.metrics?.ram?.used ?? 0 }
        let today = store.tokensToday

        return HStack(spacing: 0) {
            stat("bolt.fill", Fmt.watts(summary.gpuPowerW), "POWER")
            stat("arrow.down.circle", "\(Fmt.tpsShort(decodeTps)) t/s", "DECODE")
            stat("memorychip", Fmt.gb(memUsed), "MEMORY")
            stat("number", today.map { Fmt.tok($0.completion) } ?? "…", "TOK TODAY")
        }
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func stat(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                Text(value).font(.system(size: 14, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(label).font(.system(size: 9, weight: .medium)).tracking(0.5).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Sidebar row + reusable compact card content for a unit.
struct UnitRow: View {
    let spark: SparkSnapshot

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(online: spark.isOnline)
            VStack(alignment: .leading, spacing: 2) {
                Text(spark.name ?? spark.id ?? "?")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                secondaryLine
            }
            Spacer(minLength: 4)
            if spark.isOnline, let gpu = spark.metrics?.gpu {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.temp(gpu.temperature)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    Text(Fmt.watts(gpu.power?.draw)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var secondaryLine: some View {
        let m = spark.metrics
        var parts: [String] = []
        if spark.isWorker { parts.append("worker") }
        if let gpu = m?.gpu, let usage = gpu.usage { parts.append("GPU \(Int(usage))%") }
        if let um = m?.unifiedMemory, let used = um.used { parts.append(Fmt.gb(used)) }
        else if let ram = m?.ram { parts.append(Fmt.gb(ram.used)) }
        return Text(parts.joined(separator: " · "))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// The compact card, shared by the overview and lists.
struct SparkCard: View {
    let spark: SparkSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                StatusDot(online: spark.isOnline)
                Text(spark.name ?? spark.id ?? "?").font(.subheadline.weight(.semibold)).lineLimit(1)
                RoleChip(text: spark.roleLabel)
                Spacer(minLength: 4)
                if spark.isOnline, let gpu = spark.metrics?.gpu {
                    Text("\(Fmt.temp(gpu.temperature)) · \(Fmt.watts(gpu.power?.draw))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if spark.isOnline, let m = spark.metrics {
                resourceBars(m)
                detailLine(m)
                if spark.llmMonitoring == true || (m.llm?.isEmpty == false) {
                    llmRows(m)
                }
            } else {
                Text("Offline" + (spark.offlineReason.map { " — \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            healthRows
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func resourceBars(_ m: Metrics) -> some View {
        Group {
            if spark.isSpark, let um = m.unifiedMemory, let total = um.total, total > 0 {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("MEMORY").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Fmt.gb(um.used)) / \(Fmt.gb(total))").font(.caption2.monospacedDigit())
                    }
                    SegmentedBar(segments: [
                        ((um.gpuUsed ?? 0) / total, sparkAccent),
                        ((um.cpuUsed ?? 0) / total, Color(uiColor: .systemBlue)),
                    ])
                    HStack(spacing: 8) {
                        legend("GPU", sparkAccent, Fmt.gb(um.gpuUsed))
                        legend("CPU", .blue, Fmt.gb(um.cpuUsed))
                        legend("Free", .gray, Fmt.gb(um.available))
                    }
                }
            } else {
                if let vram = m.gpu?.vram, let total = vram.total, total > 0 {
                    MetricRow(label: "VRAM", fraction: (vram.used ?? 0) / total, color: sparkAccent,
                              value: "\(Fmt.gb(vram.used)) / \(Fmt.gb(total))")
                }
                if let ram = m.ram, let total = ram.total, total > 0 {
                    MetricRow(label: "RAM", fraction: (ram.used ?? 0) / total, color: Color(uiColor: .systemBlue),
                              value: "\(Fmt.gb(ram.used)) / \(Fmt.gb(total))")
                }
            }
            if let gpu = m.gpu, let total = gpu.vram?.total, total > 0 {
                MetricRow(label: "GPU", fraction: (gpu.usage ?? 0) / 100,
                          color: gpu.usage.map { $0 >= 90 ? Color(uiColor: .systemOrange) : sparkAccent } ?? sparkAccent,
                          value: Fmt.pct(gpu.usage))
            }
        }
    }

    private func legend(_ name: String, _ color: Color, _ value: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(name) \(value)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func detailLine(_ m: Metrics) -> some View {
        var parts: [String] = []
        if let cpu = m.cpu {
            var s = "CPU \(Fmt.pct(cpu.usage))"
            if cpu.temperature != nil { s += " \(Fmt.temp(cpu.temperature))" }
            parts.append(s)
        }
        if let net = m.network {
            parts.append("↓ \(Fmt.speed(net.rxTotal)) ↑ \(Fmt.speed(net.txTotal))")
        }
        if let root = spark.rootStorage, let pct = root.percentage {
            parts.append("Disk \(pct)%")
        }
        return Group {
            if !parts.isEmpty {
                Text(parts.joined(separator: "  ·  "))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func llmRows(_ m: Metrics) -> some View {
        let llms = m.llm ?? []
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(llms.indices, id: \.self) { i in
                let l = llms[i]
                HStack(spacing: 6) {
                    Circle()
                        .fill(l.available == true ? Color(uiColor: .systemGreen) : Color(uiColor: .systemGray))
                        .frame(width: 6, height: 6)
                    Text((l.backend ?? "LLM").uppercased())
                        .font(.system(size: 9, weight: .semibold)).tracking(0.4)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .foregroundStyle(.secondary)
                    Text(l.modelId ?? l.models?.first ?? "—").font(.caption).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Fmt.tps(l.generationTps))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(l.available == true ? sparkAccent : .secondary)
                    if let kv = l.kvCacheUsage {
                        Text("KV \(Int((kv * 100).rounded()))%").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var healthRows: some View {
        let findings = spark.health ?? []
        ForEach(findings.indices, id: \.self) { i in
            let f = findings[i]
            HStack(alignment: .top, spacing: 5) {
                Circle()
                    .fill(severityColor(f.severity))
                    .frame(width: 6, height: 6).padding(.top, 4)
                Text(f.title ?? "Finding")
                    .font(.caption)
                    .foregroundStyle(f.severity == "critical" ? Color(uiColor: .systemRed) : Color(uiColor: .systemYellow))
                    .lineLimit(2)
            }
        }
    }
}

struct RoleChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold)).tracking(0.5)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(sparkAccent.opacity(0.16)))
            .foregroundStyle(sparkAccent)
    }
}
