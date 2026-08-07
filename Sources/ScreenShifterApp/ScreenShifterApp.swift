import AppKit
import DisplayCore
import SwiftUI

@main
struct ScreenShifterApp: App {
    @StateObject private var model = ScreenShifterModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Screen Shifter", systemImage: "display.2") {
            MenuBarContent(model: model)
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
private final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(model: ScreenShifterModel) {
        if let window {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Screen Shifter Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 420, height: 600))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: ScreenShifterModel

    var body: some View {
        Button {
            SettingsWindowController.shared.show(model: model)
        } label: {
            Label("Settings...", systemImage: "gearshape")
        }
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
    @State private var selectedExternalDisplayID: UInt32?

    var body: some View {
        let builtInDisplay = model.displays.first { $0.isBuiltIn }
        let externalDisplays = model.displays.filter { !$0.isBuiltIn }
        let selectedExternalDisplay = externalDisplays.first {
            $0.displayID == selectedExternalDisplayID
        } ?? externalDisplays.first

        Form {
            Section("Displays") {
                Picker("Built-in display", selection: .constant(builtInDisplay?.displayID)) {
                    if let builtInDisplay {
                        Text(builtInDisplay.name)
                            .tag(Optional(builtInDisplay.displayID))
                    } else {
                        Text("Not detected")
                            .tag(Optional<UInt32>.none)
                    }
                }
                .disabled(builtInDisplay == nil)

                Picker("External display", selection: $selectedExternalDisplayID) {
                    Text("Not detected")
                        .tag(Optional<UInt32>.none)
                    ForEach(externalDisplays, id: \.displayID) { display in
                        Text(display.name)
                            .tag(Optional(display.displayID))
                    }
                }
                .disabled(externalDisplays.isEmpty)
                .onAppear {
                    if selectedExternalDisplayID == nil {
                        selectedExternalDisplayID = externalDisplays.first?.displayID
                    }
                }
                .onChange(of: externalDisplays.map(\.displayID)) { _, displayIDs in
                    if let selectedExternalDisplayID, displayIDs.contains(selectedExternalDisplayID) {
                        return
                    }

                    self.selectedExternalDisplayID = displayIDs.first
                }
            }

            if let builtInDisplay {
                DisplayCaptureSection(display: builtInDisplay, model: model)
            }

            if let selectedExternalDisplay {
                DisplayCaptureSection(display: selectedExternalDisplay, model: model)
            }

            if let errorMessage = model.errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            DisclosureGroup("Log") {
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

            if let captureMessage = model.captureMessage {
                Section {
                    Text(captureMessage)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Power") {
                Toggle(
                    "Keep Mac Awake with External Display",
                    isOn: $model.keepExternalDisplayAwake
                )
                Text("Prevents automatic system sleep only while an external display is connected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Check for updates") {
                    model.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
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

private struct DisplayCaptureSection: View {
    let display: ConnectedDisplay
    @ObservedObject var model: ScreenShifterModel

    private var hasSavedProfile: Bool {
        model.savedProfiles.contains { $0.displayIdentity == display.identity }
    }

    var body: some View {
        Section(display.name) {
            Button("Start capture settings") {
                model.startCapture(for: display)
            }

            Button("Display scaling") {
                model.openDisplaySettings()
            }
            Button("HiDPI mode") {
                model.openDisplaySettings()
            }
            Button("Font size") {
                model.openAppearanceSettings()
            }
            Button("Dock size") {
                model.openDockSettings()
            }

            Button("Complete capture") {
                Task {
                    await model.completeCapture(for: display)
                }
            }
            .disabled(!model.captureState(for: display).canComplete)

            Button("Reset default", role: .destructive) {
                model.prepareReset(for: display)
            }
            .disabled(!hasSavedProfile)
        }
    }
}
