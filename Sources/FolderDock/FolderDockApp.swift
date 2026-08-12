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
        appDelegate.store = store
        appDelegate.dockController = dockController
        appDelegate.updateController = updateController
    }

    var body: some Scene {
        Settings {
            SettingsView(controller: dockController, updateController: updateController)
        }
    }
}

@MainActor
private final class FolderDockAppDelegate: NSObject, NSApplicationDelegate {
    var store: FolderStore?
    var dockController: DockController?
    var updateController: UpdateController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        dockController?.start()
        updateController?.start()
    }

    func applicationDidResignActive(_ notification: Notification) {
        dockController?.handleApplicationDeactivation()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        button.image = NSImage(
            systemSymbolName: "folder.badge.gearshape",
            accessibilityDescription: "Folder Dock"
        )
        button.imagePosition = .imageOnly
        button.toolTip = "Click to show or hide Folder Dock. Right-click for options."
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu(relativeTo: sender)
        } else {
            dockController?.toggleFromMenuBar()
        }
    }

    private func showStatusMenu(relativeTo button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let folders = store?.folders, !folders.isEmpty {
            for folder in folders {
                let item = NSMenuItem(title: folder.name, action: #selector(openSavedItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = folder.url as NSURL
                item.image = NSImage(systemSymbolName: folder.isDirectory ? "folder" : "doc", accessibilityDescription: nil)
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let toggleTitle = dockController?.isVisible == true ? "Hide Folder Dock" : "Show Folder Dock"
        menu.addItem(makeMenuItem(toggleTitle, symbol: "rectangle.topthird.inset.filled", action: #selector(toggleDock)))
        menu.addItem(makeMenuItem("Add Files or Folders…", symbol: "plus", action: #selector(addItems)))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem("Settings…", symbol: "gearshape", action: #selector(openSettings)))
        menu.addItem(makeMenuItem("Check for Updates…", symbol: "arrow.triangle.2.circlepath", action: #selector(checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem("Quit Folder Dock", symbol: "power", action: #selector(quit)))

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
    }

    private func makeMenuItem(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    @objc private func openSavedItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? NSURL else { return }
        dockController?.browse(SavedFolder(url: url as URL))
    }

    @objc private func toggleDock() {
        dockController?.toggleFromMenuBar()
    }

    @objc private func addItems() {
        dockController?.chooseFolders()
    }

    @objc private func openSettings() {
        NSApp.activate()
        let modernSelector = Selector(("showSettingsWindow:"))
        if !NSApp.sendAction(modernSelector, to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        DispatchQueue.main.async {
            NSApp.activate()
            NSApp.windows.first(where: { $0.title == "Folder Dock Settings" })?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func checkForUpdates() {
        updateController?.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
