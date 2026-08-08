import AppKit
import DisplayCore
import Sparkle
import SwiftUI

@main
struct ScreenShifterApp: App {
    private let updaterController: SPUStandardUpdaterController
    private let updaterDelegate: SparkleUpdaterDelegate
    @StateObject private var model: ScreenShifterModel

    init() {
        let updaterDelegate = SparkleUpdaterDelegate()
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: nil
        )
        self.updaterController = updaterController
        self.updaterDelegate = updaterDelegate
        // Plan 001 step 1: construct the model first so we can hand the same
        // instance to a bootstrap task. Without this, `init` would only
        // register observers and the persisted profile cache would stay
        // empty until the user opened the menu and triggered Quit's
        // `.task { await model.refresh() }` modifier.
        let model = ScreenShifterModel(
            inventory: SystemDisplayInventory(),
            modeApplier: SystemDisplayModeApplier(),
            mainDisplayIDProvider: SystemMainDisplayIDProvider(),
            updateChecker: SparkleUpdateChecker(updater: updaterController.updater)
        )
        _model = StateObject(wrappedValue: model)
        Task { @MainActor in
            await model.bootstrap()
        }
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

private struct MenuBarContent: View {
    @ObservedObject var model: ScreenShifterModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            openSettings()
        } label: {
            Label("Settings...", systemImage: "gearshape")
        }
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: ScreenShifterModel
    @State private var selectedExternalDisplayID: UInt32?
    @State private var expandedDisplayID: UInt32?

    var body: some View {
        let builtInDisplay = model.displays.first { $0.isBuiltIn }
        let externalDisplays = model.displays.filter { !$0.isBuiltIn }
        let activeDisplayID = model.mainDisplayIDProvider.mainDisplayID
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
                DisplayCaptureSection(
                    display: builtInDisplay,
                    isActive: builtInDisplay.displayID == activeDisplayID,
                    isExpanded: expansionBinding(for: builtInDisplay.displayID),
                    model: model
                )
            }

            if let selectedExternalDisplay {
                DisplayCaptureSection(
                    display: selectedExternalDisplay,
                    isActive: selectedExternalDisplay.displayID == activeDisplayID,
                    isExpanded: expansionBinding(for: selectedExternalDisplay.displayID),
                    model: model
                )
            } else {
                DisclosureGroup("External display") {
                    Text("Not detected")
                        .foregroundStyle(.secondary)
                }
                .disabled(true)
            }

            if let errorMessage = model.errorMessage {
                Section("Error") {
                    Text(errorMessage.message)
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

            Section("Automation") {
                Toggle(
                    "Pause Automation",
                    isOn: $model.automationPaused
                )
                Text("Prevents automatic display restoration until resumed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
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

            Section("Updates") {
                Button("Check for updates") {
                    model.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .onAppear {
            synchronizeExpandedDisplay()
        }
        .onChange(of: model.displays.map(\.displayID)) { _, _ in
            synchronizeExpandedDisplay()
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

    private func expansionBinding(for displayID: UInt32) -> Binding<Bool> {
        Binding(
            get: { expandedDisplayID == displayID },
            set: { isExpanded in
                expandedDisplayID = isExpanded ? displayID : nil
            }
        )
    }

    private func synchronizeExpandedDisplay() {
        let availableDisplays = model.displays
        guard !availableDisplays.isEmpty else {
            expandedDisplayID = nil
            return
        }

        let activeDisplayID = model.mainDisplayIDProvider.mainDisplayID
        if availableDisplays.contains(where: { $0.displayID == activeDisplayID }) {
            expandedDisplayID = activeDisplayID
        } else {
            expandedDisplayID = availableDisplays.first?.displayID
        }
    }
}

enum DisplayCapturePresentation {
    static func statusSymbol(
        for state: DisplayCaptureState,
        hasSavedProfile: Bool
    ) -> String {
        switch state {
        case .idle:
            return hasSavedProfile ? "checkmark.circle" : "circle.dashed"
        case .capturing:
            return "record.circle"
        case .completed:
            return "checkmark.circle.fill"
        }
    }
}

private struct DisplayCaptureSection: View {
    let display: ConnectedDisplay
    let isActive: Bool
    @Binding var isExpanded: Bool
    @ObservedObject var model: ScreenShifterModel

    private var hasSavedProfile: Bool {
        model.savedProfiles.contains { $0.displayIdentity == display.identity }
    }

    private var captureStatus: String {
        switch captureState {
        case .idle:
            return hasSavedProfile ? "Saved profile available." : "No saved profile."
        case .capturing:
            return "Capture in progress. Adjust settings, then complete capture."
        case let .completed(profile):
            return "Captured \(profile.logicalWidth) × \(profile.logicalHeight)\(profile.isHiDPI ? " HiDPI" : "")."
        }
    }

    private var captureState: DisplayCaptureState {
        model.captureState(for: display)
    }

    private var isCapturing: Bool {
        captureState.canComplete
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Label(
                captureStatus,
                systemImage: DisplayCapturePresentation.statusSymbol(
                    for: captureState,
                    hasSavedProfile: hasSavedProfile
                )
            )
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !isCapturing {
                Button("Start capture settings") {
                    model.startCapture(for: display)
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Adjust in System Settings")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Text("Screen Shifter records display resolution and HiDPI state.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Group {
                Button("Display resolution and HiDPI") {
                    model.openDisplaySettings()
                }
                Button("Text size and pointer size") {
                    model.openAccessibilityDisplaySettings()
                }
                Button("Dock size") {
                    model.openDockSettings()
                }
            }
            .disabled(!isCapturing)

            if isCapturing {
                Text("When finished, return to Screen Shifter and select Complete capture.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Complete capture") {
                    Task {
                        await model.completeCapture(for: display)
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Reset default", role: .destructive) {
                model.prepareReset(for: display)
            }
            .disabled(!hasSavedProfile)
        } label: {
            HStack {
                Text(display.name)

                if isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
