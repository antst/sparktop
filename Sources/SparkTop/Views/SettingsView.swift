import AppKit
import SparkTopCore
import SwiftUI
import ServiceManagement

/// Settings: sparkDash server URL, access token, launch-at-login.
/// The token is stored in the login Keychain.
struct SettingsView: View {
    @ObservedObject var store: SnapshotStore
    @ObservedObject var settings: Settings
    @ObservedObject var ui: AppUI

    @State private var testResult: String?
    @State private var testRunning = false
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    ui.showSettings = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Back")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("sparkDash server")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("http://hai:5555", text: $settings.serverURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11).monospaced())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Access token")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                SecureField("empty if the server is open", text: $settings.token)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11).monospaced())
                Text("Stored in the Keychain. Leave empty for token-less installs.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Menu bar shows")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("Menu bar shows", selection: $settings.iconMetric) {
                    ForEach(MenuBarMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Text("The bolt icon tints amber when a unit is offline or has findings, red on critical — whatever the metric.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Button {
                    testConnection()
                } label: {
                    if testRunning {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("Test")
                    }
                }
                .controlSize(.small)
                .disabled(testRunning)

                Button("Save & Reconnect") {
                    store.reconnect()
                    ui.showSettings = false
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }

            if let testResult {
                Text(testResult)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            if let launchError {
                Text(launchError)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Divider()

            Toggle(isOn: $settings.keepPopoverFront) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep popover in front")
                        .font(.system(size: 11))
                    Text("Off: it auto-hides when you focus something else.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { want in
                    do {
                        if want {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        launchError = nil
                    } catch {
                        launchError = "Launch at login: \(error.localizedDescription)"
                    }
                }
            )) {
                Text("Launch at login")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit SparkTop", systemImage: "power")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(nsColor: .systemRed))
            .help("Quit the app (also available via right-click on the bolt)")

            Spacer()
        }
        .padding(14)
    }

    private func testConnection() {
        testRunning = true
        testResult = nil
        Task {
            defer { Task { @MainActor in testRunning = false } }
            guard let req = settings.restRequest("api/health") else {
                await MainActor.run { testResult = "Invalid server URL." }
                return
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
                    await MainActor.run { testResult = "Reachable, but the token was rejected (HTTP \(http.statusCode))." }
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let authMode = json["authMode"] as? String {
                    await MainActor.run { testResult = "OK — auth mode: \(authMode)" }
                } else {
                    await MainActor.run { testResult = "Reachable." }
                }
            } catch {
                await MainActor.run { testResult = "Unreachable: \(error.localizedDescription)" }
            }
        }
    }
}
