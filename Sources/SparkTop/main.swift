import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings.shared
    let store = SnapshotStore(settings: Settings.shared)
    let ui = AppUI()
    let popover = NSPopover()
    var statusController: StatusItemController?
    private var settingsCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyPopoverBehavior()
        popover.animates = true
        // Debug: `--pin` forces the pinned behavior regardless of settings.
        if CommandLine.arguments.contains("--pin") {
            popover.behavior = .applicationDefined
        }

        Task { @MainActor in
            let root = RootView(store: self.store, settings: self.settings, ui: self.ui)
            self.popover.contentViewController = NSHostingController(rootView: root)

            let controller = StatusItemController(store: self.store, settings: self.settings, popover: self.popover)
            controller.install(
                openSettings: { [weak self] in
                    guard let self else { return }
                    self.ui.showSettings = true
                    self.statusController?.show()
                },
                openDashboard: { [weak self] in
                    guard let self else { return }
                    if let url = self.settings.base {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
            self.statusController = controller

            self.store.start()

            // Live-apply popover behavior when the setting changes.
            self.settingsCancellable = self.settings.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    Task { @MainActor in self?.applyPopoverBehavior() }
                }

            // Debug/demo helper: `--open` opens the popover on launch.
            if CommandLine.arguments.contains("--open") {
                try? await Task.sleep(nanoseconds: 300_000_000)
                controller.show()
                FileHandle.standardError.write(Data("[sparktop] popover shown: \(self.popover.isShown)\n".utf8))
            }
        }
    }
    /// Popover pinned in front vs auto-hide on losing focus.
    private func applyPopoverBehavior() {
        popover.behavior = settings.keepPopoverFront ? .applicationDefined : .transient
    }
}

// Entry point (this is the target's main.swift).
let appDelegate = AppDelegate()
let app = NSApplication.shared
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
