@preconcurrency import AppKit
import Combine
import CoreFoundation
import DisplayCore
import IOKit.pwr_mgt
import ScreenShifterDomain
import ServiceManagement

private final class SystemSleepAssertionController {
    private var assertionID: IOPMAssertionID = 0

    @discardableResult
    func update(isEnabled: Bool) -> Bool {
        if !isEnabled {
            releaseAssertion()
            return true
        }

        guard assertionID == 0 else {
            return true
        }

        var newAssertionID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            makeCFString(kIOPMAssertionTypeNoIdleSleep),
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            makeCFString("Screen Shifter: external display"),
            &newAssertionID
        )
        guard result == kIOReturnSuccess else {
            return false
        }

        assertionID = newAssertionID
        return true
    }

    deinit {
        releaseAssertion()
    }

    private func releaseAssertion() {
        guard assertionID != 0 else {
            return
        }

        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    private func makeCFString(_ value: String) -> CFString {
        let string = value as NSString
        return CFStringCreateWithCString(
            nil,
            string.utf8String!,
            CFStringBuiltInEncodings.UTF8.rawValue
        )!
    }
}

@MainActor
final class ScreenShifterModel: ObservableObject {
    @Published private(set) var displays: [ConnectedDisplay] = []
    @Published private(set) var savedProfiles: [DisplayProfile] = []
    @Published private(set) var captureStates: [DisplayIdentity: DisplayCaptureState] = [:]
    @Published private(set) var captureCandidates: [DisplayProfile] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var captureMessage: String?
    @Published private(set) var logText = ""
    @Published var isCaptureConfirmationPresented = false
    @Published var isResetConfirmationPresented = false
    @Published private(set) var resetCandidate: ConnectedDisplay?
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published var keepExternalDisplayAwake: Bool {
        didSet {
            UserDefaults.standard.set(keepExternalDisplayAwake, forKey: "keepExternalDisplayAwake")
            updateSleepAssertion()
        }
    }
    @Published var automationPaused: Bool {
        didSet {
            UserDefaults.standard.set(automationPaused, forKey: "automationPaused")
        }
    }

    private let inventory = SystemDisplayInventory()
    private let profileStore = UserDefaultsProfileStore()
    private let logStore = LocalLogStore()
    private var notificationTokens: [NSObjectProtocol] = []
    private var scheduledAutomation: Task<Void, Never>?
    private var cooldownUntil: Date?
    private var wakeProtectionUntil: Date?
    private var lastObservedTopology: DisplayTopology?
    private let sleepAssertion = SystemSleepAssertionController()

    init() {
        automationPaused = UserDefaults.standard.bool(forKey: "automationPaused")
        keepExternalDisplayAwake = UserDefaults.standard.bool(forKey: "keepExternalDisplayAwake")
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        registerAutomationObservers()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func refresh() async {
        do {
            displays = try inventory.connectedDisplays()
            lastObservedTopology = DisplayTopology(displays: displays)
            updateSleepAssertion()
            errorMessage = nil
        } catch {
            errorMessage = "Could not read connected displays."
        }

        savedProfiles = await profileStore.profiles()
        await refreshLogs()
    }

    func prepareCapture() {
        captureCandidates = ProfileCapturePlanner.profiles(for: displays)

        guard !captureCandidates.isEmpty else {
            errorMessage = "No display modes are available to capture."
            return
        }

        captureMessage = nil
        isCaptureConfirmationPresented = true
    }

    func captureState(for display: ConnectedDisplay) -> DisplayCaptureState {
        captureStates[display.identity] ?? .idle
    }

    func startCapture(for display: ConnectedDisplay) {
        captureStates[display.identity] = DisplayCaptureStateMachine.start(
            from: captureState(for: display)
        )
        captureMessage = "Capture started for \(display.name)."
    }

    func completeCapture(for display: ConnectedDisplay) async {
        guard captureState(for: display).canComplete else {
            return
        }

        do {
            let currentDisplays = try inventory.connectedDisplays()
            guard let currentDisplay = currentDisplays.first(where: { $0.identity == display.identity }),
                  let profile = ProfileCapturePlanner.profiles(for: [currentDisplay]).first
            else {
                captureStates[display.identity] = .idle
                errorMessage = "Could not capture \(display.name); the display is no longer available."
                return
            }

            await profileStore.save(profile)
            savedProfiles = await profileStore.profiles()
            captureStates[display.identity] = DisplayCaptureStateMachine.complete(
                from: .capturing,
                profile: profile
            )
            captureMessage = "Captured settings for \(display.name)."
            await record(level: .info, message: captureMessage ?? "Captured display settings.")
        } catch {
            errorMessage = "Could not capture settings for \(display.name)."
            await record(level: .error, message: errorMessage ?? "Could not capture display settings.")
        }
    }

    func confirmCapture() async {
        let profiles = captureCandidates

        for profile in profiles {
            await profileStore.save(profile)
        }

        savedProfiles = await profileStore.profiles()
        captureCandidates = []
        captureMessage = "Saved \(profiles.count) display profile\(profiles.count == 1 ? "" : "s")."
        await record(level: .info, message: captureMessage ?? "Saved display profiles.")
    }

    func prepareReset(for display: ConnectedDisplay) {
        guard savedProfiles.contains(where: { $0.displayIdentity == display.identity }) else {
            return
        }

        resetCandidate = display
        isResetConfirmationPresented = true
    }

    func confirmReset() async {
        guard let display = resetCandidate else {
            return
        }

        do {
            try SystemDisplayModeApplier().reset(display)
            await profileStore.remove(for: display.identity)
            savedProfiles = await profileStore.profiles()
            captureStates[display.identity] = .idle
            resetCandidate = nil
            isResetConfirmationPresented = false
            captureMessage = "Reset \(display.name) to the system default."
            await record(level: .info, message: captureMessage ?? "Reset display to the system default.")
        } catch {
            errorMessage = "Could not reset \(display.name) to the system default."
            await record(level: .error, message: errorMessage ?? "Could not reset display.")
        }
    }

    func applySavedSetup(isAutomatic: Bool = false) async {
        if isAutomatic {
            let permission = AutomationPolicy.permission(
                isPaused: automationPaused,
                now: Date(),
                cooldownUntil: cooldownUntil,
                wakeProtectionUntil: wakeProtectionUntil
            )
            guard permission == .allowed else {
                return
            }
            cooldownUntil = Date().addingTimeInterval(3)
        }

        do {
            displays = try inventory.connectedDisplays()
            lastObservedTopology = DisplayTopology(displays: displays)
            updateSleepAssertion()
        } catch {
            errorMessage = "Could not read connected displays."
            await record(level: .error, message: errorMessage ?? "Could not read connected displays.")
            return
        }

        let profilesByIdentity = Dictionary(
            uniqueKeysWithValues: (await profileStore.profiles()).map {
                ($0.displayIdentity, $0)
            }
        )
        var appliedCount = 0
        var unchangedCount = 0
        var unavailableCount = 0
        var errors: [String] = []

        for display in displays {
            guard let profile = profilesByIdentity[display.identity] else {
                continue
            }

            do {
                switch try SystemDisplayModeApplier().apply(profile, to: display) {
                case .applied:
                    appliedCount += 1
                case .alreadyApplied:
                    unchangedCount += 1
                case .unavailable:
                    unavailableCount += 1
                }
            } catch {
                errors.append(display.name)
            }
        }

        if errors.isEmpty {
            errorMessage = nil
            if !isAutomatic {
                captureMessage = "Applied \(appliedCount) profile\(appliedCount == 1 ? "" : "s"); \(unchangedCount) already matched; \(unavailableCount) unavailable."
            }
            await record(
                level: .info,
                message: isAutomatic ? "Automatic apply completed." : (captureMessage ?? "Apply completed.")
            )
        } else {
            errorMessage = "Could not apply profiles for: \(errors.joined(separator: ", "))."
            await record(level: .error, message: errorMessage ?? "Could not apply saved profiles.")
        }
    }

    func clearLogs() async {
        do {
            try await logStore.clear()
            logText = ""
        } catch {
            errorMessage = "Could not clear the local log."
        }
    }

    func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
    }

    func openLogFile() {
        NSWorkspace.shared.open(LocalLogStore.defaultFileURL)
    }

    func openDisplaySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.Displays-Settings.extension")
    }

    func openAppearanceSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.Appearance-Settings.extension")
    }

    func openDockSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.dock")
    }

    func checkForUpdates() {
        guard let url = URL(string: "https://github.com/Eugenius-S/screen-shifter/releases/latest"),
              NSWorkspace.shared.open(url)
        else {
            errorMessage = "Could not open the update page."
            return
        }

        captureMessage = "Opened the latest release page."
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            launchAtLoginEnabled = enabled
        } catch {
            errorMessage = enabled
                ? "Could not enable Launch at Login."
                : "Could not disable Launch at Login."
        }
    }

    private func refreshLogs() async {
        do {
            logText = try await logStore.text()
        } catch {
            errorMessage = "Could not read the local log."
        }
    }

    private func record(level: LogLevel, message: String) async {
        do {
            try await logStore.append(level: level, message: message)
            await refreshLogs()
        } catch {
            errorMessage = "Could not write the local log."
        }
    }

    private func openSystemSettings(_ address: String) {
        guard let url = URL(string: address) else {
            errorMessage = "Could not open System Settings."
            return
        }

        guard NSWorkspace.shared.open(url) else {
            errorMessage = "Could not open System Settings."
            return
        }
    }

    private func registerAutomationObservers() {
        let notificationCenter = NotificationCenter.default
        notificationTokens = [
            notificationCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleDisplayChangeNotification()
                }
            },
            notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: NSWorkspace.shared,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.protectAutomationAfterWake()
                }
            }
        ]
    }

    private func protectAutomationAfterWake() {
        wakeProtectionUntil = Date().addingTimeInterval(3)
        scheduledAutomation?.cancel()
        scheduledAutomation = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.scheduleAutomationAfterDisplayChange(force: true)
        }
    }

    private func handleDisplayChangeNotification() {
        guard let currentDisplays = try? inventory.connectedDisplays() else {
            return
        }

        displays = currentDisplays
        updateSleepAssertion()
        let currentTopology = DisplayTopology(displays: currentDisplays)
        let shouldApply = AutomaticDisplayChangePolicy.shouldApply(
            previous: lastObservedTopology,
            current: currentTopology
        )
        lastObservedTopology = currentTopology

        guard shouldApply else {
            scheduledAutomation?.cancel()
            scheduledAutomation = nil
            return
        }

        scheduleAutomationAfterDisplayChange()
    }

    private func updateSleepAssertion() {
        let shouldPreventSleep = ExternalDisplaySleepPolicy.shouldPreventSystemSleep(
            isEnabled: keepExternalDisplayAwake,
            displays: displays
        )
        guard sleepAssertion.update(isEnabled: shouldPreventSleep) else {
            errorMessage = "Could not change the external-display sleep setting."
            return
        }

        if errorMessage == "Could not change the external-display sleep setting." {
            errorMessage = nil
        }
    }

    private func scheduleAutomationAfterDisplayChange(force: Bool = false) {
        if !force {
            let permission = AutomationPolicy.permission(
                isPaused: automationPaused,
                now: Date(),
                cooldownUntil: cooldownUntil,
                wakeProtectionUntil: wakeProtectionUntil
            )
            guard permission == .allowed else {
                return
            }
        }

        scheduledAutomation?.cancel()
        scheduledAutomation = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            await self?.applySavedSetup(isAutomatic: true)
        }
    }
}
