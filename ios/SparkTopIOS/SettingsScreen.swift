import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var settings: IOSSettings
    @Environment(\.dismiss) private var dismiss
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://hai:5555", text: $settings.serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text("sparkDash server")
                } footer: {
                    Text("The sparkDash web dashboard URL. Both devices must reach it (LAN or Tailscale).")
                }

                Section {
                    SecureField("empty if the server is open", text: $settings.token)
                        .font(.body.monospaced())
                } header: {
                    Text("Access token")
                } footer: {
                    Text("Stored in the iOS Keychain. Leave empty for token-less installs.")
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        if testing {
                            HStack { ProgressView(); Text("Testing…") }
                        } else {
                            Text("Test connection")
                        }
                    }
                    .disabled(testing)
                    if let testResult {
                        Text(testResult).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    LabeledContent("Version", value: "0.10.0")
                    LabeledContent("Data source", value: "sparkDash WebSocket")
                } header: {
                    Text("About")
                } footer: {
                    Text("SparkTop is a thin client for sparkDash — the server collects everything; this app renders the live fleet snapshot.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func testConnection() {
        testing = true
        testResult = nil
        Task {
            defer { Task { @MainActor in testing = false } }
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
