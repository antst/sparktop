import SwiftUI

/// Root: sidebar (fleet list) + detail on iPad, stacked navigation on iPhone.
struct RootView: View {
    @ObservedObject var store: SnapshotStore
    @ObservedObject var settings: IOSSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: String?
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(store.sparks.indices, id: \.self) { i in
                        let spark = store.sparks[i]
                        UnitRow(spark: spark)
                            .tag(spark.id)
                    }
                } header: {
                    Text("Fleet")
                } footer: {
                    connectionFooter
                }
                Section {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("SparkTop")
        } detail: {
            if let id = selection, let spark = store.sparks.first(where: { $0.id == id }) {
                UnitDetailView(spark: spark)
            } else {
                PlaceholderView(store: store)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsScreen(settings: settings)
        }
        .task {
            store.start()
        }
        .onChange(of: scenePhase) { phase in
            // iOS suspends sockets in the background; re-arm on foreground.
            if phase == .active {
                store.reconnect()
            }
        }
    }

    private var connectionFooter: some View {
        HStack(spacing: 6) {
            switch store.state {
            case .connected:
                Circle().fill(Color(uiColor: .systemGreen)).frame(width: 7, height: 7)
                Text("live · every \(Int(store.refreshIntervalMs / 1000))s")
            case .connecting, .idle:
                Text("connecting…")
            case .disconnected:
                Circle().fill(Color(uiColor: .systemRed)).frame(width: 7, height: 7)
                Text("reconnecting…")
            case .authFailed:
                Circle().fill(Color(uiColor: .systemRed)).frame(width: 7, height: 7)
                Text("auth failed — check token")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// Shown before a unit is selected (iPad) — the fleet summary.
struct PlaceholderView: View {
    let store: SnapshotStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                FleetStripView(store: store)
                ForEach(store.sparks.indices, id: \.self) { i in
                    SparkCard(spark: store.sparks[i])
                }
            }
            .padding()
        }
        .navigationTitle("Overview")
    }
}
