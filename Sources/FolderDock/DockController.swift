import AppKit
import Darwin
import QuickLookUI
import SwiftUI

enum DockPrompt: Identifiable {
    case newFolder(parent: URL)
    case rename(URL)
    case info(URL)
    case error(String)

    var id: String {
        switch self {
        case let .newFolder(parent): "new-folder-\(parent.path)"
        case let .rename(url): "rename-\(url.path)"
        case let .info(url): "info-\(url.path)"
        case let .error(message): "error-\(message)"
        }
    }
}

@MainActor
final class DockController: ObservableObject {
    private let store: FolderStore
    let updateController: UpdateController
    private var shelfPanel: DockPanel?
    private var browserPanel: DockPanel?
    private var hoverTimer: Timer?
    private var dismissalWorkItem: DispatchWorkItem?
    private var shortcutEventMonitor: Any?
    private var globalMouseShortcutMonitor: Any?
    private let quickLookController = QuickLookPreviewController()
    private var hasStarted = false
    private var isInteractionLocked = false
    private var shelfResizeBaseWidth: CGFloat?
    private var shelfResizeStartMouseX: CGFloat?
    private var browserResizeBaseSize: NSSize?
    private var browserResizeStartMouse: NSPoint?
    private var navigationHistory: [URL] = []
    private var historyIndex = -1
    @Published private(set) var currentFolder: URL?
    @Published private(set) var isManagingSets = false
    @Published private(set) var selectedItemURLs: Set<URL> = []
    @Published private(set) var selectionAnchorURL: URL?
    private var currentDirectoryItemURLs: [URL] = []
    private var pendingCutURLs: Set<URL> = []
    @Published private(set) var directoryRevision = UUID()
    @Published private(set) var prompt: DockPrompt?
    @Published var promptText = ""

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex >= 0 && historyIndex < navigationHistory.count - 1 }
    var selectedItemURL: URL? { selectionAnchorURL ?? selectedItemURLs.first }
    var selectedItemCount: Int { selectedItemURLs.count }

    init(store: FolderStore, updateController: UpdateController) {
        self.store = store
        self.updateController = updateController
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        NSApp.setActivationPolicy(.accessory)

        // Build the shelf before the first hover so SwiftUI/AppKit initialization never
        // lands on the reveal path. Keep it ordered out until the pointer reaches the edge.
        let shelf = makeShelfPanelIfNeeded()
        positionShelf(shelf)
        shelf.orderOut(nil)

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
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
        let shelf = makeShelfPanelIfNeeded()
        positionShelf(shelf)
        shelf.orderFrontRegardless()
        if currentFolder != nil || isManagingSets {
            let browser = makeBrowserPanelIfNeeded()
            positionBrowser(browser, below: shelf)
            browser.orderFrontRegardless()
        }
    }

    func hide() {
        cancelDismissal()
        isInteractionLocked = false
        shelfPanel?.orderOut(nil)
        browserPanel?.orderOut(nil)
    }

    func handleEscape() {
        if prompt != nil {
            cancelPrompt()
        } else {
            hide()
        }
    }

    func keepOpen() {
        isInteractionLocked = true
        cancelDismissal()
    }

    func beginShelfResize() {
        guard let shelfPanel else { return }
        keepOpen()
        shelfResizeBaseWidth = shelfPanel.frame.width
        shelfResizeStartMouseX = NSEvent.mouseLocation.x
    }

    func updateShelfResize(fromLeadingEdge: Bool) {
        guard let panel = shelfPanel, let startMouseX = shelfResizeStartMouseX else { return }
        let baseWidth = shelfResizeBaseWidth ?? panel.frame.width
        let mouseDelta = NSEvent.mouseLocation.x - startMouseX
        let directionalTranslation = fromLeadingEdge ? -mouseDelta : mouseDelta
        panel.setContentSize(NSSize(width: max(360, baseWidth + directionalTranslation * 2), height: 100))
        positionShelf(panel)
        if let browser = browserPanel, browser.isVisible {
            positionBrowser(browser, below: panel)
        }
    }

    func endShelfResize() {
        guard let panel = shelfPanel else { return }
        shelfResizeBaseWidth = nil
        shelfResizeStartMouseX = nil
        UserDefaults.standard.set(panel.frame.width, forKey: "dockShelfWidth")
        positionShelf(panel)
    }

    func beginBrowserResize() {
        guard let browserPanel else { return }
        keepOpen()
        browserResizeBaseSize = browserPanel.frame.size
        browserResizeStartMouse = NSEvent.mouseLocation
    }

    func updateBrowserResize(fromLeadingEdge: Bool) {
        guard let panel = browserPanel,
              let shelf = shelfPanel,
              let startMouse = browserResizeStartMouse else { return }
        let baseSize = browserResizeBaseSize ?? panel.frame.size
        let mouseDeltaX = NSEvent.mouseLocation.x - startMouse.x
        let directionalTranslation = fromLeadingEdge ? -mouseDeltaX : mouseDeltaX
        let downwardMouseDelta = startMouse.y - NSEvent.mouseLocation.y
        panel.setContentSize(NSSize(
            width: max(520, baseSize.width + directionalTranslation * 2),
            height: max(300, baseSize.height + downwardMouseDelta)
        ))
        positionBrowser(panel, below: shelf)
    }

    func endBrowserResize() {
        guard let panel = browserPanel, let shelf = shelfPanel else { return }
        browserResizeBaseSize = nil
        browserResizeStartMouse = nil
        UserDefaults.standard.set(panel.frame.width, forKey: "dockBrowserWidth")
        UserDefaults.standard.set(panel.frame.height, forKey: "dockBrowserHeight")
        positionBrowser(panel, below: shelf)
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
        clearSelection()
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

    func updateCurrentDirectoryItems(_ urls: [URL]) {
        currentDirectoryItemURLs = urls
        selectedItemURLs = selectedItemURLs.intersection(Set(urls))
        if let selectionAnchorURL, !selectedItemURLs.contains(selectionAnchorURL) {
            self.selectionAnchorURL = selectedItemURLs.first
        }
    }

    /// Mirrors Finder selection: click selects one item, ⌘-click toggles, and ⇧-click selects a range.
    func selectItem(_ url: URL, orderedURLs: [URL]) {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.shift),
           let anchor = selectionAnchorURL,
           let anchorIndex = orderedURLs.firstIndex(of: anchor),
           let itemIndex = orderedURLs.firstIndex(of: url) {
            let range = min(anchorIndex, itemIndex)...max(anchorIndex, itemIndex)
            let rangeSelection = Set(orderedURLs[range])
            if modifiers.contains(.command) {
                selectedItemURLs.formUnion(rangeSelection)
            } else {
                selectedItemURLs = rangeSelection
            }
            return
        }

        if modifiers.contains(.command) {
            if selectedItemURLs.contains(url) {
                selectedItemURLs.remove(url)
            } else {
                selectedItemURLs.insert(url)
                selectionAnchorURL = url
            }
            if selectedItemURLs.isEmpty {
                selectionAnchorURL = nil
            }
        } else {
            selectedItemURLs = [url]
            selectionAnchorURL = url
        }
    }

    func clearSelection() {
        selectedItemURLs = []
        selectionAnchorURL = nil
    }

    func selectAllItems() {
        selectedItemURLs = Set(currentDirectoryItemURLs)
        selectionAnchorURL = currentDirectoryItemURLs.first
    }

    func openSelectedItem() {
        openItems(Array(selectedItemURLs))
    }

    func openItems(_ urls: [URL]) {
        urls.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }).forEach(openInBrowser)
    }

    func showQuickLook() {
        quickLook(Array(selectedItemURLs))
    }

    func quickLook(_ urls: [URL]) {
        let urls = urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        guard !urls.isEmpty else { return }
        activateForInput()
        quickLookController.show(urls: urls)
    }

    func copyToPasteboard(_ url: URL) {
        copyToPasteboard([url])
    }

    func copySelectedItemsToPasteboard() {
        copyToPasteboard(Array(selectedItemURLs))
    }

    func copyToPasteboard(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        pendingCutURLs = []
    }

    func cutSelectedItems() {
        cutItems(Array(selectedItemURLs))
    }

    func cutItems(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        pendingCutURLs = Set(urls.map(\.standardizedFileURL))
    }

    func pasteIntoCurrentFolder(forceMove: Bool = false) {
        guard let currentFolder,
              let objects = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] else { return }
        let urls = objects.map { $0 as URL }
        guard !urls.isEmpty else { return }
        let shouldMove = forceMove || urls.allSatisfy { pendingCutURLs.contains($0.standardizedFileURL) }
        urls.forEach { transfer($0, into: currentFolder, copying: !shouldMove) }
        if shouldMove { pendingCutURLs = [] }
    }

    func copyPath(_ url: URL) {
        copyPaths([url])
    }

    func copyPaths(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    func addFinderTag(name: String, colorIndex: Int, to urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls {
            let existing = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
            let withoutSameName = existing.filter {
                $0.split(separator: "\n", maxSplits: 1).first.map(String.init)?.caseInsensitiveCompare(name) != .orderedSame
            }
            let tag = "\(name)\n\(colorIndex)"
            do {
                try setFinderTags(withoutSameName + [tag], for: url)
            } catch {
                prompt = .error("Couldn’t tag \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        refreshFolder()
    }

    func removeFinderTag(named name: String, from urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls {
            let existing = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
            let remaining = existing.filter {
                $0.split(separator: "\n", maxSplits: 1).first.map(String.init)?.caseInsensitiveCompare(name) != .orderedSame
            }
            try? setFinderTags(remaining, for: url)
        }
        refreshFolder()
    }

    func clearFinderTags(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        urls.forEach { try? setFinderTags([], for: $0) }
        refreshFolder()
    }

    private func setFinderTags(_ tags: [String], for url: URL) throws {
        // Finder stores tags in this binary property-list extended attribute on
        // macOS releases before URLResourceValues exposes a writable tag API.
        let data = try PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0)
        let attribute = "com.apple.metadata:_kMDItemUserTags"
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return attribute.withCString { name in
                data.withUnsafeBytes { bytes in
                    setxattr(path, name, bytes.baseAddress, data.count, 0, 0)
                }
            }
        }
        guard result == 0 else {
            throw FinderTagWriteError.failed(url.lastPathComponent)
        }
    }

    func duplicate(_ url: URL) {
        duplicate([url])
    }

    func duplicateSelectedItems() {
        duplicate(Array(selectedItemURLs))
    }

    func duplicate(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let sources = urls.map(\.standardizedFileURL)
        let destinations = sources.map(uniqueDuplicateURL(for:))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var duplicates: [URL] = []
            for (source, destination) in zip(sources, destinations) {
                if (try? FileManager.default.copyItem(at: source, to: destination)) != nil {
                    duplicates.append(destination)
                }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.selectedItemURLs = Set(duplicates)
                self.selectionAnchorURL = duplicates.first
                self.refreshFolder()
            }
        }
    }

    func selectedItemsOr(_ fallback: URL) -> [URL] {
        selectedItemURLs.contains(fallback) ? Array(selectedItemURLs) : [fallback]
    }

    func selectOnly(_ url: URL) {
        selectedItemURLs = [url]
        selectionAnchorURL = url
    }

    func moveSelection(by offset: Int, extending: Bool = false) {
        guard !currentDirectoryItemURLs.isEmpty else { return }
        let currentIndex = selectedItemURL.flatMap { currentDirectoryItemURLs.firstIndex(of: $0) }
        let index: Int
        if offset == -Int.max {
            index = 0
        } else if offset == Int.max {
            index = currentDirectoryItemURLs.count - 1
        } else if let currentIndex {
            index = min(max(currentIndex + offset, 0), currentDirectoryItemURLs.count - 1)
        } else {
            index = offset < 0 ? currentDirectoryItemURLs.count - 1 : 0
        }
        let url = currentDirectoryItemURLs[index]
        if extending,
           let anchor = selectionAnchorURL,
           let anchorIndex = currentDirectoryItemURLs.firstIndex(of: anchor) {
            selectedItemURLs = Set(currentDirectoryItemURLs[min(anchorIndex, index)...max(anchorIndex, index)])
        } else {
            selectOnly(url)
        }
    }

    func rename(_ url: URL) {
        promptText = url.lastPathComponent
        prompt = .rename(url.standardizedFileURL)
        activateForInput()
    }

    func moveToTrash(_ url: URL) {
        moveToTrash([url])
    }

    func moveSelectedItemsToTrash() {
        moveToTrash(Array(selectedItemURLs))
    }

    func moveToTrash(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.recycle(urls) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.clearSelection()
                self?.refreshFolder()
            }
        }
    }

    func showInfo(for url: URL) {
        prompt = .info(url)
        activateForInput()
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
        clearSelection()
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        currentFolder = navigationHistory[historyIndex]
        clearSelection()
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

    func externalFileDragEnded(with operation: NSDragOperation) {
        guard operation.contains(.move) else { return }
        clearSelection()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refreshFolder()
        }
    }

    func createNewFolder() {
        guard let currentFolder else { return }
        promptText = "Untitled Folder"
        prompt = .newFolder(parent: currentFolder)
        activateForInput()
    }

    func cancelPrompt() {
        prompt = nil
        promptText = ""
    }

    func confirmPrompt() {
        guard let prompt else { return }
        switch prompt {
        case let .newFolder(parent):
            createFolder(named: promptText, in: parent)
        case let .rename(source):
            rename(source, to: promptText)
        case .info, .error:
            cancelPrompt()
        }
    }

    private func createFolder(named rawName: String, in parent: URL) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { return }
        let destination = parent.appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            selectedItemURLs = [destination]
            selectionAnchorURL = destination
            cancelPrompt()
            refreshFolder()
        } catch {
            prompt = .error(error.localizedDescription)
        }
    }

    private func rename(_ source: URL, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { return }
        let destination = source.deletingLastPathComponent().appendingPathComponent(name, isDirectory: source.hasDirectoryPath)
        guard destination != source else { cancelPrompt(); return }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            prompt = .error("A file or folder named \(name) already exists.")
            return
        }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            selectedItemURLs = [destination]
            selectionAnchorURL = destination
            cancelPrompt()
            refreshFolder()
        } catch {
            prompt = .error(error.localizedDescription)
        }
    }

    func receiveFileDrop(_ providers: [NSItemProvider], into destination: URL) -> Bool {
        guard !providers.isEmpty else { return false }
        let shouldCopy = NSEvent.modifierFlags.contains(.option)

        for provider in providers {
            let type = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                ? UTType.fileURL.identifier
                : UTType.url.identifier
            guard provider.hasItemConformingToTypeIdentifier(type) else { continue }
            provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                Task { @MainActor [weak self] in
                    self?.transfer(url, into: destination, copying: shouldCopy)
                }
            }
        }
        return true
    }

    func receiveURLs(_ urls: [URL], into destination: URL) {
        let shouldCopy = NSEvent.modifierFlags.contains(.option)
        urls.forEach { transfer($0, into: destination, copying: shouldCopy) }
    }

    func closeBrowser() {
        navigationHistory.removeAll()
        historyIndex = -1
        currentFolder = nil
        isManagingSets = false
        clearSelection()
        browserPanel?.orderOut(nil)
        show()
    }

    func showSetManager() {
        navigationHistory.removeAll()
        historyIndex = -1
        currentFolder = nil
        isManagingSets = true
        show()
        // The shelf itself stays non-activating, but set management needs keyboard focus.
        activateForInput()
    }

    private func makeShelfPanelIfNeeded() -> DockPanel {
        if let shelfPanel { return shelfPanel }
        let panel = makePanel(size: savedShelfSize(), fixedHeight: 100)
        panel.contentMinSize = NSSize(width: 360, height: 100)
        panel.contentMaxSize = NSSize(width: 2_400, height: 100)
        panel.resizeEndedAction = { [weak self, weak panel] in
            guard let self, let panel else { return }
            UserDefaults.standard.set(panel.frame.width, forKey: "dockShelfWidth")
            self.positionShelf(panel)
            if let browser = self.browserPanel, browser.isVisible {
                self.positionBrowser(browser, below: panel)
            }
        }
        panel.contentView = NSHostingView(rootView: DockView(
            store: store,
            controller: self,
            updateController: updateController
        ))
        shelfPanel = panel
        return panel
    }

    private func makeBrowserPanelIfNeeded() -> DockPanel {
        if let browserPanel { return browserPanel }
        let panel = makePanel(size: savedBrowserSize(), fixedHeight: nil)
        panel.contentMinSize = NSSize(width: 520, height: 300)
        panel.contentMaxSize = NSSize(width: 2_400, height: 1_600)
        panel.resizeEndedAction = { [weak self, weak panel] in
            guard let self, let panel, let shelf = self.shelfPanel else { return }
            UserDefaults.standard.set(panel.frame.width, forKey: "dockBrowserWidth")
            UserDefaults.standard.set(panel.frame.height, forKey: "dockBrowserHeight")
            self.positionBrowser(panel, below: shelf)
        }
        panel.contentView = NSHostingView(rootView: DockBrowserView(store: store, controller: self))
        browserPanel = panel
        return panel
    }

    private func makePanel(size: NSSize, fixedHeight: CGFloat?) -> DockPanel {
        let panel = DockPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.fixedContentHeight = fixedHeight
        panel.escapeAction = { [weak self] in self?.handleEscape() }
        return panel
    }

    private func savedShelfSize() -> NSSize {
        let width = UserDefaults.standard.double(forKey: "dockShelfWidth")
        return NSSize(width: width > 0 ? width : 720, height: 100)
    }

    private func savedBrowserSize() -> NSSize {
        let width = UserDefaults.standard.double(forKey: "dockBrowserWidth")
        let height = UserDefaults.standard.double(forKey: "dockBrowserHeight")
        return NSSize(width: width > 0 ? width : 720, height: height > 0 ? height : 430)
    }

    private func checkPointerPosition() {
        let location = NSEvent.mouseLocation
        guard let screen = screen(containing: location) else { return }

        let inHotZone = abs(location.x - screen.frame.midX) < 210
            && screen.frame.maxY - location.y < 24

        if isInteractionLocked {
            cancelDismissal()
        } else if inHotZone {
            if hasVisiblePanel {
                cancelDismissal()
            } else {
                show()
            }
        } else if hasVisiblePanel && !pointerIsInsideVisiblePanel(location) {
            scheduleDismissal()
        } else {
            cancelDismissal()
        }
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private var hasVisiblePanel: Bool {
        shelfPanel?.isVisible == true || browserPanel?.isVisible == true
    }

    private func pointerIsInsideVisiblePanel(_ point: NSPoint) -> Bool {
        (shelfPanel?.isVisible == true && shelfPanel?.frame.contains(point) == true)
            || (browserPanel?.isVisible == true && browserPanel?.frame.contains(point) == true)
    }

    private func positionShelf(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = screen(containing: mouseLocation) else { return }
        let maximumWidth = max(360, screen.visibleFrame.width - 24)
        if panel.frame.width > maximumWidth {
            panel.setContentSize(NSSize(width: maximumWidth, height: 100))
        }
        let x = screen.frame.midX - panel.frame.width / 2
        let y = screen.visibleFrame.maxY - panel.frame.height - 4
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func positionBrowser(_ panel: NSPanel, below shelf: NSPanel) {
        let screen = shelf.screen ?? screen(containing: NSEvent.mouseLocation) ?? NSScreen.main
        guard let screen else { return }
        let maximumWidth = max(520, screen.visibleFrame.width - 24)
        let maximumHeight = max(300, shelf.frame.minY - screen.visibleFrame.minY - 12)
        var size = panel.frame.size
        size.width = min(max(size.width, 520), maximumWidth)
        size.height = min(max(size.height, 300), maximumHeight)
        if size != panel.frame.size {
            panel.setContentSize(size)
        }
        let x = screen.frame.midX - panel.frame.width / 2
        let y = shelf.frame.minY - panel.frame.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func scheduleDismissal() {
        guard dismissalWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.shelfPanel?.orderOut(nil)
            self?.browserPanel?.orderOut(nil)
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
        clearSelection()
    }

    private func transfer(_ source: URL, into destinationFolder: URL, copying: Bool) {
        let source = source.standardizedFileURL
        let destinationFolder = destinationFolder.standardizedFileURL
        guard source.deletingLastPathComponent() != destinationFolder,
              source.path != destinationFolder.path,
              !destinationFolder.path.hasPrefix(source.path + "/") else { return }

        let target = destinationFolder.appendingPathComponent(source.lastPathComponent, isDirectory: source.hasDirectoryPath)
        guard !FileManager.default.fileExists(atPath: target.path) else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                if copying {
                    try FileManager.default.copyItem(at: source, to: target)
                } else {
                    try FileManager.default.moveItem(at: source, to: target)
                }
                Task { @MainActor [weak self] in
                    self?.refreshFolder()
                }
            } catch {
                // Existing files and failed cross-volume transfers remain untouched.
            }
        }
    }

    private func uniqueDuplicateURL(for source: URL) -> URL {
        let parent = source.deletingLastPathComponent()
        let extensionPart = source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent
        var number = 1
        while true {
            let suffix = number == 1 ? " copy" : " copy \(number)"
            let name = extensionPart.isEmpty ? base + suffix : base + suffix + "." + extensionPart
            let candidate = parent.appendingPathComponent(name, isDirectory: source.hasDirectoryPath)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            number += 1
        }
    }

    private func activateForInput() {
        keepOpen()
        NSApp.activate(ignoringOtherApps: true)
        if currentFolder != nil || isManagingSets {
            browserPanel?.makeKeyAndOrderFront(nil)
        } else {
            shelfPanel?.makeKeyAndOrderFront(nil)
        }
    }

    private func handleShortcutEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .otherMouseDown {
            return handleMouseShortcut(event) ? nil : event
        }

        guard shelfPanel?.isKeyWindow == true || browserPanel?.isKeyWindow == true else { return event }
        if event.keyCode == 53 { // Escape
            handleEscape()
            return nil
        }

        if prompt != nil && (event.keyCode == 36 || event.keyCode == 76) {
            confirmPrompt()
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
        if command && key == "a" { selectAllItems(); return nil }
        if command && key == "c" { copySelectedItemsToPasteboard(); return nil }
        if command && key == "x" { cutSelectedItems(); return nil }
        if command && key == "v" { pasteIntoCurrentFolder(forceMove: option); return nil }
        if command && key == "d" { duplicateSelectedItems(); return nil }
        if command && key == "i", let selectedItemURL { showInfo(for: selectedItemURL); return nil }
        if command && event.keyCode == 51 { moveSelectedItemsToTrash(); return nil } // Command-Delete
        if command && shift && key == "n" { createNewFolder(); return nil }
        if command && key == "n", let currentFolder {
            NSWorkspace.shared.open(currentFolder)
            return nil
        }
        if command && event.keyCode == 126 { goToParentFolder(); return nil } // Command-Up Arrow
        if !command && event.keyCode == 126 { moveSelection(by: -1, extending: shift); return nil } // Up
        if !command && event.keyCode == 125 { moveSelection(by: 1, extending: shift); return nil } // Down
        if !command && event.keyCode == 123 { moveSelection(by: -1, extending: shift); return nil } // Left
        if !command && event.keyCode == 124 { moveSelection(by: 1, extending: shift); return nil } // Right
        if !command && event.keyCode == 115 { moveSelection(by: -Int.max, extending: shift); return nil } // Home
        if !command && event.keyCode == 119 { moveSelection(by: Int.max, extending: shift); return nil } // End
        if event.keyCode == 49 { showQuickLook(); return nil } // Space
        if event.keyCode == 36 || event.keyCode == 76 { openSelectedItem(); return nil } // Return / keypad Enter

        return event
    }

    private func handleGlobalMouseShortcut(_ event: NSEvent) {
        guard pointerIsInsideVisiblePanel(NSEvent.mouseLocation) else { return }
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

private enum FinderTagWriteError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(name): "Finder couldn’t update tags for \(name)."
        }
    }
}

private final class DockPanel: NSPanel, NSWindowDelegate {
    var escapeAction: () -> Void = {}
    var resizeEndedAction: () -> Void = {}
    var fixedContentHeight: CGFloat?

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            escapeAction()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        escapeAction()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let fixedContentHeight else { return frameSize }
        return NSSize(width: frameSize.width, height: fixedContentHeight)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        resizeEndedAction()
    }
}

private final class QuickLookPreviewController: NSObject, QLPreviewPanelDataSource {
    private var previewURLs: [URL] = []

    @MainActor
    func show(urls: [URL]) {
        previewURLs = urls
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
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURLs.indices.contains(index) ? previewURLs[index] as NSURL : nil
    }
}
