import Combine
import DisplayCore
import ScreenShifterDomain

@MainActor
final class ScreenShifterModel: ObservableObject {
    @Published private(set) var displays: [ConnectedDisplay] = []
    @Published private(set) var savedProfiles: [DisplayProfile] = []
    @Published private(set) var captureCandidates: [DisplayProfile] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var captureMessage: String?
    @Published var isCaptureConfirmationPresented = false

    private let inventory = SystemDisplayInventory()
    private let profileStore = UserDefaultsProfileStore()

    func refresh() async {
        do {
            displays = try inventory.connectedDisplays()
            errorMessage = nil
        } catch {
            errorMessage = "Could not read connected displays."
        }

        savedProfiles = await profileStore.profiles()
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

    func confirmCapture() async {
        let profiles = captureCandidates

        for profile in profiles {
            await profileStore.save(profile)
        }

        savedProfiles = await profileStore.profiles()
        captureCandidates = []
        captureMessage = "Saved \(profiles.count) display profile\(profiles.count == 1 ? "" : "s")."
    }

    func applySavedSetup() async {
        do {
            displays = try inventory.connectedDisplays()
        } catch {
            errorMessage = "Could not read connected displays."
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
            captureMessage = "Applied \(appliedCount) profile\(appliedCount == 1 ? "" : "s"); \(unchangedCount) already matched; \(unavailableCount) unavailable."
        } else {
            errorMessage = "Could not apply profiles for: \(errors.joined(separator: ", "))."
        }
    }
}