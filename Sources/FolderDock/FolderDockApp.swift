import AppKit
import SwiftUI

@main
struct FolderDockApp: App {
    @NSApplicationDelegateAdaptor(FolderDockAppDelegate.self) private var appDelegate
    @StateObject private var store: FolderStore
    @StateObject private var dockController: DockController

    init() {
        let store = FolderStore()
        let dockController = DockController(store: store)
        _store = StateObject(wrappedValue: store)
        _dockController = StateObject(wrappedValue: dockController)
        appDelegate.dockController = dockController
    }

    var body: some Scene {
        MenuBarExtra("Folder Dock", systemImage: "folder.badge.gearshape") {
            FolderDockMenu(store: store, dockController: dockController)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}

@MainActor
private final class FolderDockAppDelegate: NSObject, NSApplicationDelegate {
    var dockController: DockController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        dockController?.start()
    }

    func applicationDidResignActive(_ notification: Notification) {
        dockController?.hide()
    }
}

private struct FolderDockMenu: View {
    @ObservedObject var store: FolderStore
    @ObservedObject var dockController: DockController

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

        Button("Quit Folder Dock") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
