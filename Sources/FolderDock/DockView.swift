import AppKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers

private let compactBrowserDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = "dd/MM/yy HH:mm"
    return formatter
}()

struct DockView: View {
    @ObservedObject var store: FolderStore
    @ObservedObject var controller: DockController
    @State private var isTargeted = false
    @State private var draggedSetID: UUID?
    @State private var draggedFolderID: UUID?
    @State private var editingSetID: UUID?
    @State private var editingSetName = ""

    var body: some View {
        shelf
    }

    private var shelf: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(store.folderSets) { set in
                            FolderSetTab(
                                set: set,
                                isSelected: set.id == store.selectedSetID,
                                isEditing: editingSetID == set.id,
                                editingName: $editingSetName,
                                select: { controller.selectSet(set) },
                                startEditing: {
                                    editingSetID = set.id
                                    editingSetName = set.name
                                    controller.keepOpen()
                                },
                                finishEditing: {
                                    store.renameSet(set, to: editingSetName)
                                    editingSetID = nil
                                },
                                startDrag: { draggedSetID = set.id },
                                receiveFolders: { urls in
                                    urls.forEach { store.add(url: $0, toSetID: set.id) }
                                    controller.keepOpen()
                                    return !urls.isEmpty
                                },
                                receiveDrop: { providers in
                                    guard let draggedSetID else { return false }
                                    store.moveSet(draggedSetID, before: set.id)
                                    self.draggedSetID = nil
                                    return true
                                }
                            )
                        }

                        Button(action: controller.showSetManager) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 23, height: 23)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Add a folder set")
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 2) {
                    Text("B\(buildNumber)")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .help("Build \(buildNumber)")

                    Button(action: controller.showSetManager) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 25, height: 25)
                    }
                    .buttonStyle(.plain)
                    .help("Manage folder sets")

                    Button(action: controller.hide) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 25, height: 25)
                    }
                    .buttonStyle(.plain)
                    .help("Hide Folder Dock (Esc)")
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .frame(height: 35)

            Divider()

            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if store.folders.isEmpty {
                            emptyState
                        } else {
                            ForEach(store.folders) { folder in
                                FolderTile(
                                    folder: folder,
                                    store: store,
                                    controller: controller,
                                    onStartDrag: { draggedFolderID = folder.id },
                                    onReceiveDrop: { urls in
                                        if let draggedFolderID {
                                            store.moveFolder(draggedFolderID, before: folder.id)
                                            self.draggedFolderID = nil
                                            return true
                                        }
                                        controller.receiveURLs(urls, into: folder.url)
                                        return !urls.isEmpty
                                    }
                                )
                            }
                        }

                        Button(action: controller.chooseFolders) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 29, height: 29)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Save folders to \(store.selectedSet?.name ?? "this set")")
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 63)
        }
        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 100, maxHeight: 100)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.16), lineWidth: isTargeted ? 2 : 1)
        }
        .overlay(alignment: .bottomLeading) {
            DockResizeHandle(allowsVerticalResize: false, fromLeadingEdge: true) {
                controller.beginShelfResize()
            } onChange: {
                controller.updateShelfResize(fromLeadingEdge: true)
            } onEnd: {
                controller.endShelfResize()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            DockResizeHandle(allowsVerticalResize: false, fromLeadingEdge: false) {
                controller.beginShelfResize()
            } onChange: {
                controller.updateShelfResize(fromLeadingEdge: false)
            } onEnd: {
                controller.endShelfResize()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: acceptDrop(providers:))
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Drag a folder from Finder here")
                .font(.system(size: 13, weight: .medium))
            Text("or choose one with +")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(width: 210, alignment: .leading)
    }

    private func acceptDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                DispatchQueue.main.async {
                    store.add(url: url)
                    controller.keepOpen()
                }
            }
        }
        return !providers.isEmpty
    }
}

struct DockBrowserView: View {
    @ObservedObject var store: FolderStore
    @ObservedObject var controller: DockController

    var body: some View {
        Group {
            if let currentFolder = controller.currentFolder {
                FolderBrowser(folder: currentFolder, controller: controller)
                    .id(currentFolder.standardizedFileURL.path)
            } else if controller.isManagingSets {
                FolderSetManager(store: store, controller: controller)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            DockResizeHandle(allowsVerticalResize: true, fromLeadingEdge: true) {
                controller.beginBrowserResize()
            } onChange: {
                controller.updateBrowserResize(fromLeadingEdge: true)
            } onEnd: {
                controller.endBrowserResize()
            }
        }
        .overlay(alignment: .bottomTrailing) {
            DockResizeHandle(allowsVerticalResize: true, fromLeadingEdge: false) {
                controller.beginBrowserResize()
            } onChange: {
                controller.updateBrowserResize(fromLeadingEdge: false)
            } onEnd: {
                controller.endBrowserResize()
            }
        }
    }
}

private struct DockResizeHandle: View {
    let allowsVerticalResize: Bool
    let fromLeadingEdge: Bool
    let onBegin: () -> Void
    let onChange: () -> Void
    let onEnd: () -> Void
    @State private var isDragging = false

    var body: some View {
        Image(systemName: allowsVerticalResize ? "arrow.up.left.and.arrow.down.right" : "arrow.left.and.right")
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(.secondary.opacity(0.42))
            .scaleEffect(x: fromLeadingEdge ? -1 : 1)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in
                        if !isDragging {
                            isDragging = true
                            onBegin()
                        }
                        onChange()
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEnd()
                    }
            )
            .onHover { hovering in
                if allowsVerticalResize {
                    hovering ? NSCursor.crosshair.set() : NSCursor.arrow.set()
                } else {
                    hovering ? NSCursor.resizeLeftRight.set() : NSCursor.arrow.set()
                }
            }
    }
}

private struct FolderSetTab: View {
    let set: FolderSet
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editingName: String
    let select: () -> Void
    let startEditing: () -> Void
    let finishEditing: () -> Void
    let startDrag: () -> Void
    let receiveFolders: ([URL]) -> Bool
    let receiveDrop: ([NSItemProvider]) -> Bool
    @State private var isDropTarget = false
    @FocusState private var nameIsFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 10, weight: .medium))
            if isEditing {
                TextField("Set name", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(minWidth: 64, maxWidth: 120)
                    .focused($nameIsFocused)
                    .onSubmit(finishEditing)
            } else {
                Text(set.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .padding(.horizontal, 8)
        .frame(height: 23)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture { if !isEditing { select() } }
        .onTapGesture(count: 2, perform: startEditing)
        .contextMenu {
            Button("Rename Set") { startEditing() }
        }
        .help(isEditing ? "Press Return to save" : "Click to switch. Double-click to rename.")
        .onDrag {
            startDrag()
            return NSItemProvider(object: set.id.uuidString as NSString)
        }
        .background(
            isDropTarget ? Color.accentColor.opacity(0.28) : (isSelected ? Color.white.opacity(0.14) : .clear),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .dropDestination(for: URL.self, action: { urls, _ in receiveFolders(urls) }, isTargeted: { isDropTarget = $0 })
        .onDrop(of: [.text], isTargeted: $isDropTarget, perform: receiveDrop)
        .onAppear {
            if isEditing {
                DispatchQueue.main.async { nameIsFocused = true }
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                DispatchQueue.main.async { nameIsFocused = true }
            }
        }
    }
}

private struct FolderTile: View {
    let folder: SavedFolder
    @ObservedObject var store: FolderStore
    @ObservedObject var controller: DockController
    let onStartDrag: () -> Void
    let onReceiveDrop: ([URL]) -> Bool
    private var tags: [FinderTag] { FinderTag.tags(for: folder.url) }

    var body: some View {
        PointerButton(
            primaryAction: { controller.browse(folder) },
            middleAction: { controller.openInNewFinderWindow(folder) },
            dragURL: folder.url,
            dragStarted: onStartDrag,
            receiveDrop: onReceiveDrop,
            contextActions: [
                PointerContextAction(title: "Browse Here", action: { controller.browse(folder) }),
                PointerContextAction(title: "Open in Finder", action: { store.open(folder) }),
                PointerContextAction(title: "Open in New Finder Window", action: { controller.openInNewFinderWindow(folder) }),
                PointerContextAction(title: "Show in Finder", action: { store.showInFinder(folder) }),
                PointerContextAction(title: "-", action: {}),
                PointerContextAction(title: "Remove from Dock", isDestructive: true, action: { store.remove(folder) })
            ]
        ) {
            VStack(spacing: 4) {
                FileIcon(url: folder.url, size: 29, tint: tags.first?.color)
                HStack(spacing: 3) {
                    Text(folder.name)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    FinderTagDots(tags: tags, size: 5)
                }
                .frame(width: 58)
            }
            .padding(.horizontal, 3)
            .frame(width: 66, height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .help("Click to browse. Middle-click to open a new Finder window.")
    }
}

private struct BrowserItem: Identifiable, Sendable {
    let url: URL
    let isDirectory: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var kind: String { isDirectory ? "Folder" : (url.pathExtension.isEmpty ? "Document" : url.pathExtension.uppercased()) }
    var size: Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
    var modificationDate: Date? { try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
    var tags: [FinderTag] { FinderTag.tags(for: url) }
}

private struct FinderTag: Hashable, Sendable {
    let name: String
    let colorIndex: Int
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: (Date, [FinderTag])] = [:]

    static func tags(for url: URL) -> [FinderTag] {
        let cacheKey = url.path
        let now = Date()
        cacheLock.lock()
        if let cached = cache[cacheKey], now.timeIntervalSince(cached.0) < 1.5 {
            cacheLock.unlock()
            return cached.1
        }
        cacheLock.unlock()

        let tagNames = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
        guard !tagNames.isEmpty else {
            cacheLock.lock()
            cache[cacheKey] = (now, [])
            cacheLock.unlock()
            return []
        }
        let rawColorIndexes = rawFinderTags(for: url).reduce(into: [String: Int]()) { result, rawTag in
            let parts = rawTag.split(separator: "\n", maxSplits: 1).map(String.init)
            if let name = parts.first, let index = Int(parts.dropFirst().first ?? "") {
                result[name] = index
            }
        }
        let tags = tagNames.map { rawTag in
            let parts = rawTag.split(separator: "\n", maxSplits: 1).map(String.init)
            let name = parts.first ?? rawTag
            let storedIndex = Int(parts.dropFirst().first ?? "0") ?? 0
            let colorIndex = storedIndex == 0 ? (rawColorIndexes[name] ?? defaultColorIndex(for: name)) : storedIndex
            return FinderTag(name: name, colorIndex: colorIndex)
        }
        cacheLock.lock()
        cache[cacheKey] = (now, tags)
        cacheLock.unlock()
        return tags
    }

    private static func rawFinderTags(for url: URL) -> [String] {
        let attribute = "com.apple.metadata:_kMDItemUserTags"
        let data: Data? = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            return attribute.withCString { name in
                let byteCount = getxattr(path, name, nil, 0, 0, 0)
                guard byteCount > 0 else { return nil }
                var data = Data(count: byteCount)
                let readCount = data.withUnsafeMutableBytes { bytes in
                    getxattr(path, name, bytes.baseAddress, byteCount, 0, 0)
                }
                guard readCount == byteCount else { return nil }
                return data
            }
        }
        guard let data else { return [] }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String] ?? []
    }

    private static func defaultColorIndex(for name: String) -> Int {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "gray", "grey": 1
        case "green": 2
        case "purple": 3
        case "blue": 4
        case "yellow": 5
        case "red": 6
        case "orange": 7
        default: 0
        }
    }

    var color: Color {
        Color(nsColor: nsColor)
    }

    private var nsColor: NSColor {
        switch colorIndex {
        case 1: .systemGray
        case 2: .systemGreen
        case 3: .systemPurple
        case 4: .systemBlue
        case 5: .systemYellow
        case 6: .systemRed
        case 7: .systemOrange
        default: .secondaryLabelColor
        }
    }

    var menuImage: NSImage {
        let image = NSImage(size: NSSize(width: 13, height: 13))
        image.lockFocus()
        nsColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 11, height: 11)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

private struct FinderTagDots: View {
    let tags: [FinderTag]
    var size: CGFloat = 7

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 3) {
                ForEach(tags, id: \.self) { tag in
                    Circle()
                        .fill(tag.color)
                        .frame(width: size, height: size)
                }
            }
            .help(tags.map(\.name).joined(separator: ", "))
        }
    }
}

private struct FinderTagMenu: View {
    let urls: [URL]
    @ObservedObject var controller: DockController

    private let standardTags: [(String, Int)] = [
        ("Red", 6), ("Orange", 7), ("Yellow", 5), ("Green", 2),
        ("Blue", 4), ("Purple", 3), ("Gray", 1)
    ]

    private var existingTagNames: [String] {
        Array(Set(urls.flatMap { FinderTag.tags(for: $0).map(\.name) })).sorted()
    }

    var body: some View {
        Menu("Tags") {
            ForEach(standardTags, id: \.0) { name, colorIndex in
                Button {
                    controller.addFinderTag(name: name, colorIndex: colorIndex, to: urls)
                } label: {
                    HStack(spacing: 7) {
                        Image(nsImage: FinderTag(name: name, colorIndex: colorIndex).menuImage)
                            .renderingMode(.original)
                        Text(name)
                    }
                }
            }
            if !existingTagNames.isEmpty {
                Divider()
                Menu("Remove Tag") {
                    ForEach(existingTagNames, id: \.self) { name in
                        Button(name) { controller.removeFinderTag(named: name, from: urls) }
                    }
                }
                Button("Clear Tags") { controller.clearFinderTags(from: urls) }
            }
        }
    }
}

private enum BrowserSortKey: String {
    case name, kind, size, dateModified
}

private enum DirectoryLoadFailure: Error, Sendable {
    case message(String)
}

private struct FolderBrowser: View {
    let folder: URL
    @ObservedObject var controller: DockController
    @State private var items: [BrowserItem] = []
    @State private var loadedFolderPath: String?
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var isFileDropTarget = false
    @State private var searchText = ""
    @State private var tagRefreshTimer: Timer?
    @State private var tagRefreshTick = 0
    @State private var loadRequestID = UUID()
    @AppStorage("browserViewMode") private var viewMode = "icons"
    @AppStorage("browserListNameColumnWidth") private var nameColumnWidth = 326.0
    @AppStorage("browserListKindColumnWidth") private var kindColumnWidth = 82.0
    @AppStorage("browserListSizeColumnWidth") private var sizeColumnWidth = 66.0
    @AppStorage("browserListDateColumnWidth") private var dateColumnWidth = 132.0
    @AppStorage("browserColumnLayoutVersion") private var columnLayoutVersion = 0
    @AppStorage("browserSortKey") private var sortKeyValue = BrowserSortKey.name.rawValue
    @AppStorage("browserSortAscending") private var sortAscending = true

    private let columns = [GridItem(.adaptive(minimum: 86, maximum: 104), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: controller.goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!controller.canGoBack)
                .opacity(controller.canGoBack ? 1 : 0.35)
                .help("Back")

                Button(action: controller.goForward) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!controller.canGoForward)
                .opacity(controller.canGoForward ? 1 : 0.35)
                .help("Forward")

                Button(action: controller.goToParentFolder) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("Enclosing Folder (⌘↑)")

                FileIcon(url: folder, size: 21, tint: FinderTag.tags(for: folder).first?.color)

                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(folder.path)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 72, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)

                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                    .frame(width: 118)
                    .help("Filter this folder")

                Button(action: controller.createNewFolder) {
                    Image(systemName: "folder.badge.plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("New Folder (⇧⌘N)")

                Button(action: controller.refreshFolder) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Refresh (⌘R)")

                Menu {
                    Button {
                        viewMode = "icons"
                    } label: {
                        Label("Icon View", systemImage: viewMode == "icons" ? "checkmark" : "square.grid.2x2")
                    }
                    Button {
                        viewMode = "list"
                    } label: {
                        Label("List View", systemImage: viewMode == "list" ? "checkmark" : "list.bullet")
                    }
                } label: {
                    Image(systemName: viewMode == "list" ? "list.bullet" : "square.grid.2x2")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .help("Change view")

                Button {
                    NSWorkspace.shared.open(folder)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Open this folder in Finder")

                Button(action: controller.closeBrowser) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Return to saved folders")
            }
            .padding(.horizontal, 14)
            .frame(height: 54)

            Divider()

            if let bannerPrompt {
                BrowserNotice(prompt: bannerPrompt, controller: controller)
                Divider()
            }

            Group {
                if isLoading || loadedFolderPath != folder.standardizedFileURL.path {
                    ProgressView("Loading \(folder.lastPathComponent)…")
                        .controlSize(.small)
                } else if let loadError {
                    ContentUnavailableView("Couldn't open this folder", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if items.isEmpty && !isCreatingFolder {
                    ContentUnavailableView("This folder is empty", systemImage: "folder")
                } else {
                    if viewMode == "list" {
                        listView
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 14) {
                                if isCreatingFolder {
                                    BrowserNewFolderTile(controller: controller)
                                }
                                ForEach(visibleItems) { item in
                                    BrowserItemTile(item: item, orderedURLs: visibleItems.map(\.url), refreshTick: tagRefreshTick, controller: controller)
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .overlay {
            if isFileDropTarget {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(2)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isFileDropTarget) { providers in
            controller.receiveFileDrop(providers, into: folder)
        }
        .onAppear {
            migrateColumnLayoutIfNeeded()
            loadItems()
            tagRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in
                    tagRefreshTick &+= 1
                    loadItems(showLoading: false)
                }
            }
        }
        .onDisappear {
            tagRefreshTimer?.invalidate()
            tagRefreshTimer = nil
            loadRequestID = UUID()
        }
        .onChange(of: folder.path) { _, _ in
            loadRequestID = UUID()
            items = []
            loadedFolderPath = nil
            loadError = nil
            searchText = ""
            controller.updateCurrentDirectoryItems([])
            loadItems()
        }
        .onChange(of: controller.directoryRevision) { _, _ in loadItems() }
        .onChange(of: sortKeyValue) { _, _ in updateSelectionOrder() }
        .onChange(of: sortAscending) { _, _ in updateSelectionOrder() }
        .onChange(of: searchText) { _, _ in updateSelectionOrder() }
    }

    private func loadItems(showLoading: Bool = true) {
        let directory = folder
        let requestID = UUID()
        loadRequestID = requestID
        if showLoading && items.isEmpty {
            isLoading = true
            loadedFolderPath = nil
        }
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.readItems(in: directory)
            }.value

            guard requestID == loadRequestID else { return }
            isLoading = false
            switch result {
            case let .success(loadedItems):
                loadedFolderPath = directory.standardizedFileURL.path
                if items.map(\.url) != loadedItems.map(\.url) {
                    items = loadedItems
                }
                updateSelectionOrder()
                loadError = nil
            case let .failure(.message(message)):
                items = []
                loadedFolderPath = nil
                controller.updateCurrentDirectoryItems([])
                loadError = message
            }
        }
    }

    private func migrateColumnLayoutIfNeeded() {
        guard columnLayoutVersion < 1 else { return }
        // Older builds persisted a table wider than the browser, which made the
        // Date Modified column appear clipped on every launch. Keep every column
        // visible initially; users can still drag a separator wider when needed.
        nameColumnWidth = 326
        kindColumnWidth = 82
        sizeColumnWidth = 66
        dateColumnWidth = 132
        columnLayoutVersion = 1
    }

    nonisolated private static func readItems(in folder: URL) -> Result<[BrowserItem], DirectoryLoadFailure> {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            )
            let items = urls.compactMap { url -> BrowserItem? in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return BrowserItem(url: url, isDirectory: values?.isDirectory ?? false)
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return .success(items)
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    private var listView: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        SortHeader(title: "Name", key: .name, activeKey: sortKey, ascending: sortAscending, action: changeSort)
                            .frame(width: nameWidth, alignment: .leading)
                        ColumnResizeHandle(width: $nameColumnWidth, range: 180...1_200)
                        SortHeader(title: "Kind", key: .kind, activeKey: sortKey, ascending: sortAscending, action: changeSort)
                            .frame(width: kindWidth, alignment: .leading)
                        ColumnResizeHandle(width: $kindColumnWidth, range: 60...360)
                        SortHeader(title: "Size", key: .size, activeKey: sortKey, ascending: sortAscending, action: changeSort)
                            .frame(width: sizeWidth, alignment: .trailing)
                        ColumnResizeHandle(width: $sizeColumnWidth, range: 56...220)
                        SortHeader(title: "Date Modified", key: .dateModified, activeKey: sortKey, ascending: sortAscending, action: changeSort)
                            .frame(width: dateWidth, alignment: .leading)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .frame(height: 28)
                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 2) {
                            if isCreatingFolder {
                                BrowserNewFolderRow(
                                    nameWidth: nameWidth,
                                    kindWidth: kindWidth,
                                    sizeWidth: sizeWidth,
                                    dateWidth: dateWidth,
                                    controller: controller
                                )
                            }
                            ForEach(visibleItems) { item in
                                BrowserListRow(
                                    item: item,
                                    orderedURLs: visibleItems.map(\.url),
                                    nameWidth: nameWidth,
                                    kindWidth: kindWidth,
                                    sizeWidth: sizeWidth,
                                    dateWidth: dateWidth,
                                    refreshTick: tagRefreshTick,
                                    controller: controller
                                )
                            }
                        }
                        .padding(8)
                    }
                }
                .frame(width: max(tableWidth, proxy.size.width), height: proxy.size.height, alignment: .topLeading)
            }
        }
    }

    private var nameWidth: CGFloat { CGFloat(nameColumnWidth) }
    private var kindWidth: CGFloat { CGFloat(kindColumnWidth) }
    private var sizeWidth: CGFloat { CGFloat(sizeColumnWidth) }
    private var dateWidth: CGFloat { CGFloat(dateColumnWidth) }
    private var tableWidth: CGFloat { nameWidth + kindWidth + sizeWidth + dateWidth + 72 }
    private var sortKey: BrowserSortKey { BrowserSortKey(rawValue: sortKeyValue) ?? .name }
    private var sortedItems: [BrowserItem] {
        items.sorted { lhs, rhs in
            let result: ComparisonResult
            switch sortKey {
            case .name: result = lhs.name.localizedStandardCompare(rhs.name)
            case .kind: result = lhs.kind.localizedStandardCompare(rhs.kind)
            case .size:
                if lhs.size == rhs.size { result = lhs.name.localizedStandardCompare(rhs.name) }
                else { result = lhs.size < rhs.size ? .orderedAscending : .orderedDescending }
            case .dateModified:
                let lhsDate = lhs.modificationDate ?? .distantPast
                let rhsDate = rhs.modificationDate ?? .distantPast
                if lhsDate == rhsDate { result = lhs.name.localizedStandardCompare(rhs.name) }
                else { result = lhsDate < rhsDate ? .orderedAscending : .orderedDescending }
            }
            return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
    }
    private var visibleItems: [BrowserItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sortedItems }
        return sortedItems.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.kind.localizedCaseInsensitiveContains(query)
        }
    }
    private var isCreatingFolder: Bool {
        if case let .newFolder(parent) = controller.prompt {
            return parent.standardizedFileURL == folder.standardizedFileURL
        }
        return false
    }
    private var bannerPrompt: DockPrompt? {
        switch controller.prompt {
        case .info, .error: controller.prompt
        case .newFolder, .rename, .none: nil
        }
    }

    private func changeSort(_ key: BrowserSortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKeyValue = key.rawValue
            sortAscending = true
        }
        updateSelectionOrder()
    }

    private func updateSelectionOrder() {
        controller.updateCurrentDirectoryItems(visibleItems.map(\.url))
    }
}

private struct SortHeader: View {
    let title: String
    let key: BrowserSortKey
    let activeKey: BrowserSortKey
    let ascending: Bool
    let action: (BrowserSortKey) -> Void

    var body: some View {
        Button { action(key) } label: {
            HStack(spacing: 4) {
                Text(title)
                if activeKey == key {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sort by \(title)")
    }
}

private struct ColumnResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    @State private var dragStart: Double?
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(isHovering ? Color.accentColor.opacity(0.8) : Color.clear)
            .frame(width: 8, height: 24)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStart == nil { dragStart = width }
                        guard let dragStart else { return }
                        width = min(max(dragStart + value.translation.width, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .help("Drag to resize this column")
    }
}

private struct BrowserNotice: View {
    let prompt: DockPrompt
    @ObservedObject var controller: DockController

    private var isError: Bool {
        if case .error = prompt { return true }
        return false
    }

    private var text: String {
        switch prompt {
        case let .info(url):
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            let kind = values?.isDirectory == true ? "Folder" : (url.pathExtension.isEmpty ? "Document" : url.pathExtension.uppercased() + " file")
            let size = values?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "—"
            let date = values?.contentModificationDate.map { " · Modified \($0.formatted(date: .abbreviated, time: .shortened))" } ?? ""
            return "\(url.lastPathComponent) · \(kind) · \(size)\(date)\n\(url.path)"
        case let .error(message): return message
        case .newFolder, .rename: return ""
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isError ? Color.orange : Color.accentColor)
            Text(text)
                .font(.system(size: 10))
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button(action: controller.cancelPrompt) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .background(isError ? Color.orange.opacity(0.09) : Color.accentColor.opacity(0.08))
    }
}

private struct BrowserNewFolderTile: View {
    @ObservedObject var controller: DockController
    @FocusState private var nameIsFocused: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 35, weight: .light))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
            TextField("Folder name", text: $controller.promptText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, weight: .medium))
                .focused($nameIsFocused)
                .onSubmit(controller.confirmPrompt)
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .top)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear { DispatchQueue.main.async { nameIsFocused = true } }
    }
}

private struct BrowserNewFolderRow: View {
    let nameWidth: CGFloat
    let kindWidth: CGFloat
    let sizeWidth: CGFloat
    let dateWidth: CGFloat
    @ObservedObject var controller: DockController
    @FocusState private var nameIsFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
                TextField("New Folder", text: $controller.promptText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .focused($nameIsFocused)
                    .onSubmit(controller.confirmPrompt)
            }
            .frame(width: nameWidth, alignment: .leading)
            Text("Folder")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: kindWidth, alignment: .leading)
            Text("—")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: sizeWidth, alignment: .trailing)
            Text("—")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: dateWidth, alignment: .leading)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: 32)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onAppear { DispatchQueue.main.async { nameIsFocused = true } }
    }
}

private struct InlineNameField: View {
    @ObservedObject var controller: DockController
    let centered: Bool
    @FocusState private var nameIsFocused: Bool

    var body: some View {
        TextField("Name", text: $controller.promptText)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, weight: .medium))
            .multilineTextAlignment(centered ? .center : .leading)
            .focused($nameIsFocused)
            .onSubmit(controller.confirmPrompt)
            .onAppear { DispatchQueue.main.async { nameIsFocused = true } }
    }
}

private struct BrowserItemTile: View {
    let item: BrowserItem
    let orderedURLs: [URL]
    let refreshTick: Int
    @ObservedObject var controller: DockController
    @State private var isFileDropTarget = false

    private var isSelected: Bool { controller.selectedItemURLs.contains(item.url) }
    private var isRenaming: Bool {
        if case let .rename(url) = controller.prompt { return url == item.url }
        return false
    }

    var body: some View {
        VStack(spacing: 7) {
            if item.isDirectory {
                FileIcon(url: item.url, size: 42, tint: item.tags.first?.color)
            } else {
                FilePreview(url: item.url, size: 42)
            }
            if isRenaming {
                InlineNameField(controller: controller, centered: true)
            } else {
                Text(item.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            FinderTagDots(tags: item.tags, size: 6)
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(isSelected ? Color.accentColor.opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if item.isDirectory && isFileDropTarget {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            } else if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1)
            }
        }
        .overlay(alignment: .topTrailing) {
            if item.isDirectory {
                Button {
                    controller.openInBrowser(item.url)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .help("Browse this folder")
            }
        }
        .onTapGesture(count: 2) {
            controller.openInBrowser(item.url)
        }
        .onTapGesture {
            controller.selectItem(item.url, orderedURLs: orderedURLs)
        }
        .draggable(item.url)
        .onDrop(of: [.fileURL], isTargeted: $isFileDropTarget) { providers in
            guard item.isDirectory else { return false }
            return controller.receiveFileDrop(providers, into: item.url)
        }
        .contextMenu {
            FileItemContextMenu(item: item, controller: controller)
        }
    }
}

private struct BrowserListRow: View {
    let item: BrowserItem
    let orderedURLs: [URL]
    let nameWidth: CGFloat
    let kindWidth: CGFloat
    let sizeWidth: CGFloat
    let dateWidth: CGFloat
    let refreshTick: Int
    @ObservedObject var controller: DockController
    @State private var isFileDropTarget = false

    private var isSelected: Bool { controller.selectedItemURLs.contains(item.url) }
    private var isRenaming: Bool {
        if case let .rename(url) = controller.prompt { return url == item.url }
        return false
    }
    private var kind: String { item.isDirectory ? "Folder" : (item.url.pathExtension.isEmpty ? "Document" : item.url.pathExtension.uppercased()) }
    private var size: String {
        guard !item.isDirectory,
              let bytes = try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
    private var modified: String {
        guard let date = item.modificationDate else { return "—" }
        return compactBrowserDateFormatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                if item.isDirectory {
                    FileIcon(url: item.url, size: 22, tint: item.tags.first?.color)
                } else {
                    FilePreview(url: item.url, size: 22)
                }
                if isRenaming {
                    InlineNameField(controller: controller, centered: false)
                } else {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                FinderTagDots(tags: item.tags)
                Spacer(minLength: 4)
                if item.isDirectory {
                    Button {
                        controller.openInBrowser(item.url)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Browse this folder")
                }
            }
            .frame(width: nameWidth, alignment: .leading)
            Text(kind)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: kindWidth, alignment: .leading)
            Text(size)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: sizeWidth, alignment: .trailing)
            Text(modified)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: dateWidth, alignment: .leading)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: 32)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .background(isSelected ? Color.accentColor.opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            if item.isDirectory && isFileDropTarget {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .onTapGesture(count: 2) {
            controller.openInBrowser(item.url)
        }
        .onTapGesture {
            controller.selectItem(item.url, orderedURLs: orderedURLs)
        }
        .draggable(item.url)
        .onDrop(of: [.fileURL], isTargeted: $isFileDropTarget) { providers in
            guard item.isDirectory else { return false }
            return controller.receiveFileDrop(providers, into: item.url)
        }
        .contextMenu {
            FileItemContextMenu(item: item, controller: controller)
        }
    }
}

private struct FileItemContextMenu: View {
    let item: BrowserItem
    @ObservedObject var controller: DockController

    private var targets: [URL] { controller.selectedItemsOr(item.url) }
    private var targetCount: Int { targets.count }
    private var actionSuffix: String { targetCount == 1 ? "" : " (\(targetCount) Items)" }

    var body: some View {
        if item.isDirectory {
            Button("Browse Here") { controller.openInBrowser(item.url) }
        }
        Button("Open\(actionSuffix)") { controller.openItems(targets) }
        Button("Quick Look") {
            controller.quickLook(targets)
        }
        Divider()
        Button("Rename…") { controller.rename(item.url) }
            .disabled(targetCount != 1)
        Button("Duplicate\(actionSuffix)") { controller.duplicate(targets) }
        Button("Copy\(actionSuffix)") { controller.copyToPasteboard(targets) }
        Button("Cut\(actionSuffix)") { controller.cutItems(targets) }
        Button("Copy Path\(actionSuffix)") { controller.copyPaths(targets) }
        Button("Get Info") { controller.showInfo(for: item.url) }
            .disabled(targetCount != 1)
        FinderTagMenu(urls: targets, controller: controller)
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(targets)
        }
        Button("Move to Trash\(actionSuffix)", role: .destructive) {
            controller.moveToTrash(targets)
        }
    }
}

struct FileIcon: View {
    let url: URL
    let size: CGFloat
    var tint: Color? = nil

    var body: some View {
        Group {
            if let tint {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(tint)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
            }
        }
        .frame(width: size, height: size)
    }
}
