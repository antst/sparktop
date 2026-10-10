import SwiftUI

/// Shared UI state (which "page" the popover shows).
final class AppUI: ObservableObject {
    @Published var showSettings = false
}

/// Root of the popover: swaps between the fleet overview and settings.
struct RootView: View {
    @ObservedObject var store: SnapshotStore
    @ObservedObject var settings: Settings
    @ObservedObject var ui: AppUI

    var body: some View {
        Group {
            if ui.showSettings {
                SettingsView(store: store, settings: settings, ui: ui)
            } else {
                OverviewView(store: store, settings: settings, ui: ui)
            }
        }
        .frame(width: 372, height: ui.showSettings ? 420 : 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Fleet overview: header with connection state, scrollable per-unit cards,
/// footer with last-update time and an open-in-browser button.
struct OverviewView: View {
    @ObservedObject var store: SnapshotStore
    let settings: Settings
    @ObservedObject var ui: AppUI

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
    }

    // MARK: Fleet summary strip

    private var fleetStrip: some View {
        let summary = store.fleetSummary
        let online = store.sparks.filter { $0.isOnline }
        let llms = online.flatMap { $0.metrics?.llm ?? [] }.filter { $0.available == true }
        var decodeTps = 0.0
        for l in llms { decodeTps += l.generationTps ?? 0 }
        var memUsed = 0.0
        for s in online { memUsed += s.metrics?.unifiedMemory?.used ?? s.metrics?.ram?.used ?? 0 }
        let todayValue: String
        if let tokens = store.tokensToday {
            todayValue = Fmt.tok(tokens.completion)
        } else {
            todayValue = "…"
        }
        return HStack(spacing: 0) {
            StatBlock(icon: "bolt.fill", value: Fmt.watts(summary.gpuPowerW), label: "POWER",
                      help: "Fleet GPU power draw right now")
            StatBlock(icon: "arrow.down.circle", value: "\(Fmt.tpsShort(decodeTps)) tok/s", label: "DECODE",
                      help: "Fleet decode throughput across all serving LLMs")
            StatBlock(icon: "memorychip", value: Fmt.gb(memUsed), label: "MEMORY",
                      help: "Memory in use across the fleet")
            StatBlock(icon: "number", value: todayValue, label: "TOK TODAY",
                      help: store.tokensToday.map { "Tokens today: \(Fmt.tok($0.completion)) generated · \(Fmt.tok($0.prompt)) prefill" } ?? "Tokens generated today (waiting for data)")
        }
        .padding(.vertical, 6)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(sparkAccent)
            Text("SparkTop")
                .font(.system(size: 13, weight: .semibold))
            connectionBadge
            Spacer()
            Button {
                ui.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var connectionBadge: some View {
        HStack(spacing: 4) {
            switch store.state {
            case .connected:
                Circle().fill(Color(nsColor: .systemGreen)).frame(width: 6, height: 6)
                Text("live \(Int(store.refreshIntervalMs / 1000))s")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
            case .connecting:
                ProgressView()
                    .controlSize(.mini)
                Text("connecting…")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            case .idle:
                EmptyView()
            case .disconnected:
                Circle().fill(Color(nsColor: .systemRed)).frame(width: 6, height: 6)
                Text("reconnecting…")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            case .authFailed:
                Circle().fill(Color(nsColor: .systemRed)).frame(width: 6, height: 6)
                Text("auth failed")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .authFailed(let message):
            VStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                Button("Open Settings") { ui.showSettings = true }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        case .idle, .connecting, .disconnected:
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting to sparkDash…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if case .disconnected(let reason) = store.state {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                if store.sparks.isEmpty {
                    Button("Settings…") { ui.showSettings = true }
                        .controlSize(.small)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .overlay(alignment: .top) { staleDataBanner }
        case .connected:
            if store.sparks.isEmpty {
                Text("No units in the fleet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                cards
            }
        }
    }

    /// When disconnected but we still hold a snapshot, keep showing it with a
    /// staleness banner — better than blanking the view on a hiccup.
    @ViewBuilder
    private var staleDataBanner: some View {
        if !store.sparks.isEmpty {
            Text("Showing last known data")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
    }

    private var cards: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                fleetStrip
                ForEach(store.sparks.indices, id: \.self) { i in
                    SparkCardView(spark: store.sparks[i])
                }
                activitySection
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
    }

    // MARK: Recent activity (fleet event log, newest first)

    @ViewBuilder
    private var activitySection: some View {
        if !store.recentEvents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("RECENT ACTIVITY")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.tertiary)
                ForEach(store.recentEvents) { event in
                    HStack(alignment: .top, spacing: 5) {
                        Circle()
                            .fill(severityColor(event.severity))
                            .frame(width: 5, height: 5)
                            .padding(.top, 3)
                        Text(event.message ?? event.type ?? "")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Fmt.relativeTime(event.ts))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            let summary = store.fleetSummary
            Text("\(summary.online)/\(summary.total) online")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            if summary.gpuPowerW > 0 {
                Text("·")
                    .foregroundStyle(.tertiary)
                Label(Fmt.watts(summary.gpuPowerW), systemImage: "bolt.fill")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let last = store.lastSnapshotAt {
                Text(last, style: .time)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .help("Last snapshot received")
            }
            Button {
                if let url = settings.base {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("sparkDash", systemImage: "arrow.up.right.square")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(sparkAccent)
            .help("Open sparkDash in the browser")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
