import AppKit
import SwiftUI

@main
struct ScreenShifterApp: App {
    @StateObject private var model = ScreenShifterModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Screen Shifter", systemImage: "display.2") {
            MenuBarContent(model: model, automationPaused: $model.automationPaused)
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: ScreenShifterModel
    @Binding var automationPaused: Bool

    var body: some View {
        Button("Apply Saved Setup") {
            Task {
                await model.applySavedSetup()
            }
        }
        Button("Capture Current Setup") {
            model.prepareCapture()
        }

        Divider()

        Toggle("Pause Automation", isOn: $automationPaused)

        Divider()

        SettingsLink()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .task {
            await model.refresh()
        }
        .alert("Save Current Display Profiles", isPresented: $model.isCaptureConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                Task {
                    await model.confirmCapture()
                }
            }
        } message: {
            Text("This will replace saved profiles for \(model.captureCandidates.count) connected display\(model.captureCandidates.count == 1 ? "" : "s").")
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: ScreenShifterModel
    @AppStorage("launchAtLoginEnabled") private var launchAtLoginEnabled = false

    var body: some View {
        Form {
            Section("Connected Displays") {
                if model.displays.isEmpty {
                    Text("No displays detected.")
                } else {
                    ForEach(model.displays, id: \.displayID) { display in
                        Text(display.name)
                    }
                }

                Button("Refresh Displays") {
                    Task {
                        await model.refresh()
                    }
                }
            }

            Section("Saved Profiles") {
                if model.savedProfiles.isEmpty {
                    Text("No saved display profiles.")
                } else {
                    ForEach(model.savedProfiles, id: \.displayIdentity) { profile in
                        Text("\(profile.logicalWidth) x \(profile.logicalHeight)\(profile.isHiDPI ? " HiDPI" : "")")
                    }
                }

                if let captureMessage = model.captureMessage {
                    Text(captureMessage)
                }
            }

            if let errorMessage = model.errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
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