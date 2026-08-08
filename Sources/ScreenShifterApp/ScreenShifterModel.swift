@preconcurrency import AppKit
import Combine
import CoreFoundation
import DisplayCore
import IOKit.pwr_mgt
import ScreenShifterDomain
import ServiceManagement
import Sparkle

@MainActor
protocol UpdateChecking {
    func checkForUpdates() -> Bool
}

enum GitHubUpdateConfiguration {
    static let feedURL = URL(string: "https://github.com/Eugenius-S/screen-shifter/releases/latest/download/appcast.xml")!
}

enum SystemSettingsDestination {
    case displayResolution
    case accessibilityDisplay
    case dock

    var url: URL? {
        switch self {
        case .displayResolution:
            return URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")
        case .accessibilityDisplay:
            return URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?Seeing_Display")
        case .dock:
            return URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")
        }
    }
}

@MainActor
final class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var appcastURLString: String {
        GitHubUpdateConfiguration.feedURL.absoluteString
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        appcastURLString
    }
}

@MainActor
final class SparkleUpdateChecker: UpdateChecking {
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    func checkForUpdates() -> Bool {
        guard updater.canCheckForUpdates else {
            return false
        }

        updater.checkForUpdates()
        return true
    }
}

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
    @Published private(set) var errorMessage: ModelError?
    @Published private(set) var captureMessage: String?
    @Published private(set) var logText = ""
    @Published var isResetConfirmationPresented = false
    @Published private(set) var resetCandidate: ConnectedDisplay?
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var isReady: Bool = false
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

    private let inventory: DisplayInventorying
    private let modeApplier: DisplayModeApplying
    private let profileStore: DisplayProfileStoring
    private let logStore: LocalLogStore
    private var notificationTokens: [NSObjectProtocol] = []
    // Internal so tests can await the scheduled automation task via
    // `@testable import ScreenShifterApp`. Do not mutate from production
    // code outside the scheduler.
    var scheduledAutomation: Task<Void, Never>?
    private var cooldownUntil: Date?
    private var wakeProtectionUntil: Date?
    private var lastObservedTopology: DisplayTopology?
    private var hasPendingTopologyChange: Bool = false
    private let automationDelayNanoseconds: UInt64
    private let sleepAssertion = SystemSleepAssertionController()
    private let updateChecker: UpdateChecking
    let mainDisplayIDProvider: MainDisplayIDProviding

    init(
        inventory: DisplayInventorying,
        modeApplier: DisplayModeApplying,
        mainDisplayIDProvider: MainDisplayIDProviding,
        profileStore: DisplayProfileStoring = UserDefaultsProfileStore(),
        logStore: LocalLogStore = LocalLogStore(),
        updateChecker: UpdateChecking,
        automationDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.inventory = inventory
        self.modeApplier = modeApplier
        self.mainDisplayIDProvider = mainDisplayIDProvider
        self.profileStore = profileStore
        self.logStore = logStore
        self.updateChecker = updateChecker
        self.automationDelayNanoseconds = automationDelayNanoseconds
        automationPaused = UserDefaults.standard.bool(forKey: "automationPaused")
        keepExternalDisplayAwake = UserDefaults.standard.bool(forKey: "keepExternalDisplayAwake")
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        registerAutomationObservers()
        // P1-5: hold the sleep assertion immediately when keep-awake is on
        // so the system cannot sleep between launch and the first refresh.
        // The first refresh re-evaluates against the real inventory and
        // releases the assertion if no external display is connected.
        if keepExternalDisplayAwake {
            _ = sleepAssertion.update(isEnabled: true)
        }
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    /// Hydrates the profile cache, inventory, and log before observers can
    /// trigger an automatic apply with an empty cache.
    ///
    /// Observers are registered in `init` but the persisted profile store is
    /// loaded asynchronously. A display notification received before
    /// `bootstrap()` completes sets `hasPendingTopologyChange`; after
    /// hydration this method replays that notification once. Idempotent: a
    /// second call is a no-op.
    func bootstrap() async {
        guard !isReady else {
            return
        }

        await refresh()
        isReady = true

        if hasPendingTopologyChange {
            hasPendingTopologyChange = false
            // The notification arrived before we knew the initial inventory.
            // Reset the topology baseline so the replay sees the transition
            // from "no observation" to the new state, which is what
            // `AutomaticDisplayChangePolicy.shouldApply` needs to schedule
            // the apply.
            lastObservedTopology = nil
            handleDisplayChangeNotification()
        }
    }

    func refresh() async {
        do {
            displays = try inventory.connectedDisplays()
            lastObservedTopology = DisplayTopology(displays: displays)
            updateSleepAssertion()
            errorMessage = nil
        } catch {
            errorMessage = .inventoryReadFailed
        }

        savedProfiles = await profileStore.profiles()
        await refreshLogs()
    }

    func prepareCapture() {
        // Per-display capture only; the bulk "save all" flow was removed in
        // slice 4 (P1-2 dead code). The Settings UI now drives the per-display
        // capture state machine via DisplayCaptureSection.
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
                captureStates[display.identity] = DisplayCaptureStateMachine.cancel(
                    from: captureState(for: display)
                )
                errorMessage = .displayNoLongerAvailable(display: display.name)
                return
            }

            await profileStore.save(profile)
            savedProfiles = await profileStore.profiles()
            captureStates[display.identity] = DisplayCaptureStateMachine.complete(
                from: .capturing,
                profile: profile
            )
            errorMessage = nil
            captureMessage = "Captured settings for \(display.name)."
            await record(level: .info, message: captureMessage ?? "Captured display settings.")
        } catch {
            let error: ModelError = .captureFailed(display: display.name)
            errorMessage = error
            await record(level: .error, message: error.message)
        }
    }

    func confirmCapture() async {
        // Bulk capture flow removed in slice 4 (P1-2 dead code). Per-display
        // capture is now the only path, driven by DisplayCaptureSection.
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

        // Plan 001 step 2: a successful read that lacks the display means
        // a disconnect (remove the profile, show the disconnect-aware
        // message). A read failure is *neither* evidence of a disconnect
        // nor permission to drop the profile: preserve it, surface the
        // error, and clear the pending reset state so the dialog does not
        // stay open on top of stale UI.
        let currentDisplays: [ConnectedDisplay]
        do {
            currentDisplays = try inventory.connectedDisplays()
        } catch {
            let error: ModelError = .inventoryReadFailed
            errorMessage = error
            await record(level: .error, message: error.message)
            resetCandidate = nil
            isResetConfirmationPresented = false
            return
        }

        let stillConnected = currentDisplays.contains { $0.identity == display.identity }

        if stillConnected {
            do {
                try modeApplier.reset(display)
            } catch {
                let error: ModelError = .resetFailed(display: display.name)
                errorMessage = error
                await record(level: .error, message: error.message)
                return
            }
        }

        await profileStore.remove(for: display.identity)
        savedProfiles = await profileStore.profiles()
        captureStates[display.identity] = DisplayCaptureStateMachine.cancel(
            from: captureState(for: display)
        )
        resetCandidate = nil
        isResetConfirmationPresented = false
        errorMessage = nil
        captureMessage = stillConnected
            ? "Reset \(display.name) to the system default."
            : "\(display.name) disconnected. Removed the saved profile; the system default is unchanged."
        await record(level: .info, message: captureMessage ?? "Reset display to the system default.")
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
            let error: ModelError = .inventoryReadFailed
            errorMessage = error
            await record(level: .error, message: error.message)
            return
        }

        let profilesByIdentity = Dictionary(
            uniqueKeysWithValues: savedProfiles.map {
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
                switch try modeApplier.apply(profile, to: display) {
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
            let error: ModelError = .applyFailed(displays: errors)
            errorMessage = error
            await record(level: .error, message: error.message)
        }
    }

    func clearLogs() async {
        do {
            try await logStore.clear()
            logText = ""
            errorMessage = nil
        } catch {
            errorMessage = .logWriteFailed
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
        openSystemSettings(.displayResolution)
    }

    func openAccessibilityDisplaySettings() {
        openSystemSettings(.accessibilityDisplay)
    }

    func openDockSettings() {
        openSystemSettings(.dock)
    }

    func checkForUpdates() {
        guard updateChecker.checkForUpdates() else {
            errorMessage = .updateCheckFailed
            return
        }

        errorMessage = nil
        captureMessage = "Started update check."
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            launchAtLoginEnabled = enabled
            errorMessage = nil
        } catch {
            errorMessage = .launchAtLoginFailed(
                reason: enabled
                    ? "Could not enable Launch at Login."
                    : "Could not disable Launch at Login."
            )
        }
    }

    private func refreshLogs() async {
        do {
            logText = try await logStore.text()
        } catch {
            errorMessage = .logWriteFailed
        }
    }

    private func record(level: LogLevel, message: String) async {
        do {
            try await logStore.append(level: level, message: message)
            await refreshLogs()
        } catch {
            errorMessage = .logWriteFailed
        }
    }

    private func openSystemSettings(_ destination: SystemSettingsDestination) {
        guard let url = destination.url else {
            errorMessage = .systemSettingsUnavailable
            return
        }

        guard NSWorkspace.shared.open(url) else {
            errorMessage = .systemSettingsUnavailable
            return
        }

        errorMessage = nil
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

    func handleDisplayChangeNotification() {
        // Plan 001 step 1: defer automatic work until bootstrap has loaded
        // persisted profiles. A display notification that arrives between
        // `init` and `bootstrap()` completion would otherwise build a lookup
        // from an empty `savedProfiles` cache and silently skip every saved
        // profile.
        guard isReady else {
            hasPendingTopologyChange = true
            return
        }

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
            errorMessage = .sleepAssertionFailed
            return
        }

        if errorMessage == .sleepAssertionFailed {
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
            // Plan 001 step 1: the production scheduler waits two seconds so a
            // burst of plug/unplug events only fires one apply. Tests pass
            // `automationDelayNanoseconds: 0` to avoid real-time waits.
            let delay = self?.automationDelayNanoseconds ?? 0
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else {
                return
            }
            await self?.applySavedSetup(isAutomatic: true)
        }
    }
}
