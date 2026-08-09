import Sparkle
import SwiftUI

@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var availableVersion: String?
    @Published private(set) var isChecking = false

    private var hasStarted = false
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    var isUpdateAvailable: Bool {
        availableVersion != nil
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        updaterController.startUpdater()

        // A probe updates our button state without presenting Sparkle's update UI.
        DispatchQueue.main.async { [weak self] in
            self?.probeForUpdate()
        }
    }

    func probeForUpdate() {
        guard hasStarted,
              !updaterController.updater.sessionInProgress else { return }
        isChecking = true
        updaterController.updater.checkForUpdateInformation()
    }

    func checkForUpdates() {
        guard hasStarted else { return }
        updaterController.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = "\(item.displayVersionString) (B\(item.versionString))"
        isChecking = false
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        availableVersion = nil
        isChecking = false
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        isChecking = false
    }
}
