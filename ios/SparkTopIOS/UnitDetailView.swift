import SwiftUI

/// Full detail for one unit: GPU, memory, CPU, network, storage, LLM, health.
struct UnitDetailView: View {
    let spark: SparkSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if spark.isOnline, let m = spark.metrics {
                    gpuSection(m)
                    memorySection(m)
                    cpuSection(m)
                    networkSection(m)
                    storageSection(m)
                    llmSection(m)
                    healthSection
                } else {
                    Label("Offline" + (spark.offlineReason.map { " — \($0)" } ?? ""),
                          systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }
            }
            .padding()
        }
        .navigationTitle(spark.name ?? spark.id ?? "Unit")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(online: spark.isOnline)
            VStack(alignment: .leading, spacing: 2) {
                Text(spark.hardware?.device ?? (spark.isSpark ? "NVIDIA DGX Spark" : "GPU host"))
                    .font(.subheadline)
                HStack(spacing: 6) {
                    if let up = Fmt.uptime(spark.uptime) as String?, !up.isEmpty {
                        Text(up).font(.caption2.monospacedDigit())
                    }
                    if let lan = spark.lanIp {
                        Text(lan).font(.caption2.monospacedDigit())
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            RoleChip(text: spark.roleLabel)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    // MARK: Sections

    private func gpuSection(_ m: Metrics) -> some View {
        section("GPU") {
            if let gpu = m.gpu {
                MetricRow(label: "Usage", fraction: (gpu.usage ?? 0) / 100,
                          color: gpu.usage.map { $0 >= 90 ? Color(uiColor: .systemOrange) : sparkAccent } ?? sparkAccent,
                          value: Fmt.pct(gpu.usage))
                HStack(spacing: 12) {
                    labelPair("Temp", Fmt.temp(gpu.temperature))
                    labelPair("Draw", Fmt.watts(gpu.power?.draw))
                    if let limit = gpu.power?.limit {
                        labelPair("Limit", Fmt.watts(limit))
                    }
                    if let sys = gpu.power?.systemDraw {
                        labelPair("System", Fmt.watts(sys))
                    }
                }
                if let t = gpu.throttle {
                    Text(t.active == true ? "Throttled: \(t.reason ?? "unknown")" : (t.detail ?? "Clocks nominal"))
                        .font(.caption2).foregroundStyle(t.active == true ? Color(uiColor: .systemOrange) : .secondary)
                }
                if let gpus = gpu.gpus, gpus.count > 1 {
                    ForEach(gpus.indices, id: \.self) { i in
                        let g = gpus[i]
                        MetricRow(label: "GPU \(g.index ?? i)", fraction: (g.usage ?? 0) / 100,
                                  color: sparkAccent, value: "\(Fmt.temp(g.temperature)) · \(Fmt.pct(g.usage))")
                    }
                }
            }
        }
    }

    private func memorySection(_ m: Metrics) -> some View {
        section(spark.isSpark ? "Unified memory" : "Memory") {
            if spark.isSpark, let um = m.unifiedMemory, let total = um.total, total > 0 {
                SegmentedBar(segments: [
                    ((um.gpuUsed ?? 0) / total, sparkAccent),
                    ((um.cpuUsed ?? 0) / total, Color(uiColor: .systemBlue)),
                ])
                HStack(spacing: 12) {
                    labelPair("GPU", Fmt.gb(um.gpuUsed))
                    labelPair("CPU", Fmt.gb(um.cpuUsed))
                    labelPair("Free", Fmt.gb(um.available))
                }
                if let bw = um.bandwidth, let current = bw.current, current > 0 {
                    Text("Bandwidth \(Int(current)) / \(Int(bw.peak ?? 0)) GB/s")
                        .font(.caption2).foregroundStyle(.secondary)
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
        }
    }

    private func cpuSection(_ m: Metrics) -> some View {
        section("CPU") {
            if let cpu = m.cpu {
                HStack(spacing: 12) {
                    labelPair("Usage", Fmt.pct(cpu.usage))
                    if cpu.temperature != nil { labelPair("Temp", Fmt.temp(cpu.temperature)) }
                    if let draw = cpu.draw, let tdp = cpu.tdp {
                        labelPair("Draw", "\(Int(draw.rounded())) / \(Int(tdp.rounded())) W")
                    }
                }
                if let model = spark.hardware?.cpuModel {
                    Text(model).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private func networkSection(_ m: Metrics) -> some View {
        section("Network") {
            if let net = m.network {
                HStack(spacing: 12) {
                    labelPair("↓", Fmt.speed(net.rxTotal))
                    labelPair("↑", Fmt.speed(net.txTotal))
                    if let link = net.linkSpeedMbps {
                        labelPair("Link", link >= 1000 ? "\(Int(link / 1000)) Gb/s" : "\(Int(link)) Mb/s")
                    }
                }
                let ifaces = (net.interfaces ?? []).filter { $0.disabled != true }.prefix(4)
                ForEach(Array(ifaces).indices, id: \.self) { i in
                    let iff = ifaces[i]
                    HStack {
                        Text(iff.name ?? "?").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Text("↓ \(Fmt.speed(iff.rxSpeed)) ↑ \(Fmt.speed(iff.txSpeed))")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func storageSection(_ m: Metrics) -> some View {
        let mounts = (m.storage ?? []).filter { $0.disabled != true }
        return Group {
            if !mounts.isEmpty {
                section("Storage") {
                    ForEach(mounts.indices, id: \.self) { i in
                        let mount = mounts[i]
                        MetricRow(label: mount.label ?? mount.device ?? "?",
                                  fraction: Double(mount.percentage ?? 0) / 100,
                                  color: (mount.percentage ?? 0) >= 90 ? Color(uiColor: .systemRed) : sparkAccent,
                                  value: "\(Fmt.gb(mount.used)) / \(Fmt.gb(mount.total))")
                    }
                }
            }
        }
    }

    private func llmSection(_ m: Metrics) -> some View {
        let llms = m.llm ?? []
        return Group {
            if spark.llmMonitoring == true || !llms.isEmpty {
                section("LLM") {
                    if llms.isEmpty {
                        Text("No LLM endpoint configured").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(llms.indices, id: \.self) { i in
                        let l = llms[i]
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(l.available == true ? Color(uiColor: .systemGreen) : Color(uiColor: .systemGray))
                                    .frame(width: 7, height: 7)
                                Text((l.backend ?? "unknown").uppercased())
                                    .font(.system(size: 10, weight: .semibold)).tracking(0.4)
                                Text(l.modelId ?? l.models?.first ?? "—").font(.footnote).lineLimit(1)
                            }
                            HStack(spacing: 12) {
                                labelPair("Decode", Fmt.tps(l.generationTps))
                                if let pre = l.prefillTps, pre > 0 {
                                    labelPair("Prefill", Fmt.tps(pre))
                                }
                                if let kv = l.kvCacheUsage {
                                    labelPair("KV cache", "\(Int((kv * 100).rounded()))%")
                                }
                                if let run = l.requestsRunning {
                                    labelPair("Requests", "\(run)" + (l.requestsWaiting.map { " (+\($0) wait)" } ?? ""))
                                }
                            }
                            if let ctx = l.contextLength {
                                Text("Context \(Fmt.tok(ctx))").font(.caption2).foregroundStyle(.tertiary)
                            }
                            if let error = l.error, l.available != true {
                                Text(error).font(.caption2).foregroundStyle(Color(uiColor: .systemRed))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        let findings = spark.health ?? []
        if !findings.isEmpty {
            section("Health") {
                ForEach(findings.indices, id: \.self) { i in
                    let f = findings[i]
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Circle().fill(severityColor(f.severity)).frame(width: 6, height: 6)
                            Text(f.title ?? "Finding").font(.footnote.weight(.medium))
                        }
                        if let detail = f.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                        if let hint = f.hint {
                            Text(hint).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: Helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func labelPair(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9, weight: .medium)).tracking(0.4).foregroundStyle(.tertiary)
            Text(value).font(.footnote.monospacedDigit())
        }
    }
}
