import AppKit
import Combine
import Foundation

/// Owns the NSStatusItem: a bolt icon plus a live fleet metric, tinted by
/// fleet health. Clicking toggles the popover.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: SnapshotStore
    private let settings: Settings
    private let popover: NSPopover
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var openSettings: (() -> Void)?
    private var openDashboard: (() -> Void)?

    init(store: SnapshotStore, settings: Settings, popover: NSPopover) {
        self.store = store
        self.settings = settings
        self.popover = popover
        super.init()
    }

    func install(openSettings: @escaping () -> Void, openDashboard: @escaping () -> Void) {
        self.openSettings = openSettings
        self.openDashboard = openDashboard
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "SparkTop")
            button.image?.isTemplate = true
            button.imageHugsTitle = true
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        cancellable = store.$sparks
            .combineLatest(store.$state)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.renderCurrent() }
            }
        // Re-render when the user picks a different menu bar metric.
        settingsCancellable = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.renderCurrent() }
            }
        renderCurrent()
    }

    @objc private func togglePopover() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || (NSApp.currentEvent?.type == .leftMouseUp && NSApp.currentEvent?.modifierFlags.contains(.control) == true)
        if isRightClick {
            showContextMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    // MARK: Right-click menu

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let dash = NSMenuItem(title: "Open sparkDash", action: #selector(openDashboardAction), keyEquivalent: "")
        dash.target = self
        dash.isEnabled = openDashboard != nil
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.isEnabled = openSettings != nil
        menu.addItem(dash)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit SparkTop", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        button.menu = menu
        button.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.button?.menu = nil
    }

    @objc private func openDashboardAction() { openDashboard?() }
    @objc private func openSettingsAction() { openSettings?() }
    @objc private func quitAction() { NSApp.terminate(nil) }

    func show() {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    // MARK: Rendering

    private func renderCurrent() {
        render(sparks: store.sparks, state: store.state, metric: settings.iconMetric)
    }

    /// Metric text next to the bolt, per the user's menu bar preference.
    private func metricTitle(_ metric: MenuBarMetric, sparks: [SparkSnapshot]) -> String {
        let online = sparks.filter { $0.isOnline }
        switch metric {
        case .none:
            return ""
        case .power:
            var watts = 0.0
            for s in online { watts += s.metrics?.gpu?.power?.draw ?? 0 }
            return watts > 0 ? " \(Int(watts.rounded()))W" : ""
        case .gpu:
            var busiest = 0.0
            for s in online { busiest = max(busiest, s.metrics?.gpu?.usage ?? 0) }
            return busiest > 0 ? " \(Int(busiest.rounded()))%" : ""
        case .decode:
            var tps = 0.0
            for s in online {
                for l in s.metrics?.llm ?? [] where l.available == true {
                    tps += l.generationTps ?? 0
                }
            }
            return tps > 0 ? " \(Fmt.tpsShort(tps)) t/s" : ""
        case .memory:
            var usedMB = 0.0
            for s in online { usedMB += s.metrics?.unifiedMemory?.used ?? s.metrics?.ram?.used ?? 0 }
            return usedMB > 0 ? " \(Int((usedMB / 1024).rounded()))G" : ""
        }
    }

    private func render(sparks: [SparkSnapshot], state: SnapshotStore.ConnState, metric: MenuBarMetric) {
        guard let button = statusItem?.button else { return }
        let summary = SnapshotStore.summarize(sparks)

        var title = metricTitle(metric, sparks: sparks)
        var color = NSColor.labelColor
        var tint: NSColor? = nil

        switch state {
        case .connected, .idle, .connecting:
            if summary.hasCritical {
                color = .systemRed
            } else if summary.hasOffline || summary.hasWarning {
                color = .systemYellow
            }
        case .disconnected, .authFailed:
            title = ""
            tint = .systemRed
        }

        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium),
                .foregroundColor: color,
            ]
        )
        button.contentTintColor = tint

        let stateText: String
        switch state {
        case .connected: stateText = "sparkDash connected"
        case .connecting: stateText = "connecting…"
        case .idle: stateText = "idle"
        case .disconnected(let why): stateText = "sparkDash offline (\(why))"
        case .authFailed: stateText = "sparkDash auth failed"
        }
        button.toolTip = "SparkTop — \(summary.online)/\(summary.total) online · GPU \(Int(summary.gpuPowerW.rounded())) W\n\(stateText)"
    }
}
