import Foundation

// MARK: - sparkDash WebSocket snapshot models
//
// Decoded from the payload pushed on ws://<host>/ws?token=…:
//   { type: "snapshot", generatedAt, refreshInterval, sparks: [...] }
//
// Every field is optional on purpose: sparkDash evolves, and a missing or
// reshaped field must degrade to "—" instead of dropping the whole snapshot.

public struct WsEnvelope: Decodable {
    public let type: String?
    public let generatedAt: Double?
    public let sparks: [SparkSnapshot]?
    public let refreshInterval: Double? // milliseconds
}

public struct SparkSnapshot: Decodable {
    public let id: String?
    public let name: String?
    public let kind: String?            // "spark" | "host"
    public let platform: String?
    public let online: Bool?
    public let offlineReason: String?
    public let uptime: Double?          // seconds
    public let lanIp: String?
    public let role: String?            // "head" | "worker" | "standalone"
    public let workerNode: Bool?
    public let workerLabel: String?
    public let llmMonitoring: Bool?
    public let comfyMonitoring: Bool?
    public let health: [HealthFinding]?
    public let hardware: Hardware?
    public let metrics: Metrics?
}

public struct Hardware: Decodable {
    public let device: String?
    public let cpuModel: String?
    public let cpuCores: Int?
    public let totalMemoryGB: Int?
    public let gpuChip: String?
    public let cudaDriver: String?
    public let gpuCount: Int?
}

public struct Metrics: Decodable {
    public let gpu: GpuMetrics?
    public let cpu: CpuMetrics?
    public let ram: RamMetrics?
    public let unifiedMemory: UnifiedMemory?
    public let llm: [LlmStatus]?
    public let network: NetworkMetrics?
    public let storage: [StorageMount]?
}

public struct GpuMetrics: Decodable {
    public let temperature: Double?
    public let usage: Double?
    public let power: Power?
    public let vram: Memory?
    public let throttle: Throttle?
    /// Per-card detail on multi-GPU hosts (the aggregate above stays the
    /// headline numbers so Overview cards need no changes).
    public let gpus: [PerGpu]?
}

public struct PerGpu: Decodable {
    public let index: Int?
    public let name: String?
    public let uuid: String?
    public let temperature: Double?
    public let usage: Double?
    public let power: Power?
    public let vram: Memory?
    public let throttle: Throttle?
}

public struct Power: Decodable {
    public let draw: Double?
    public let limit: Double?
    public let systemDraw: Double?
}

public struct Memory: Decodable {
    public let used: Double?
    public let total: Double?
    public let percentage: Double?
    public let available: Double?
}

public struct Throttle: Decodable {
    public let active: Bool?
    public let reason: String?
    public let detail: String?
}

public struct CpuMetrics: Decodable {
    public let usage: Double?
    public let temperature: Double?
    public let draw: Double?
    public let tdp: Double?
}

public struct RamMetrics: Decodable {
    public let used: Double?
    public let total: Double?
    public let percentage: Double?
}

public struct UnifiedMemory: Decodable {
    public let total: Double?
    public let gpuUsed: Double?
    public let cpuUsed: Double?
    public let used: Double?
    public let available: Double?
    public let percentage: Double?
    public let oomRisk: String?
    public let bandwidth: Bandwidth?
}

public struct Bandwidth: Decodable {
    public let current: Double?  // GB/s
    public let peak: Double?
}

public struct LlmStatus: Decodable {
    public let available: Bool?
    public let backend: String?
    public let modelId: String?
    public let models: [String]?
    public let contextLength: Int?
    public let slotsActive: Int?
    public let slotsTotal: Int?
    public let generationTps: Double?
    public let prefillTps: Double?
    public let prefillActive: Bool?
    public let kvCacheUsage: Double?   // 0…1
    public let requestsRunning: Int?
    public let requestsWaiting: Int?
    public let error: String?
}

public struct NetworkMetrics: Decodable {
    public let primaryInterface: String?
    public let linkSpeedMbps: Double?
    public let interfaces: [NetInterface]?
}

public struct NetInterface: Decodable {
    public let name: String?
    public let rxSpeed: Double?   // bytes/sec
    public let txSpeed: Double?
    public let operstate: String?
    public let disabled: Bool?
}

public struct StorageMount: Decodable {
    public let device: String?
    public let label: String?
    public let used: Double?
    public let total: Double?
    public let available: Double?
    public let percentage: Double?
    public let disabled: Bool?
}

/// { id, severity: "warn" | "critical", title, detail, hint }
public struct HealthFinding: Decodable {
    public let id: String?
    public let severity: String?
    public let title: String?
    public let detail: String?
    public let hint: String?
}

// MARK: - REST poll payloads

/// GET /api/llm-token-totals/history?days=1 → daily UTC buckets.
public struct TokenHistoryResponse: Decodable {
    public let day: [TokenDayBucket]?
}

public struct TokenDayBucket: Decodable {
    public let t: String?
    public let promptTokens: Int?
    public let completionTokens: Int?
}

/// GET /api/events → fleet activity log (newest first).
public struct EventsResponse: Decodable {
    public let events: [FleetEvent]?
}

public struct FleetEvent: Decodable, Identifiable {
    public let id: Int64?
    public let ts: Double?          // epoch ms
    public let type: String?
    public let severity: String?    // "success" | "warn" | "error" | "info" …
    public let sparkName: String?
    public let message: String?
}

// MARK: - Convenience

public extension SparkSnapshot {
    public var isSpark: Bool { (kind ?? "spark") == "spark" }
    public var isOnline: Bool { online ?? false }
    public var isWorker: Bool { workerNode ?? false }

    public var roleLabel: String {
        if isWorker { return workerLabel?.uppercased() ?? "WORKER" }
        switch role {
        case "head": return "HEAD"
        case "standalone": return "STANDALONE"
        default: return isSpark ? "SPARK" : "GPU HOST"
        }
    }

    public var hasCriticalFinding: Bool {
        (health ?? []).contains { $0.severity == "critical" }
    }

    public var hasWarningFinding: Bool {
        (health ?? []).contains { $0.severity == "warn" }
    }

    /// Root filesystem mount (falls back to the first enabled mount).
    public var rootStorage: StorageMount? {
        let all = (metrics?.storage ?? []).filter { $0.disabled != true }
        return all.first { $0.label == "/" } ?? all.first
    }
}

public extension NetworkMetrics {
    public var rxTotal: Double {
        (interfaces ?? []).filter { $0.disabled != true }.reduce(0) { $0 + ($1.rxSpeed ?? 0) }
    }
    public var txTotal: Double {
        (interfaces ?? []).filter { $0.disabled != true }.reduce(0) { $0 + ($1.txSpeed ?? 0) }
    }
}
