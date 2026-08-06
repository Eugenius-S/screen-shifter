import AppKit
import SwiftUI

@main
struct ScreenShifterApp: App {
    @AppStorage("automationPaused") private var automationPaused = false

    var body: some Scene {
        MenuBarExtra("Screen Shifter", systemImage: "display.2") {
            Button("Apply Saved Setup") {}
            Button("Capture Current Setup") {}

            Divider()

            Toggle("Pause Automation", isOn: $automationPaused)

            Divider()

            SettingsLink()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

private struct SettingsView: View {
    @AppStorage("launchAtLoginEnabled") private var launchAtLoginEnabled = false

    var body: some View {
        Form {
            Section("Profiles") {
                Text("No saved display profiles.")
            }

            Section {
                Toggle("Launch at Login", isOn: $launchAtLoginEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}