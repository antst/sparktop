import AppKit
import Combine
import Foundation

/// Owns the NSStatusItem: a bolt icon plus a live fleet metric, tinted by
/// fleet health. Clicking toggles the popover; right-click opens a menu.
///
/// The item uses a sticky width: it grows to fit the widest metric rendered
/// so far but never shrinks back, so neighbors don't jitter as digits change.
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

    /// High-water mark of metric text width (points). Never shrinks during a
    /// session; reset when the metric mode changes.
    private var maxMetricWidth: CGFloat = 0
    private var lastMetricMode: MenuBarMetric?

    /// Cap so a pathological value can't eat the whole menu bar.
    private nonisolated static let maxMetricWidthCap: CGFloat = 110
    private nonisolated static let barHeight: CGFloat = 24
    private nonisolated static let boltWidth: CGFloat = 12
    private nonisolated static let gap: CGFloat = 3
    private nonisolated static let sidePadding: CGFloat = 5

    init(store: SnapshotStore, settings: Settings, popover: NSPopover) {
        self.store = store
        self.settings = settings
        self.popover = popover
        super.init()
    }

    func install(openSettings: @escaping () -> Void, openDashboard: @escaping () -> Void) {
        self.openSettings = openSettings
        self.openDashboard = openDashboard
        let item = NSStatusBar.system.statusItem(withLength: Self.statusLength(metricWidth: 0))
        if let button = item.button {
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

    static func statusLength(metricWidth: CGFloat) -> CGFloat {
        Self.sidePadding + Self.boltWidth + Self.gap + metricWidth + Self.sidePadding
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
        // Derive behavior from the setting at every open — the setting and
        // the popover can never drift apart, even across upgrades.
        popover.behavior = settings.popoverBehavior
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
            return "\(Int(watts.rounded()))W"
        case .gpu:
            var busiest = 0.0
            for s in online { busiest = max(busiest, s.metrics?.gpu?.usage ?? 0) }
            return "\(Int(busiest.rounded()))%"
        case .decode:
            var tps = 0.0
            for s in online {
                for l in s.metrics?.llm ?? [] where l.available == true {
                    tps += l.generationTps ?? 0
                }
            }
            return "\(Fmt.tpsShort(tps)) t/s"
        case .memory:
            var usedMB = 0.0
            for s in online { usedMB += s.metrics?.unifiedMemory?.used ?? s.metrics?.ram?.used ?? 0 }
            return "\(Int((usedMB / 1024).rounded()))G"
        }
    }

    private func render(sparks: [SparkSnapshot], state: SnapshotStore.ConnState, metric: MenuBarMetric) {
        guard let button = statusItem?.button else { return }
        let summary = SnapshotStore.summarize(sparks)

        var title = metricTitle(metric, sparks: sparks)
        var color: NSColor = .labelColor
        var isTemplate = true

        switch state {
        case .connected, .idle, .connecting:
            if summary.hasCritical {
                color = .systemRed
                isTemplate = false
            } else if summary.hasOffline || summary.hasWarning {
                color = .systemYellow
                isTemplate = false
            }
        case .disconnected, .authFailed:
            title = ""
            color = .systemRed
            isTemplate = false
        }

        // Sticky width: grow to the widest value seen, never shrink back.
        if metric != lastMetricMode {
            maxMetricWidth = 0
            lastMetricMode = metric
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
        let attributed = NSAttributedString(string: title, attributes: [.font: font])
        let textWidth = ceil(attributed.size().width)
        if textWidth > maxMetricWidth {
            maxMetricWidth = min(textWidth, Self.maxMetricWidthCap)
        }

        let scale = button.window?.backingScaleFactor ?? 2
        let canvasWidth = Self.statusLength(metricWidth: maxMetricWidth)
        let image = Self.drawStatusImage(
            width: canvasWidth,
            height: Self.barHeight,
            scale: scale,
            boltSymbol: "bolt.fill",
            title: title,
            font: font,
            color: color
        )
        image.isTemplate = isTemplate
        image.accessibilityDescription = "SparkTop"
        button.image = image
        button.imagePosition = .imageLeading
        button.attributedTitle = NSAttributedString()
        button.contentTintColor = nil
        statusItem?.length = canvasWidth

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

    /// Renders bolt + metric text into a fixed-size canvas so the item keeps
    /// a stable width. Drawn at the backing scale for retina crispness.
    nonisolated static func drawStatusImage(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        boltSymbol: String,
        title: String,
        font: NSFont,
        color: NSColor
    ) -> NSImage {
        let pixelsW = max(1, Int(width * scale))
        let pixelsH = max(1, Int(height * scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsW,
            pixelsHigh: pixelsH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: NSColorSpaceName.calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage()
        }
        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return NSImage() }
        NSGraphicsContext.current = ctx

        let x: CGFloat = sidePadding

        // Bolt, vertically centered, scaled to the square box.
        if var bolt = NSImage(systemSymbolName: boltSymbol, accessibilityDescription: nil) {
            let box = boltWidth
            let config = NSImage.SymbolConfiguration(pointSize: box, weight: .medium)
            bolt = bolt.withSymbolConfiguration(config) ?? bolt
            let src = bolt.size
            let fit = min(box / src.width, (box * 1.25) / src.height)
            let drawW = src.width * fit
            let drawH = src.height * fit
            let dy = (height - drawH) / 2
            let rect = NSRect(x: x, y: dy, width: drawW, height: drawH)
            // Render the symbol, then tint it by painting the alpha mask.
            let tinted = NSImage(size: bolt.size)
            tinted.lockFocusFlipped(false)
            bolt.draw(in: NSRect(origin: .zero, size: bolt.size))
            color.set()
            NSRect(origin: .zero, size: bolt.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: rect)
        }

        // Metric text, right-aligned in the sticky canvas: the unit suffix
        // (" t/s") stays put while digits grow leftward into reserved space.
        if !title.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let attr = NSAttributedString(string: title, attributes: attrs)
            let size = attr.size()
            let tx = width - sidePadding - ceil(size.width)
            let ty = (height - size.height) / 2
            attr.draw(at: NSPoint(x: tx, y: ty))
        }

        let image = NSImage()
        image.addRepresentation(rep)
        return image
    }
}
