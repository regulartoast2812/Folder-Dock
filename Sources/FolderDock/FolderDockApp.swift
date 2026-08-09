import AppKit
import SwiftUI

@main
struct FolderDockApp: App {
    @NSApplicationDelegateAdaptor(FolderDockAppDelegate.self) private var appDelegate
    @StateObject private var store: FolderStore
    @StateObject private var dockController: DockController
    @StateObject private var updateController: UpdateController

    init() {
        let store = FolderStore()
        let updateController = UpdateController()
        let dockController = DockController(store: store, updateController: updateController)
        _store = StateObject(wrappedValue: store)
        _dockController = StateObject(wrappedValue: dockController)
        _updateController = StateObject(wrappedValue: updateController)
        appDelegate.dockController = dockController
        appDelegate.updateController = updateController
    }

    var body: some Scene {
        MenuBarExtra("Folder Dock", systemImage: "folder.badge.gearshape") {
            FolderDockMenu(
                store: store,
                dockController: dockController,
                updateController: updateController
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store, updateController: updateController)
        }
    }
}

@MainActor
private final class FolderDockAppDelegate: NSObject, NSApplicationDelegate {
    var dockController: DockController?
    var updateController: UpdateController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        dockController?.start()
        updateController?.start()
    }

    func applicationDidResignActive(_ notification: Notification) {
        dockController?.hide()
    }
}

private struct FolderDockMenu: View {
    @ObservedObject var store: FolderStore
    @ObservedObject var dockController: DockController
    @ObservedObject var updateController: UpdateController

    var body: some View {
        if store.folders.isEmpty {
            Text("No saved folders yet")
        } else {
            ForEach(store.folders) { folder in
                Button(folder.name) {
                    dockController.browse(folder)
                }
            }
            Divider()
        }

        Button("Add Folder…") {
            dockController.chooseFolders()
        }

        Button("Show Folder Dock") {
            dockController.show()
        }
        .keyboardShortcut("d")

        Divider()

        SettingsLink {
            Text("Settings…")
        }

        Button("Check for Updates…") {
            updateController.checkForUpdates()
        }

        Button("Quit Folder Dock") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
