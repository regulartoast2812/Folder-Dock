import AppKit
import QuickLookUI
import SwiftUI

@MainActor
final class DockController: ObservableObject {
    private let store: FolderStore
    private var panel: NSPanel?
    private var hoverTimer: Timer?
    private var dismissalWorkItem: DispatchWorkItem?
    private var shortcutEventMonitor: Any?
    private var globalMouseShortcutMonitor: Any?
    private let quickLookController = QuickLookPreviewController()
    private var hasStarted = false
    private var isInteractionLocked = false
    private var navigationHistory: [URL] = []
    private var historyIndex = -1
    @Published private(set) var currentFolder: URL?
    @Published private(set) var isManagingSets = false
    @Published private(set) var selectedItemURL: URL?
    @Published private(set) var directoryRevision = UUID()

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex >= 0 && historyIndex < navigationHistory.count - 1 }

    init(store: FolderStore) {
        self.store = store
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        NSApp.setActivationPolicy(.accessory)

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPointerPosition()
            }
        }
        if let hoverTimer {
            RunLoop.main.add(hoverTimer, forMode: .common)
        }

        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleShortcutEvent(event)
        }
        globalMouseShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleGlobalMouseShortcut(event)
            }
        }
    }

    func show() {
        cancelDismissal()
        let panel = makePanelIfNeeded()
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        cancelDismissal()
        isInteractionLocked = false
        panel?.orderOut(nil)
    }

    func keepOpen() {
        isInteractionLocked = true
        cancelDismissal()
    }

    func chooseFolders() {
        keepOpen()
        let picker = NSOpenPanel()
        picker.title = "Save folders to Folder Dock"
        picker.prompt = "Save Folders"
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = true
        picker.canCreateDirectories = false

        NSApp.activate(ignoringOtherApps: true)
        if picker.runModal() == .OK {
            picker.urls.forEach(store.add(url:))
        }
        show()
    }

    func selectSet(_ set: FolderSet) {
        store.selectSet(set)
        keepOpen()
        closeBrowser()
    }

    func switchSet(forward: Bool) {
        let sets = store.folderSets
        guard sets.count > 1,
              let currentIndex = sets.firstIndex(where: { $0.id == store.selectedSetID }) else { return }
        let nextIndex = forward
            ? (currentIndex + 1) % sets.count
            : (currentIndex - 1 + sets.count) % sets.count
        selectSet(sets[nextIndex])
    }

    func browse(_ folder: SavedFolder) {
        isManagingSets = false
        navigationHistory = [folder.url]
        historyIndex = 0
        currentFolder = folder.url
        selectedItemURL = nil
        resizePanel(for: .browser)
        show()
        activateForInput()
    }

    func openInBrowser(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            navigate(to: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func selectItem(_ url: URL) {
        selectedItemURL = url
    }

    func openSelectedItem() {
        guard let selectedItemURL else { return }
        openInBrowser(selectedItemURL)
    }

    func showQuickLook() {
        guard let selectedItemURL else { return }
        activateForInput()
        quickLookController.show(url: selectedItemURL)
    }

    func openInNewFinderWindow(_ folder: SavedFolder) {
        let escapedPath = folder.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = NSAppleScript(source: """
        tell application \"Finder\"
            activate
            make new Finder window to (POSIX file \"\(escapedPath)\" as alias)
        end tell
        """)

        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if error != nil {
            NSWorkspace.shared.open(folder.url)
        }
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        currentFolder = navigationHistory[historyIndex]
        selectedItemURL = nil
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        currentFolder = navigationHistory[historyIndex]
        selectedItemURL = nil
    }

    func goToParentFolder() {
        guard let currentFolder else { return }
        let parent = currentFolder.deletingLastPathComponent()
        guard parent.path != currentFolder.path else { return }
        navigate(to: parent)
    }

    func refreshFolder() {
        directoryRevision = UUID()
    }

    func createNewFolder() {
        guard let currentFolder else { return }
        activateForInput()

        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Create a folder in \(currentFolder.lastPathComponent)."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: "Untitled Folder")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { return }

        let destination = currentFolder.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            selectedItemURL = destination
            refreshFolder()
        } catch {
            let errorAlert = NSAlert(error: error)
            errorAlert.runModal()
        }
    }

    func closeBrowser() {
        navigationHistory.removeAll()
        historyIndex = -1
        currentFolder = nil
        isManagingSets = false
        selectedItemURL = nil
        resizePanel(for: .shelf)
        show()
    }

    func showSetManager() {
        navigationHistory.removeAll()
        historyIndex = -1
        currentFolder = nil
        isManagingSets = true
        resizePanel(for: .browser)
        show()
        // The shelf itself stays non-activating, but set management needs keyboard focus.
        activateForInput()
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }

        let panel = DockPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 72),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: DockView(store: store, controller: self))
        self.panel = panel
        return panel
    }

    private enum PanelMode {
        case shelf, browser

        var size: NSSize {
            switch self {
            case .shelf: NSSize(width: 460, height: 94)
            case .browser: NSSize(width: 720, height: 532)
            }
        }
    }

    private func resizePanel(for mode: PanelMode) {
        let panel = makePanelIfNeeded()
        panel.setContentSize(mode.size)
        position(panel)
    }

    private func checkPointerPosition() {
        let location = NSEvent.mouseLocation
        guard let screen = screen(containing: location) else { return }

        let inHotZone = abs(location.x - screen.frame.midX) < 210
            && screen.frame.maxY - location.y < 24

        if isInteractionLocked {
            cancelDismissal()
        } else if inHotZone {
            show()
        } else if let panel, panel.isVisible, !panel.frame.contains(location) {
            scheduleDismissal()
        } else {
            cancelDismissal()
        }
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = screen(containing: mouseLocation) else { return }
        let frame = panel.frame
        let x = screen.frame.midX - frame.width / 2
        // visibleFrame places the shelf below the menu bar, which keeps the notch area unobstructed.
        let y = screen.visibleFrame.maxY - frame.height + 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func scheduleDismissal() {
        guard dismissalWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
            self?.dismissalWorkItem = nil
        }
        dismissalWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func cancelDismissal() {
        dismissalWorkItem?.cancel()
        dismissalWorkItem = nil
    }

    private func navigate(to url: URL) {
        if historyIndex < navigationHistory.count - 1 {
            navigationHistory.removeSubrange((historyIndex + 1)...)
        }
        navigationHistory.append(url)
        historyIndex = navigationHistory.count - 1
        currentFolder = url
        selectedItemURL = nil
    }

    private func activateForInput() {
        keepOpen()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func handleShortcutEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .otherMouseDown {
            return handleMouseShortcut(event) ? nil : event
        }

        guard panel?.isKeyWindow == true else { return event }
        if event.keyCode == 53 { // Escape
            hide()
            return nil
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = modifiers.contains(.command)
        let shift = modifiers.contains(.shift)
        let option = modifiers.contains(.option)
        let key = event.charactersIgnoringModifiers?.lowercased()

        if command && option && event.keyCode == 123 { switchSet(forward: false); return nil } // Option-Command-Left
        if command && option && event.keyCode == 124 { switchSet(forward: true); return nil }  // Option-Command-Right
        guard currentFolder != nil else { return event }
        if command && key == "[" { goBack(); return nil }
        if command && key == "]" { goForward(); return nil }
        if command && key == "r" { refreshFolder(); return nil }
        if command && key == "w" { closeBrowser(); return nil }
        if command && key == "o" { openSelectedItem(); return nil }
        if command && shift && key == "n" { createNewFolder(); return nil }
        if command && key == "n", let currentFolder {
            NSWorkspace.shared.open(currentFolder)
            return nil
        }
        if command && event.keyCode == 126 { goToParentFolder(); return nil } // Command-Up Arrow
        if event.keyCode == 49 { showQuickLook(); return nil } // Space
        if event.keyCode == 36 || event.keyCode == 76 { openSelectedItem(); return nil } // Return / keypad Enter

        return event
    }

    private func handleGlobalMouseShortcut(_ event: NSEvent) {
        guard let panel,
              panel.isVisible,
              panel.frame.contains(NSEvent.mouseLocation) else { return }
        _ = handleMouseShortcut(event)
    }

    @discardableResult
    private func handleMouseShortcut(_ event: NSEvent) -> Bool {
        guard currentFolder != nil else { return false }
        switch event.buttonNumber {
        case 3:
            goBack()       // Logitech MX Back button
            return true
        case 4:
            goForward()    // Logitech MX Forward button
            return true
        default:
            return false
        }
    }
}

private final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource {
    private var previewURL: URL?

    @MainActor
    func show(url: URL) {
        previewURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.makeKeyAndOrderFront(nil)
        // QLPreviewPanel resets some window attributes while it presents. Apply the
        // level on the next run-loop turn so it remains above Folder Dock's status-bar panel.
        DispatchQueue.main.async {
            panel.level = .screenSaver
            panel.orderFrontRegardless()
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }
}
