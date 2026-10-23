import Foundation
import SparkTopCore

/// What the menu bar icon displays next to the bolt.
public enum MenuBarMetric: String, CaseIterable, Identifiable {
    case power      // fleet GPU power draw: "267W"
    case gpu        // busiest GPU utilization: "94%"
    case decode     // fleet decode throughput: "82 t/s"
    case memory     // fleet memory in use: "290G"
    case none       // icon only

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .power: return "Fleet power"
        case .gpu: return "Busiest GPU"
        case .decode: return "Decode tok/s"
        case .memory: return "Memory in use"
        case .none: return "Icon only"
        }
    }
}

/// macOS-specific settings on top of the shared server configuration.
final class Settings: ServerConfig {
    static let shared = Settings()
    private static let iconMetricKey = "iconMetric"
    private static let keepPopoverFrontKey = "keepPopoverFront"

    /// What the menu bar icon shows.
    @Published var iconMetric: MenuBarMetric = .power {
        didSet { UserDefaults.standard.set(iconMetric.rawValue, forKey: Self.iconMetricKey) }
    }
    /// true: popover stays open until dismissed via the bolt (or Esc).
    /// false (default): popover auto-hides when focus moves elsewhere.
    @Published var keepPopoverFront: Bool = false {
        didSet { UserDefaults.standard.set(keepPopoverFront, forKey: Self.keepPopoverFrontKey) }
    }

    private init() {
        super.init(defaultServerURL: "http://hai:5555")
        iconMetric = MenuBarMetric(rawValue: UserDefaults.standard.string(forKey: Self.iconMetricKey) ?? "") ?? .power
        keepPopoverFront = UserDefaults.standard.bool(forKey: Self.keepPopoverFrontKey)
        Self.log("settings loaded: server=\(serverURL) metric=\(iconMetric.rawValue) keepPopoverFront=\(keepPopoverFront)")
    }
}
