import SwiftUI

/// Compact per-unit card, in the spirit of sparkDash's Overview cards.
struct SparkCardView: View {
    let spark: SparkSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if spark.isOnline {
                if let m = spark.metrics {
                    resourceBars(m)
                    detailRow(m)
                    if spark.llmMonitoring == true || (m.llm?.isEmpty == false) {
                        llmRows(m)
                    }
                }
                healthRows
            } else {
                Text("Offline" + (spark.offlineReason.map { " — \($0)" } ?? ""))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .opacity(spark.isOnline ? 1 : 0.55)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            StatusDot(online: spark.isOnline)
            Text(spark.name ?? spark.id ?? "?")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            RoleChip(text: spark.roleLabel)
            if let uptime = Fmt.uptime(spark.uptime) as String?, !uptime.isEmpty {
                Text(uptime)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if spark.isOnline, let gpu = spark.metrics?.gpu {
                Label {
                    Text(Fmt.temp(gpu.temperature)).font(.system(size: 10).monospacedDigit())
                } icon: {
                    Image(systemName: "thermometer.medium")
                        .renderingMode(.template)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Text(Fmt.watts(gpu.power?.draw))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Resource bars

    private func resourceBars(_ m: Metrics) -> some View {
        Group {
            if spark.isSpark, let um = m.unifiedMemory, let total = um.total, total > 0 {
                // Unified memory: GPU / CPU / free segments.
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("MEMORY")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Fmt.gb(um.used)) / \(Fmt.gb(total))")
                            .font(.system(size: 10).monospacedDigit())
                    }
                    SegmentedBar(segments: [
                        ((um.gpuUsed ?? 0) / total, sparkAccent),
                        ((um.cpuUsed ?? 0) / total, Color(nsColor: .systemBlue)),
                    ])
                    HStack(spacing: 8) {
                        legend("GPU", sparkAccent, Fmt.gb(um.gpuUsed))
                        legend("CPU", .blue, Fmt.gb(um.cpuUsed))
                        legend("Free", .gray, Fmt.gb(um.available))
                        if let bw = um.bandwidth, let current = bw.current, current > 0 {
                            Spacer()
                            Text("BW \(Int(current)) / \(Int(bw.peak ?? 0)) GB/s")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } else {
                if let vram = m.gpu?.vram, let total = vram.total, total > 0 {
                    MetricRow(
                        label: "VRAM",
                        fraction: (vram.used ?? 0) / total,
                        color: sparkAccent,
                        value: "\(Fmt.gb(vram.used)) / \(Fmt.gb(total))"
                    )
                }
                if let ram = m.ram, let total = ram.total, total > 0 {
                    MetricRow(
                        label: "RAM",
                        fraction: (ram.used ?? 0) / total,
                        color: Color(nsColor: .systemBlue),
                        value: "\(Fmt.gb(ram.used)) / \(Fmt.gb(total))"
                    )
                }
            }
            if let gpu = m.gpu, let total = gpu.vram?.total, total > 0 {
                MetricRow(
                    label: "GPU",
                    fraction: (gpu.usage ?? 0) / 100,
                    color: gpu.usage.map { $0 >= 90 ? Color(nsColor: .systemOrange) : sparkAccent } ?? sparkAccent,
                    value: Fmt.pct(gpu.usage)
                )
            }
        }
    }

    private func legend(_ name: String, _ color: Color, _ value: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(name) \(value)")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Detail row (CPU / network / disk)

    private func detailRow(_ m: Metrics) -> some View {
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
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: LLM

    private func llmRows(_ m: Metrics) -> some View {
        let llms = m.llm ?? []
        return VStack(spacing: 4) {
            if llms.isEmpty {
                Text("LLM unreachable")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            ForEach(llms.indices, id: \.self) { i in
                let l = llms[i]
                HStack(spacing: 6) {
                    Circle()
                        .fill(l.available == true ? Color(nsColor: .systemGreen) : Color(nsColor: .systemGray))
                        .frame(width: 6, height: 6)
                    Text((l.backend ?? "LLM").uppercased())
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(0.4)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                        .foregroundStyle(.secondary)
                    Text(l.modelId ?? l.models?.first ?? "—")
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    if l.prefillActive == true {
                        Text("pre \(Fmt.tps(l.prefillTps))")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(Fmt.tps(l.generationTps))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(l.available == true ? sparkAccent : .secondary)
                    if let kv = l.kvCacheUsage {
                        Text("KV \(Int((kv * 100).rounded()))%")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    if let run = l.requestsRunning {
                        let wait = l.requestsWaiting.map { " · \($0) wait" } ?? ""
                        Text("\(run) run\(wait)")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                if let error = l.error, l.available != true {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: Health findings

    private var healthRows: some View {
        let findings = spark.health ?? []
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(findings.indices, id: \.self) { i in
                let f = findings[i]
                HStack(alignment: .top, spacing: 5) {
                    HealthDot(severity: f.severity)
                        .padding(.top, 3)
                    Text(f.title ?? "Finding")
                        .font(.system(size: 10))
                        .foregroundStyle(f.severity == "critical" ? Color(nsColor: .systemRed) : Color(nsColor: .systemYellow))
                        .lineLimit(1)
                        .help([f.detail, f.hint].compactMap { $0 }.joined(separator: "\n\n"))
                }
            }
        }
    }
}
