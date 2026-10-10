import Foundation

// MARK: - sparkDash WebSocket snapshot models
//
// Decoded from the payload pushed on ws://<host>/ws?token=…:
//   { type: "snapshot", generatedAt, refreshInterval, sparks: [...] }
//
// Every field is optional on purpose: sparkDash evolves, and a missing or
// reshaped field must degrade to "—" instead of dropping the whole snapshot.

struct WsEnvelope: Decodable {
    let type: String?
    let generatedAt: Double?
    let sparks: [SparkSnapshot]?
    let refreshInterval: Double? // milliseconds
}

struct SparkSnapshot: Decodable {
    let id: String?
    let name: String?
    let kind: String?            // "spark" | "host"
    let platform: String?
    let online: Bool?
    let offlineReason: String?
    let uptime: Double?          // seconds
    let lanIp: String?
    let role: String?            // "head" | "worker" | "standalone"
    let workerNode: Bool?
    let workerLabel: String?
    let llmMonitoring: Bool?
    let comfyMonitoring: Bool?
    let health: [HealthFinding]?
    let hardware: Hardware?
    let metrics: Metrics?
}

struct Hardware: Decodable {
    let device: String?
    let cpuModel: String?
    let cpuCores: Int?
    let totalMemoryGB: Int?
    let gpuChip: String?
    let cudaDriver: String?
    let gpuCount: Int?
}

struct Metrics: Decodable {
    let gpu: GpuMetrics?
    let cpu: CpuMetrics?
    let ram: RamMetrics?
    let unifiedMemory: UnifiedMemory?
    let llm: [LlmStatus]?
    let network: NetworkMetrics?
    let storage: [StorageMount]?
}

struct GpuMetrics: Decodable {
    let temperature: Double?
    let usage: Double?
    let power: Power?
    let vram: Memory?
    let throttle: Throttle?
}

struct Power: Decodable {
    let draw: Double?
    let limit: Double?
    let systemDraw: Double?
}

struct Memory: Decodable {
    let used: Double?
    let total: Double?
    let percentage: Double?
    let available: Double?
}

struct Throttle: Decodable {
    let active: Bool?
    let reason: String?
    let detail: String?
}

struct CpuMetrics: Decodable {
    let usage: Double?
    let temperature: Double?
    let draw: Double?
    let tdp: Double?
}

struct RamMetrics: Decodable {
    let used: Double?
    let total: Double?
    let percentage: Double?
}

struct UnifiedMemory: Decodable {
    let total: Double?
    let gpuUsed: Double?
    let cpuUsed: Double?
    let used: Double?
    let available: Double?
    let percentage: Double?
    let oomRisk: String?
    let bandwidth: Bandwidth?
}

struct Bandwidth: Decodable {
    let current: Double?  // GB/s
    let peak: Double?
}

struct LlmStatus: Decodable {
    let available: Bool?
    let backend: String?
    let modelId: String?
    let models: [String]?
    let contextLength: Int?
    let slotsActive: Int?
    let slotsTotal: Int?
    let generationTps: Double?
    let prefillTps: Double?
    let prefillActive: Bool?
    let kvCacheUsage: Double?   // 0…1
    let requestsRunning: Int?
    let requestsWaiting: Int?
    let error: String?
}

struct NetworkMetrics: Decodable {
    let primaryInterface: String?
    let linkSpeedMbps: Double?
    let interfaces: [NetInterface]?
}

struct NetInterface: Decodable {
    let name: String?
    let rxSpeed: Double?   // bytes/sec
    let txSpeed: Double?
    let operstate: String?
    let disabled: Bool?
}

struct StorageMount: Decodable {
    let device: String?
    let label: String?
    let used: Double?
    let total: Double?
    let available: Double?
    let percentage: Double?
    let disabled: Bool?
}

/// { id, severity: "warn" | "critical", title, detail, hint }
struct HealthFinding: Decodable {
    let id: String?
    let severity: String?
    let title: String?
    let detail: String?
    let hint: String?
}

// MARK: - REST poll payloads

/// GET /api/llm-token-totals/history?days=1 → daily UTC buckets.
struct TokenHistoryResponse: Decodable {
    let day: [TokenDayBucket]?
}

struct TokenDayBucket: Decodable {
    let t: String?
    let promptTokens: Int?
    let completionTokens: Int?
}

/// GET /api/events → fleet activity log (newest first).
struct EventsResponse: Decodable {
    let events: [FleetEvent]?
}

struct FleetEvent: Decodable, Identifiable {
    let id: Int64?
    let ts: Double?          // epoch ms
    let type: String?
    let severity: String?    // "success" | "warn" | "error" | "info" …
    let sparkName: String?
    let message: String?
}

// MARK: - Convenience

extension SparkSnapshot {
    var isSpark: Bool { (kind ?? "spark") == "spark" }
    var isOnline: Bool { online ?? false }
    var isWorker: Bool { workerNode ?? false }

    var roleLabel: String {
        if isWorker { return workerLabel?.uppercased() ?? "WORKER" }
        switch role {
        case "head": return "HEAD"
        case "standalone": return "STANDALONE"
        default: return isSpark ? "SPARK" : "GPU HOST"
        }
    }

    var hasCriticalFinding: Bool {
        (health ?? []).contains { $0.severity == "critical" }
    }

    var hasWarningFinding: Bool {
        (health ?? []).contains { $0.severity == "warn" }
    }

    /// Root filesystem mount (falls back to the first enabled mount).
    var rootStorage: StorageMount? {
        let all = (metrics?.storage ?? []).filter { $0.disabled != true }
        return all.first { $0.label == "/" } ?? all.first
    }
}

extension NetworkMetrics {
    var rxTotal: Double {
        (interfaces ?? []).filter { $0.disabled != true }.reduce(0) { $0 + ($1.rxSpeed ?? 0) }
    }
    var txTotal: Double {
        (interfaces ?? []).filter { $0.disabled != true }.reduce(0) { $0 + ($1.txSpeed ?? 0) }
    }
}
