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
        .alert("Reset Display to Default", isPresented: $model.isResetConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task {
                    await model.confirmReset()
                }
            }
        } message: {
            Text("This removes the saved profile for \(model.resetCandidate?.name ?? "this display") and restores the system default scaling.")
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: ScreenShifterModel

    var body: some View {
        Form {
            Section("Connected Displays") {
                if model.displays.isEmpty {
                    Text("No displays detected.")
                } else {
                    ForEach(model.displays, id: \.displayID) { display in
                        HStack {
                            Text(display.name)
                            Spacer()
                            Button("Reset to Default") {
                                model.prepareReset(for: display)
                            }
                            .disabled(!model.savedProfiles.contains { $0.displayIdentity == display.identity })
                        }
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

            Section("Local Log") {
                TextEditor(text: .constant(model.logText))
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 140)

                HStack {
                    Button("Copy Logs") {
                        model.copyLogs()
                    }
                    Button("Clear Logs") {
                        Task {
                            await model.clearLogs()
                        }
                    }
                    Button("Open Log File") {
                        model.openLogFile()
                    }
                }
            }

            Section {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}