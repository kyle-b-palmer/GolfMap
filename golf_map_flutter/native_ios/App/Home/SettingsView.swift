import GolfCore
import GolfDesign
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.autoAdvanceHoles) private var autoAdvance = true
    @AppStorage(SettingsKey.showScoreTarget) private var showScoreTarget = true
    @AppStorage(SettingsKey.keepScreenAwake) private var keepAwake = true
    @AppStorage(SettingsKey.mapImagery) private var imagery = true
    @AppStorage(SettingsKey.idealLineEnabled) private var idealLine = true
    @AppStorage(SettingsKey.showShotDispersion) private var dispersion = false
    @AppStorage(SettingsKey.healthWorkoutMode) private var healthMode = HealthWorkoutMode.always.rawValue
    @AppStorage(SettingsKey.gpsSimulationEnabled) private var gpsSimulation = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Toggle("Advance after 12 s on the green", isOn: $autoAdvance)
                Toggle("Show score target", isOn: $showScoreTarget)
                Toggle("Keep screen awake", isOn: $keepAwake)
            } header: {
                Text("Round")
            }

            Section {
                Picker("Map style", selection: $imagery) {
                    Text("Satellite").tag(true)
                    Text("Map").tag(false)
                }
                Toggle("Ideal line", isOn: $idealLine)
                Toggle("Shot dispersion", isOn: $dispersion)
            } header: {
                Text("Map")
            }

            Section {
                Picker("Start a golf workout", selection: $healthMode) {
                    Text("Always").tag(HealthWorkoutMode.always.rawValue)
                    Text("Ask each round").tag(HealthWorkoutMode.ask.rawValue)
                    Text("Never").tag(HealthWorkoutMode.never.rawValue)
                }
            } header: {
                Text("Apple Health")
            }

            Section {
                Toggle("Location simulation", isOn: $gpsSimulation)
            } header: {
                Text("Developer")
            } footer: {
                Text("Adds Simulate Location to the round menu, so you can tap the map to stand anywhere on the course.")
            }

            Section {
                LabeledContent("Version", value: Self.version)
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

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
