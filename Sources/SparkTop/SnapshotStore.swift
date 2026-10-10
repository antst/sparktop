import Foundation
import Combine

/// Live fleet state: connects to sparkDash over WebSocket and keeps the last
/// snapshot. Reconnects with capped exponential backoff; distinguishes "server
/// down" from "token rejected" by probing GET /api/health over REST.
@MainActor
final class SnapshotStore: ObservableObject {
    enum ConnState: Equatable {
        case idle
        case connecting
        case connected
        case disconnected(String)
        case authFailed(String)
    }

    @Published private(set) var sparks: [SparkSnapshot] = []
    @Published private(set) var state: ConnState = .idle
    @Published private(set) var lastSnapshotAt: Date?
    @Published private(set) var refreshIntervalMs: Double = 2000
    @Published private(set) var tokensToday: TokensToday?
    @Published private(set) var recentEvents: [FleetEvent] = []

    struct TokensToday: Equatable {
        var completion: Int
        var prompt: Int
    }

    private nonisolated(unsafe) let settings: Settings
    private nonisolated(unsafe) let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var backoff: TimeInterval = 1
    private var pingTimer: Timer?
    private var watchdogTimer: Timer?
    private var restTimer: Timer?
    private var retryItem: DispatchWorkItem?
    private var authTask: Task<Void, Never>?

    private nonisolated static func log(_ message: String) {
        FileHandle.standardError.write(Data("[sparktop] \(message)\n".utf8))
    }

    /// Nonisolated so the app delegate (created before the main-actor hop) can
    /// construct the store; all mutation happens on the main actor.
    nonisolated init(settings: Settings, session: URLSession = URLSession(configuration: .default)) {
        self.settings = settings
        self.session = session
    }

    // MARK: Lifecycle

    func start() {
        stopTimers()
        backoff = 1
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.watchdogTick() }
        }
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendPing() }
        }
        restTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollRest() }
        }
        pollRest()
        connect()
    }

    func reconnect() {
        retryItem?.cancel()
        teardownSocket()
        backoff = 1
        start()
    }

    func stop() {
        retryItem?.cancel()
        teardownSocket()
        stopTimers()
        state = .idle
    }

    private func stopTimers() {
        pingTimer?.invalidate(); pingTimer = nil
        watchdogTimer?.invalidate(); watchdogTimer = nil
        restTimer?.invalidate(); restTimer = nil
    }

    private func teardownSocket() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    // MARK: Connection

    private func connect() {
        retryItem?.cancel()
        guard let url = settings.wsURL() else {
            Self.log("no server URL configured (raw: \(settings.serverURL))")
            state = .disconnected("No sparkDash server URL configured")
            return
        }
        Self.log("connecting to \(url)")
        state = .connecting
        let t = session.webSocketTask(with: url)
        t.resume()
        task = t
        receiveNext()
    }

    private func receiveNext() {
        task?.receive { [weak self] result in
            Task { @MainActor in self?.handleReceive(result) }
        }
    }

    private func handleReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(.string(let text)):
            ingest(text)
            receiveNext()
        case .success(.data(let data)):
            ingest(String(decoding: data, as: UTF8.self))
            receiveNext()
        case .success:
            receiveNext()
        case .failure(let error):
            scheduleReconnect(reason: error.localizedDescription)
        }
    }

    private func ingest(_ text: String) {
        guard
            let env = try? JSONDecoder().decode(WsEnvelope.self, from: Data(text.utf8)),
            env.type == "snapshot",
            let sparks = env.sparks
        else { return }
        self.sparks = sparks
        self.lastSnapshotAt = Date()
        self.state = .connected
        self.backoff = 1
        Self.log("snapshot: \(sparks.count) units, interval \(env.refreshInterval ?? 0) ms")
        if let ms = env.refreshInterval, ms > 0 {
            self.refreshIntervalMs = ms
        }
    }

    private func sendPing() {
        guard let task else { return }
        task.sendPing { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                self?.scheduleReconnect(reason: "ping failed")
            }
        }
    }

    /// A connected socket that has gone quiet means the stream is dead.
    private func watchdogTick() {
        guard state == .connected, let last = lastSnapshotAt else { return }
        let threshold = max(10, refreshIntervalMs / 1000 * 5)
        if Date().timeIntervalSince(last) > threshold {
            scheduleReconnect(reason: "stream went quiet")
        }
    }

    private func scheduleReconnect(reason: String) {
        Self.log("reconnect scheduled: \(reason)")
        teardownSocket()
        state = .disconnected(reason)

        authTask?.cancel()
        authTask = Task { [weak self] in
            guard let self else { return }
            let tokenOK = await self.checkAuth()
            if Task.isCancelled { return }
            if !tokenOK {
                self.state = .authFailed("sparkDash rejected the access token")
                return
            }
            let delay = self.backoff
            self.backoff = min(30, self.backoff * 2)
            let item = DispatchWorkItem { [weak self] in self?.connect() }
            self.retryItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    /// GET /api/health — 200 means the token is accepted (or not required);
    /// 401 means the token is wrong and retrying is pointless.
    private func checkAuth() async -> Bool {
        guard let req = settings.restRequest("api/health") else { return true }
        do {
            let (_, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse {
                Self.log("auth check: HTTP \(http.statusCode)")
                return http.statusCode != 401 && http.statusCode != 403
            }
            return true
        } catch {
            Self.log("auth check failed: \(error.localizedDescription)")
            // Server unreachable — cannot tell; keep retrying.
            return true
        }
    }

    // MARK: REST polls (tokens today, recent activity)

    private func pollRest() {
        guard settings.base != nil else { return }
        Task { [weak self] in
            await self?.fetchTokensToday()
            await self?.fetchEvents()
        }
    }

    private func fetchTokensToday() async {
        guard let req = settings.restRequest("api/llm-token-totals/history", query: ["days": "1"]) else { return }
        guard let (data, _) = try? await session.data(for: req),
              let resp = try? JSONDecoder().decode(TokenHistoryResponse.self, from: data) else { return }
        let days = resp.day ?? []
        self.tokensToday = TokensToday(
            completion: days.reduce(0) { $0 + ($1.completionTokens ?? 0) },
            prompt: days.reduce(0) { $0 + ($1.promptTokens ?? 0) }
        )
    }

    private func fetchEvents() async {
        guard let req = settings.restRequest("api/events", query: ["limit": "3"]) else { return }
        guard let (data, _) = try? await session.data(for: req),
              let resp = try? JSONDecoder().decode(EventsResponse.self, from: data) else { return }
        self.recentEvents = resp.events ?? []
    }

    // MARK: Derived values for the menu bar

    struct FleetSummary {
        var total: Int = 0
        var online: Int = 0
        var gpuPowerW: Double = 0
        var hasOffline: Bool = false
        var hasCritical: Bool = false
        var hasWarning: Bool = false
    }

    var fleetSummary: FleetSummary {
        Self.summarize(sparks)
    }

    /// Pure computation so nonisolated callers (menu bar) can use it too.
    nonisolated static func summarize(_ sparks: [SparkSnapshot]) -> FleetSummary {
        var s = FleetSummary()
        s.total = sparks.count
        for spark in sparks {
            if spark.isOnline {
                s.online += 1
                s.gpuPowerW += spark.metrics?.gpu?.power?.draw ?? 0
                if spark.hasCriticalFinding { s.hasCritical = true }
                if spark.hasWarningFinding { s.hasWarning = true }
            } else {
                s.hasOffline = true
            }
        }
        return s
    }
}
