import AppKit
import Sparkle
import SwiftUI

@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var availableVersion: String?
    @Published private(set) var isChecking = false

    private var hasStarted = false
    private let appManagementPromptKey = "hasShownAppManagementPromptV1"
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
        showAppManagementPromptIfNeeded()
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

    func openAppManagementSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppManagement") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func showAppManagementPromptIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: appManagementPromptKey) else { return }
        UserDefaults.standard.set(true, forKey: appManagementPromptKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Enable automatic updates"
            alert.informativeText = "Allow Folder Dock in System Settings → Privacy & Security → App Management so future updates can install automatically."
            alert.addButton(withTitle: "Open App Management")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                self.openAppManagementSettings()
            }
        }
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
