import AppKit
import Foundation

/// Small Keychain wrapper for the sparkDash access token.
/// Items the app creates itself are readable without prompts; foreign items
/// (e.g. seeded from the `security` CLI) can require user interaction, so
/// reads go through getAsync() and must never block startup.
enum Keychain {
    private static let service = "SparkTop"
    private static let account = "sparkdash-token"

    static func get() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String) {
        let data = value.data(using: .utf8) ?? Data()
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]

        let status = SecItemCopyMatching(base as CFDictionary, nil)
        if status == errSecSuccess {
            SecItemUpdate(base as CFDictionary, update as CFDictionary)
        } else if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
        // Other statuses (prompt required, denied): drop silently — the
        // on-disk cache in Settings keeps the token functional.
    }

    /// Reads the Keychain off the main thread with a timeout, so an ACL
    /// prompt for a foreign item can never block app startup. Returns nil
    /// on timeout, absence, or error — callers fall back to the cache.
    static func getAsync(timeout: TimeInterval = 1.0, completion: @escaping (String?) -> Void) {
        DispatchQueue.global().async {
            let box = TimeoutBox<String>()
            let worker = DispatchQueue(label: "sparktop.keychain.read")
            worker.async {
                let value = get()
                box.fulfill(value)
            }
            let value = box.wait(upTo: timeout)
            DispatchQueue.main.async { completion(value) }
        }
    }
}

/// One-shot value cell with a timeout, so a hung SecItem call is abandoned.
final class TimeoutBox<T> {
    private let sema = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var value: T?

    func fulfill(_ value: T?) {
        lock.lock(); self.value = value; lock.unlock()
        sema.signal()
    }

    func wait(upTo timeout: TimeInterval) -> T? {
        _ = sema.wait(timeout: .now() + timeout)
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

/// What the menu bar icon displays next to the bolt.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case power      // fleet GPU power draw: "267W"
    case gpu        // busiest GPU utilization: "94%"
    case decode     // fleet decode throughput: "82 t/s"
    case memory     // fleet memory in use: "290G"
    case none       // icon only

    var id: String { rawValue }

    var label: String {
        switch self {
        case .power: return "Fleet power"
        case .gpu: return "Busiest GPU"
        case .decode: return "Decode tok/s"
        case .memory: return "Memory in use"
        case .none: return "Icon only"
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private static let urlKey = "serverURL"
    private static let iconMetricKey = "iconMetric"
    private static let keepPopoverFrontKey = "keepPopoverFront"
    /// Plain-text cache of the token: instant startup, survives Keychain
    /// unavailability, and mirrors every Keychain write.
    private static let tokenCacheKey = "sparkdash-token-cache"

    /// Base URL of the sparkDash server, e.g. "http://hai:5555".
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: Self.urlKey) }
    }
    /// Bearer token for the sparkDash API (may be empty for open installs).
    @Published var token: String {
        didSet {
            UserDefaults.standard.set(token, forKey: Self.tokenCacheKey)
            Keychain.set(token)
        }
    }
    /// What the menu bar icon shows.
    @Published var iconMetric: MenuBarMetric {
        didSet { UserDefaults.standard.set(iconMetric.rawValue, forKey: Self.iconMetricKey) }
    }
    /// true: popover stays open until dismissed via the bolt (or Esc).
    /// false (default): popover auto-hides when focus moves elsewhere.
    @Published var keepPopoverFront: Bool {
        didSet { UserDefaults.standard.set(keepPopoverFront, forKey: Self.keepPopoverFrontKey) }
    }

    private init() {
        serverURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? "http://hai:5555"
        token = UserDefaults.standard.string(forKey: Self.tokenCacheKey) ?? ""
        iconMetric = MenuBarMetric(rawValue: UserDefaults.standard.string(forKey: Self.iconMetricKey) ?? "") ?? .power
        keepPopoverFront = UserDefaults.standard.bool(forKey: Self.keepPopoverFrontKey)
        Self.log("settings loaded: server=\(serverURL) metric=\(iconMetric.rawValue) keepPopoverFront=\(keepPopoverFront)")
        // If a Keychain item exists (created by this app) and the user has
        // not typed a different token in the meantime, prefer it.
        let cached = token
        Keychain.getAsync { [weak self] value in
            guard let self, let value else { return }
            if self.token == cached {
                self.token = value
            }
        }
    }

    /// Popover behavior — THE single source of truth, derived from the
    /// setting every time it is consulted. `--pin` forces pinned (debug).
    var popoverBehavior: NSPopover.Behavior {
        if CommandLine.arguments.contains("--pin") { return .applicationDefined }
        return keepPopoverFront ? .applicationDefined : .transient
    }

    static func log(_ message: String) {
        FileHandle.standardError.write(Data("[sparktop] \(message)\n".utf8))
    }

    /// Normalized base URL (scheme added, trailing slash dropped).
    var base: URL? {
        var raw = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        if !raw.contains("://") { raw = "http://" + raw }
        while raw.hasSuffix("/") { raw.removeLast() }
        return URL(string: raw)
    }

    /// ws://…/ws?token=… (wss for https).
    func wsURL() -> URL? {
        guard let base, var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
        comps.path = "/ws"
        if !token.isEmpty {
            comps.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        return comps.url
    }

    /// Authenticated REST request for GET <path> with optional query params.
    func restRequest(_ path: String, query: [String: String] = [:]) -> URLRequest? {
        guard let base else { return nil }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        comps?.path = "/" + clean
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else { return nil }
        var req = URLRequest(url: url)
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = 6
        return req
    }
}
