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

    func reportApplyUnavailable() {
        errorMessage = "Applying saved modes requires an external-display capability check."
    }
}