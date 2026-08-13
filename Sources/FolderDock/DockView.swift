import AppKit
import Darwin
import FolderDockCore
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

private struct ShelfItemFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ShelfViewportWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DockView: View {
    @ObservedObject var store: FolderStore
    @ObservedObject var controller: DockController
    @ObservedObject var updateController: UpdateController
    @State private var isTargeted = false
    @State private var draggedSetID: UUID?
    @State private var selectedShelfItemIDs = Set<UUID>()
    @State private var shelfSelectionAnchorID: UUID?
    @State private var draggedShelfItemIDs: [UUID] = []
    @State private var shelfItemFrames: [UUID: CGRect] = [:]
    @State private var shelfMarqueeStart: CGPoint?
    @State private var shelfMarqueeCurrent: CGPoint?
    @State private var shelfMarqueeBaseSelection = Set<UUID>()
    @State private var shelfMarqueeAccumulatedIDs = Set<UUID>()
    @State private var isShelfMarqueeAllowed: Bool?
    @State private var shelfViewportWidth: CGFloat = 0
    @State private var shelfAutoScrollDirection: ShelfAutoScrollDirection?
    @State private var shelfAutoScrollTask: Task<Void, Never>?
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

                    if updateController.isUpdateAvailable {
                        Button("Update") {
                            updateController.checkForUpdates()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .help(updateHelpText)
                    }

                    Button(action: controller.showSetManager) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 25, height: 25)
                    }
                    .buttonStyle(.plain)
                    .help("Manage folder sets")

                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 25, height: 25)
                    }
                    .buttonStyle(.plain)
                    .help("Folder Dock settings")

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
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if store.folders.isEmpty {
                                emptyState
                            } else {
                                ForEach(store.folders) { folder in
                                    FolderTile(
                                    folder: folder,
                                    isSelected: selectedShelfItemIDs.contains(folder.id),
                                    store: store,
                                    controller: controller,
                                    primaryAction: { selectShelfItem(folder) },
                                    actionItems: { shelfActionItems(for: folder) },
                                    onContextMenu: { prepareShelfContextMenu(for: folder) },
                                    onStartDrag: { beginShelfDrag(from: folder) },
                                    onEndDrag: { draggedShelfItemIDs = [] },
                                    onReceiveDrop: { urls in
                                        if !draggedShelfItemIDs.isEmpty {
                                            guard !draggedShelfItemIDs.contains(folder.id) else { return false }
                                            store.moveFolders(draggedShelfItemIDs, before: folder.id)
                                            self.draggedShelfItemIDs = []
                                            return true
                                        }
                                        guard folder.isDirectory else { return false }
                                        controller.receiveURLs(urls, into: folder.url)
                                        return !urls.isEmpty
                                    }
                                    )
                                    .id(folder.id)
                                }
                            }

                            Button(action: controller.chooseFolders) {
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 29, height: 29)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help("Save files or folders to \(store.selectedSet?.name ?? "this set")")
                        }
                        .padding(.vertical, 3)
                    }
                    .coordinateSpace(name: "savedShelf")
                    .contentShape(Rectangle())
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ShelfViewportWidthPreferenceKey.self,
                                value: proxy.size.width
                            )
                        }
                    }
                    .onPreferenceChange(ShelfViewportWidthPreferenceKey.self) { shelfViewportWidth = $0 }
                    .onPreferenceChange(ShelfItemFramesPreferenceKey.self) { frames in
                        shelfItemFrames = frames
                        updateShelfSelectionForCurrentMarquee()
                    }
                    .simultaneousGesture(shelfMarqueeGesture(using: scrollProxy))
                    .simultaneousGesture(shelfBlankTapGesture)
                    .overlay(alignment: .topLeading) {
                        if let marqueeRect = shelfMarqueeRect {
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.14))
                                .overlay {
                                    Rectangle()
                                        .stroke(Color.accentColor.opacity(0.85), lineWidth: 1)
                                }
                                .frame(width: marqueeRect.width, height: marqueeRect.height)
                                .offset(x: marqueeRect.minX, y: marqueeRect.minY)
                                .allowsHitTesting(false)
                        }
                    }
                    .onDisappear(perform: stopShelfAutoScroll)
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
        .onChange(of: store.selectedSetID) { _, _ in
            clearShelfSelection()
        }
        .onChange(of: store.folders.map(\.id)) { _, itemIDs in
            let validIDs = Set(itemIDs)
            selectedShelfItemIDs.formIntersection(validIDs)
            if let shelfSelectionAnchorID, !validIDs.contains(shelfSelectionAnchorID) {
                self.shelfSelectionAnchorID = selectedShelfItemIDs.first
            }
        }
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    private var updateHelpText: String {
        if let version = updateController.availableVersion {
            return "Install Folder Dock \(version)"
        }
        return "Install update"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Drag files or folders here")
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

    private func selectShelfItem(_ item: SavedFolder) {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let orderedIDs = store.folders.map(\.id)

        if modifiers.contains(.shift),
           let anchor = shelfSelectionAnchorID,
           let anchorIndex = orderedIDs.firstIndex(of: anchor),
           let itemIndex = orderedIDs.firstIndex(of: item.id) {
            let range = min(anchorIndex, itemIndex)...max(anchorIndex, itemIndex)
            let rangeIDs = Set(orderedIDs[range])
            if modifiers.contains(.command) {
                selectedShelfItemIDs.formUnion(rangeIDs)
            } else {
                selectedShelfItemIDs = rangeIDs
            }
            controller.keepOpen()
            return
        }

        if modifiers.contains(.command) {
            if selectedShelfItemIDs.contains(item.id) {
                selectedShelfItemIDs.remove(item.id)
            } else {
                selectedShelfItemIDs.insert(item.id)
            }
            shelfSelectionAnchorID = item.id
            controller.keepOpen()
            return
        }

        selectedShelfItemIDs = [item.id]
        shelfSelectionAnchorID = item.id
        controller.keepOpen()
    }

    private func shelfActionItems(for item: SavedFolder) -> [SavedFolder] {
        ShelfActionTargetResolver.resolve(
            clickedItem: item,
            selectedIDs: selectedShelfItemIDs,
            orderedItems: store.folders,
            id: \.id
        )
    }

    private func prepareShelfContextMenu(for item: SavedFolder) {
        if !selectedShelfItemIDs.contains(item.id) {
            selectedShelfItemIDs = [item.id]
            shelfSelectionAnchorID = item.id
        }
        controller.keepOpen()
    }

    private func beginShelfDrag(from item: SavedFolder) {
        if !selectedShelfItemIDs.contains(item.id) {
            selectedShelfItemIDs = [item.id]
            shelfSelectionAnchorID = item.id
        }
        draggedShelfItemIDs = store.folders
            .filter { selectedShelfItemIDs.contains($0.id) }
            .map(\.id)
        controller.keepOpen()
    }

    private func clearShelfSelection() {
        selectedShelfItemIDs.removeAll()
        shelfSelectionAnchorID = nil
        draggedShelfItemIDs = []
        endShelfMarquee()
    }

    private func shelfMarqueeGesture(using scrollProxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("savedShelf"))
            .onChanged { value in updateShelfMarquee(value, using: scrollProxy) }
            .onEnded { _ in
                if isShelfMarqueeAllowed == true {
                    shelfSelectionAnchorID = store.folders.last(where: {
                        selectedShelfItemIDs.contains($0.id)
                    })?.id
                    controller.keepOpen()
                }
                endShelfMarquee()
            }
    }

    private var shelfBlankTapGesture: some Gesture {
        SpatialTapGesture(coordinateSpace: .named("savedShelf"))
            .onEnded { value in
                let tappedItem = shelfItemFrames.values.contains { frame in
                    frame.insetBy(dx: -2, dy: -2).contains(value.location)
                }
                guard !tappedItem else { return }
                clearShelfSelection()
                controller.keepOpen()
            }
    }

    private var shelfMarqueeRect: CGRect? {
        guard isShelfMarqueeAllowed == true,
              let start = shelfMarqueeStart,
              let current = shelfMarqueeCurrent else { return nil }
        return selectionRect(from: start, to: current)
    }

    private func updateShelfMarquee(_ value: DragGesture.Value, using scrollProxy: ScrollViewProxy) {
        if isShelfMarqueeAllowed == nil {
            let startedOnItem = shelfItemFrames.values.contains { frame in
                frame.insetBy(dx: -2, dy: -2).contains(value.startLocation)
            }
            isShelfMarqueeAllowed = !startedOnItem
            guard !startedOnItem else { return }

            shelfMarqueeStart = value.startLocation
            shelfMarqueeAccumulatedIDs = []
            let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            shelfMarqueeBaseSelection = modifiers.contains(.command) ? selectedShelfItemIDs : []
        }

        guard isShelfMarqueeAllowed == true, shelfMarqueeStart != nil else { return }
        shelfMarqueeCurrent = value.location
        updateShelfSelectionForCurrentMarquee()
        updateShelfAutoScroll(for: value.location.x, using: scrollProxy)
        controller.keepOpen()
    }

    private func updateShelfSelectionForCurrentMarquee() {
        guard isShelfMarqueeAllowed == true,
              let start = shelfMarqueeStart,
              let current = shelfMarqueeCurrent else { return }
        let marquee = selectionRect(from: start, to: current)
        let intersectingIDs = Set(shelfItemFrames.compactMap { id, frame in
            marquee.intersects(frame) ? id : nil
        })
        if shelfAutoScrollDirection != nil {
            shelfMarqueeAccumulatedIDs.formUnion(intersectingIDs)
        }
        selectedShelfItemIDs = shelfMarqueeBaseSelection
            .union(shelfMarqueeAccumulatedIDs)
            .union(intersectingIDs)
    }

    private func updateShelfAutoScroll(for pointerX: CGFloat, using scrollProxy: ScrollViewProxy) {
        let edgeThreshold: CGFloat = 26
        let direction: ShelfAutoScrollDirection?
        if pointerX <= edgeThreshold {
            direction = .backward
        } else if shelfViewportWidth > 0 && pointerX >= shelfViewportWidth - edgeThreshold {
            direction = .forward
        } else {
            direction = nil
        }

        guard direction != shelfAutoScrollDirection else { return }
        stopShelfAutoScroll()
        shelfAutoScrollDirection = direction
        guard let direction else { return }

        shelfMarqueeAccumulatedIDs.formUnion(selectedShelfItemIDs.subtracting(shelfMarqueeBaseSelection))
        autoScrollShelf(direction: direction, using: scrollProxy)
        shelfAutoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                autoScrollShelf(direction: direction, using: scrollProxy)
            }
        }
    }

    private func autoScrollShelf(direction: ShelfAutoScrollDirection, using scrollProxy: ScrollViewProxy) {
        guard isShelfMarqueeAllowed == true,
              shelfAutoScrollDirection == direction,
              shelfViewportWidth > 0 else { return }
        let orderedIDs = store.folders.map(\.id)
        let visibleIDs = Set(shelfItemFrames.compactMap { id, frame in
            frame.maxX > 0 && frame.minX < shelfViewportWidth ? id : nil
        })
        guard let targetID = ShelfAutoScrollTargetResolver.resolve(
            direction: direction,
            orderedIDs: orderedIDs,
            visibleIDs: visibleIDs
        ) else { return }

        shelfMarqueeAccumulatedIDs.insert(targetID)
        selectedShelfItemIDs = shelfMarqueeBaseSelection.union(shelfMarqueeAccumulatedIDs)
        withAnimation(.linear(duration: 0.08)) {
            scrollProxy.scrollTo(targetID, anchor: direction == .backward ? .leading : .trailing)
        }
        controller.keepOpen()
    }

    private func stopShelfAutoScroll() {
        shelfAutoScrollTask?.cancel()
        shelfAutoScrollTask = nil
        shelfAutoScrollDirection = nil
    }

    private func selectionRect(from start: CGPoint, to current: CGPoint) -> CGRect {
        let minimumThickness: CGFloat = 4
        let minX = min(start.x, current.x)
        let minY = min(start.y, current.y)
        let width = max(abs(current.x - start.x), minimumThickness)
        let height = max(abs(current.y - start.y), minimumThickness)
        return CGRect(
            x: current.x >= start.x ? minX : minX - (width - abs(current.x - start.x)),
            y: current.y >= start.y ? minY : minY - (height - abs(current.y - start.y)),
            width: width,
            height: height
        )
    }

    private func endShelfMarquee() {
        stopShelfAutoScroll()
        shelfMarqueeStart = nil
        shelfMarqueeCurrent = nil
        shelfMarqueeBaseSelection = []
        shelfMarqueeAccumulatedIDs = []
        isShelfMarqueeAllowed = nil
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
        .contextMenu {
            Button {
                startEditing()
            } label: {
                Label("Rename Set…", systemImage: "pencil")
            }
        }
        .help(isEditing ? "Press Return to save" : "Click to switch. Right-click to rename.")
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
    let isSelected: Bool
    @ObservedObject var store: FolderStore
    @ObservedObject var controller: DockController
    let primaryAction: () -> Void
    let actionItems: () -> [SavedFolder]
    let onContextMenu: () -> Void
    let onStartDrag: () -> Void
    let onEndDrag: () -> Void
    let onReceiveDrop: ([URL]) -> Bool
    @State private var tags: [FinderTag] = []
    private var contextActions: [PointerContextAction] {
        let targets = actionItems()
        let urls = targets.map(\.url)
        let count = targets.count
        let suffix = count > 1 ? " (\(count) Items)" : ""

        if count > 1 {
            var actions = [
                PointerContextAction(title: "Open\(suffix)", systemImageName: "arrow.up.forward.app", action: { store.open(targets) }),
                PointerContextAction(title: "Quick Look\(suffix)", systemImageName: "eye", action: { controller.quickLook(urls) }),
                PointerContextAction(title: "Show in Finder\(suffix)", systemImageName: "scope", action: { store.showInFinder(targets) }),
                PointerContextAction(title: "Copy Paths\(suffix)", systemImageName: "link", action: { controller.copyPaths(urls) })
            ]
            if targets.allSatisfy(\.isDirectory) {
                actions.insert(
                    PointerContextAction(title: "Open in New Finder Windows\(suffix)", systemImageName: "macwindow.badge.plus", action: {
                        targets.forEach(controller.openInNewFinderWindow)
                    }),
                    at: 1
                )
            }
            actions.append(PointerContextAction(title: "-", action: {}))
            actions.append(PointerContextAction(
                title: "Remove from Dock\(suffix)",
                systemImageName: "minus.circle",
                isDestructive: true,
                action: { store.remove(targets) }
            ))
            return actions
        }

        if folder.isDirectory {
            return [
                PointerContextAction(title: "Browse Here", systemImageName: "folder", action: { controller.browse(folder) }),
                PointerContextAction(title: "Open in Finder", systemImageName: "arrow.up.forward.app", action: { store.open(folder) }),
                PointerContextAction(title: "Open in New Finder Window", systemImageName: "macwindow.badge.plus", action: { controller.openInNewFinderWindow(folder) }),
                PointerContextAction(title: "Show in Finder", systemImageName: "scope", action: { store.showInFinder(folder) }),
                PointerContextAction(title: "Copy Path", systemImageName: "link", action: { controller.copyPath(folder.url) }),
                PointerContextAction(title: "-", action: {}),
                PointerContextAction(title: "Remove from Dock", systemImageName: "minus.circle", isDestructive: true, action: { store.remove(folder) })
            ]
        }

        return [
            PointerContextAction(title: "Open", systemImageName: "arrow.up.forward.app", action: { store.open(folder) }),
            PointerContextAction(title: "Quick Look", systemImageName: "eye", action: { controller.quickLook([folder.url]) }),
            PointerContextAction(title: "Show in Finder", systemImageName: "scope", action: { store.showInFinder(folder) }),
            PointerContextAction(title: "Copy Path", systemImageName: "link", action: { controller.copyPath(folder.url) }),
            PointerContextAction(title: "-", action: {}),
            PointerContextAction(title: "Remove from Dock", systemImageName: "minus.circle", isDestructive: true, action: { store.remove(folder) })
        ]
    }

    var body: some View {
        PointerButton(
            primaryAction: primaryAction,
            doubleAction: { controller.browse(folder) },
            middleAction: {
                if folder.isDirectory {
                    controller.openInNewFinderWindow(folder)
                } else {
                    store.open(folder)
                }
            },
            dragURLs: { actionItems().map(\.url) },
            dragStarted: onStartDrag,
            dragEnded: { _ in onEndDrag() },
            receiveDrop: onReceiveDrop,
            contextMenuStarted: onContextMenu,
            contextActions: contextActions
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
            .background(
                isSelected ? Color.accentColor.opacity(0.24) : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.9) : .clear, lineWidth: 1)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ShelfItemFramesPreferenceKey.self,
                        value: [folder.id: proxy.frame(in: .named("savedShelf"))]
                    )
                }
            }
        }
        .task(id: folder.path) {
            let url = folder.url
            let loadedTags = await Task.detached(priority: .userInitiated) {
                FinderTag.tags(for: url)
            }.value
            guard !Task.isCancelled else { return }
            tags = loadedTags
        }
        .help(folder.isDirectory
            ? "Click to select. Double-click to browse. Command-click or Shift-click selects multiple items."
            : "Click to select. Double-click to open. Command-click or Shift-click selects multiple items.")
    }
}

private struct BrowserItem: Identifiable, Sendable, Equatable {
    let url: URL
    let isDirectory: Bool
    let kind: String
    let size: Int
    let modificationDate: Date?
    let tags: [FinderTag]

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

private struct RecursiveSearchNode: Identifiable, Sendable, Equatable {
    let item: BrowserItem
    let isMatch: Bool
    let children: [RecursiveSearchNode]

    var id: URL { item.url }
}

private struct RecursiveSearchRow: Identifiable {
    let node: RecursiveSearchNode
    let depth: Int

    var id: URL { node.id }
}

private enum BrowserSearchScope: String, CaseIterable, Identifiable {
    case currentFolder
    case subfolders

    var id: String { rawValue }
    var title: String {
        switch self {
        case .currentFolder: "This Folder"
        case .subfolders: "All Subfolders"
        }
    }
}

private struct RecursiveSearchScan: Sendable {
    let roots: [RecursiveSearchNode]
    let matchCount: Int
    let wasLimited: Bool
}

private struct FinderTag: Hashable, Sendable {
    let name: String
    let colorIndex: Int
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: (Date, [FinderTag])] = [:]

    static func tags(
        for url: URL,
        knownTagNames: [String]? = nil,
        maximumCacheAge: TimeInterval = 1.5
    ) -> [FinderTag] {
        let cacheKey = url.path
        let now = Date()
        cacheLock.lock()
        if maximumCacheAge > 0,
           let cached = cache[cacheKey],
           now.timeIntervalSince(cached.0) < maximumCacheAge {
            cacheLock.unlock()
            return cached.1
        }
        cacheLock.unlock()

        let tagNames = knownTagNames ?? (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
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

private let finderStandardTags: [(name: String, colorIndex: Int)] = [
    ("Red", 6), ("Orange", 7), ("Yellow", 5), ("Green", 2),
    ("Blue", 4), ("Purple", 3), ("Gray", 1)
]

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
    @State private var browserDropFocus = false
    @State private var activeDropTargetIDs: Set<String> = []
    @State private var dropFocusGeneration = UUID()
    @State private var searchText = ""
    @State private var searchScope = BrowserSearchScope.currentFolder
    @State private var recursiveSearchRoots: [RecursiveSearchNode] = []
    @State private var recursiveMatchCount = 0
    @State private var recursiveSearchWasLimited = false
    @State private var isRecursiveSearchLoading = false
    @State private var recursiveSearchError: String?
    @State private var recursiveSearchRequestID = UUID()
    @State private var expandedSearchFolders: Set<URL> = []
    @State private var recursiveSearchTask: Task<Void, Never>?
    @State private var directoryRefreshTimer: Timer?
    @State private var loadRequestID = UUID()
    @State private var loadInFlightPath: String?
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
        let displayedItems = visibleItems
        let displayedURLs = displayedItems.map(\.url)
        let recursiveRows = flattenedRecursiveSearchRows
        let recursiveURLs = recursiveRows.map { $0.node.item.url }

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
                    CopyablePathLabel(path: folder.path) {
                        controller.keepOpen()
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 16, maxHeight: 16)
                    .clipped()
                }
                .frame(minWidth: 72, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)
                .clipped()

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

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .help(searchScope == .subfolders ? "Search this folder and all subfolders" : "Filter this folder")
                Picker("Search scope", selection: $searchScope) {
                    ForEach(BrowserSearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Divider()

            if isBatchRenaming {
                BatchRenameBar(controller: controller)
                Divider()
            }

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
                } else if isRecursiveSearchActive {
                    recursiveSearchView(rows: recursiveRows, orderedURLs: recursiveURLs)
                } else if items.isEmpty && !isCreatingFolder {
                    ContentUnavailableView("This folder is empty", systemImage: "folder")
                } else {
                    if viewMode == "list" {
                        listView(items: displayedItems, orderedURLs: displayedURLs)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 14) {
                                if isCreatingFolder {
                                    BrowserNewFolderTile(controller: controller)
                                }
                                ForEach(displayedItems) { item in
                                    BrowserItemTile(
                                        item: item,
                                        orderedURLs: displayedURLs,
                                        controller: controller,
                                        onDropFocusChanged: {
                                            updateDropFocus(for: item.url.path, isTargeted: $0)
                                        }
                                    )
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
            if browserDropFocus {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(2)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isFileDropTarget) { providers in
            controller.receiveFileDrop(providers, into: folder)
        }
        .onChange(of: isFileDropTarget) { _, targeted in
            updateDropFocus(for: "browser-root", isTargeted: targeted)
        }
        .onAppear {
            migrateColumnLayoutIfNeeded()
            loadItems()
            directoryRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated {
                    loadItems(showLoading: false)
                }
            }
        }
        .onDisappear {
            directoryRefreshTimer?.invalidate()
            directoryRefreshTimer = nil
            loadRequestID = UUID()
            loadInFlightPath = nil
            recursiveSearchRequestID = UUID()
            recursiveSearchTask?.cancel()
            recursiveSearchTask = nil
            recursiveSearchRoots = []
            isRecursiveSearchLoading = false
            activeDropTargetIDs.removeAll()
            browserDropFocus = false
        }
        .onChange(of: folder.path) { _, _ in
            loadRequestID = UUID()
            items = []
            loadedFolderPath = nil
            loadError = nil
            searchText = ""
            recursiveSearchRequestID = UUID()
            recursiveSearchTask?.cancel()
            recursiveSearchTask = nil
            recursiveSearchRoots = []
            recursiveMatchCount = 0
            recursiveSearchError = nil
            expandedSearchFolders = []
            controller.updateCurrentDirectoryItems([])
            loadItems()
        }
        .onChange(of: controller.directoryRevision) { _, _ in
            loadItems()
            if isRecursiveSearchActive { scheduleRecursiveSearch() }
        }
        .onChange(of: sortKeyValue) { _, _ in updateSelectionOrder() }
        .onChange(of: sortAscending) { _, _ in updateSelectionOrder() }
        .onChange(of: searchText) { _, _ in searchInputChanged() }
        .onChange(of: searchScope) { _, _ in searchInputChanged() }
    }

    private func loadItems(showLoading: Bool = true) {
        let directory = folder
        let directoryPath = directory.standardizedFileURL.path
        if !showLoading, loadInFlightPath == directoryPath {
            return
        }
        let requestID = UUID()
        loadRequestID = requestID
        loadInFlightPath = directoryPath
        if showLoading && items.isEmpty {
            isLoading = true
            loadedFolderPath = nil
        }
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.readItems(in: directory)
            }.value

            guard requestID == loadRequestID else { return }
            loadInFlightPath = nil
            isLoading = false
            switch result {
            case let .success(loadedItems):
                loadedFolderPath = directoryPath
                if items != loadedItems {
                    items = loadedItems
                    updateSelectionOrder()
                }
                loadError = nil
            case let .failure(.message(message)):
                items = []
                loadedFolderPath = nil
                controller.updateCurrentDirectoryItems([])
                loadError = message
            }
        }
    }

    private func updateDropFocus(for id: String, isTargeted: Bool) {
        if isTargeted {
            activeDropTargetIDs.insert(id)
            dropFocusGeneration = UUID()
            browserDropFocus = true
            return
        }

        activeDropTargetIDs.remove(id)
        guard activeDropTargetIDs.isEmpty else { return }

        let generation = UUID()
        dropFocusGeneration = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard dropFocusGeneration == generation, activeDropTargetIDs.isEmpty else { return }
            browserDropFocus = false
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
            let resourceKeys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isHiddenKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .tagNamesKey
            ]
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )
            let items = urls.map { url -> BrowserItem in
                let values = try? url.resourceValues(forKeys: resourceKeys)
                let isDirectory = values?.isDirectory ?? false
                let kind = isDirectory
                    ? "Folder"
                    : (url.pathExtension.isEmpty ? "Document" : url.pathExtension.uppercased())
                return BrowserItem(
                    url: url,
                    isDirectory: isDirectory,
                    kind: kind,
                    size: values?.fileSize ?? 0,
                    modificationDate: values?.contentModificationDate,
                    tags: FinderTag.tags(
                        for: url,
                        knownTagNames: values?.tagNames ?? [],
                        maximumCacheAge: 0
                    )
                )
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

    nonisolated private static func searchRecursively(
        in root: URL,
        query: String,
        maximumMatches: Int = 500,
        maximumVisitedItems: Int = 20_000
    ) -> Result<RecursiveSearchScan, DirectoryLoadFailure> {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isHiddenKey,
            .isPackageKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .tagNamesKey
        ]
        let rootComponentCount = root.standardizedFileURL.pathComponents.count
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return .failure(.message("This folder could not be searched."))
        }

        var matchingPaths: [[URL]] = []
        var itemByURL: [URL: BrowserItem] = [:]
        var matchCount = 0
        var visitedCount = 0
        var wasLimited = false

        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            visitedCount += 1
            if visitedCount > maximumVisitedItems {
                wasLimited = true
                break
            }
            let values = try? url.resourceValues(forKeys: resourceKeys)
            if values?.isHidden == true { continue }
            let isDirectory = values?.isDirectory ?? false
            if isDirectory && values?.isPackage == true {
                enumerator.skipDescendants()
            }
            let kind = isDirectory
                ? "Folder"
                : (url.pathExtension.isEmpty ? "Document" : url.pathExtension.uppercased())
            let isMatch = url.lastPathComponent.localizedCaseInsensitiveContains(query)
                || kind.localizedCaseInsensitiveContains(query)
            guard isMatch else { continue }

            if matchCount == maximumMatches {
                wasLimited = true
                break
            }
            matchCount += 1

            let relativeComponents = Array(url.standardizedFileURL.pathComponents.dropFirst(rootComponentCount))
            guard !relativeComponents.isEmpty else { continue }
            var parentURL = root
            var componentPath: [URL] = []
            for (index, component) in relativeComponents.enumerated() {
                let componentURL = parentURL.appendingPathComponent(component)
                if itemByURL[componentURL] == nil {
                    let isLeaf = index == relativeComponents.count - 1
                    let componentValues = isLeaf ? values : (try? componentURL.resourceValues(forKeys: resourceKeys))
                    let componentIsDirectory = componentValues?.isDirectory ?? !isLeaf
                    let componentKind = componentIsDirectory
                        ? "Folder"
                        : (componentURL.pathExtension.isEmpty ? "Document" : componentURL.pathExtension.uppercased())
                    itemByURL[componentURL] = BrowserItem(
                        url: componentURL,
                        isDirectory: componentIsDirectory,
                        kind: componentKind,
                        size: componentValues?.fileSize ?? 0,
                        modificationDate: componentValues?.contentModificationDate,
                        tags: FinderTag.tags(
                            for: componentURL,
                            knownTagNames: componentValues?.tagNames ?? []
                        )
                    )
                }
                componentPath.append(componentURL)
                parentURL = componentURL
            }
            matchingPaths.append(componentPath)
        }

        let pathTree = SearchPathTreeBuilder.build(matchingPaths: matchingPaths) {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        func makeNode(_ treeNode: SearchPathTreeNode<URL>) -> RecursiveSearchNode? {
            guard let item = itemByURL[treeNode.value] else { return nil }
            return RecursiveSearchNode(
                item: item,
                isMatch: treeNode.isMatch,
                children: treeNode.children.compactMap(makeNode)
            )
        }
        let frozenRoots = pathTree.compactMap(makeNode)
        return .success(RecursiveSearchScan(roots: frozenRoots, matchCount: matchCount, wasLimited: wasLimited))
    }

    private func listView(items displayedItems: [BrowserItem], orderedURLs displayedURLs: [URL]) -> some View {
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
                            ForEach(displayedItems) { item in
                                BrowserListRow(
                                    item: item,
                                    orderedURLs: displayedURLs,
                                    nameWidth: nameWidth,
                                    kindWidth: kindWidth,
                                    sizeWidth: sizeWidth,
                                    dateWidth: dateWidth,
                                    controller: controller,
                                    onDropFocusChanged: {
                                        updateDropFocus(for: item.url.path, isTargeted: $0)
                                    }
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

    @ViewBuilder
    private func recursiveSearchView(rows: [RecursiveSearchRow], orderedURLs: [URL]) -> some View {
        if isRecursiveSearchLoading && recursiveSearchRoots.isEmpty {
            ProgressView("Searching subfolders…")
                .controlSize(.small)
        } else if let recursiveSearchError {
            ContentUnavailableView(
                "Search failed",
                systemImage: "exclamationmark.triangle",
                description: Text(recursiveSearchError)
            )
        } else if rows.isEmpty {
            ContentUnavailableView.search(text: normalizedSearchQuery)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("\(recursiveMatchCount) result\(recursiveMatchCount == 1 ? "" : "s")")
                    if recursiveSearchWasLimited {
                        Label("Results limited", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    if isRecursiveSearchLoading {
                        ProgressView().controlSize(.mini)
                    }
                    Button("Expand All") { expandedSearchFolders = recursiveFolderURLs }
                        .buttonStyle(.plain)
                    Button("Collapse All") { expandedSearchFolders = [] }
                        .buttonStyle(.plain)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(height: 30)
                Divider()

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rows) { row in
                            RecursiveSearchResultRow(
                                row: row,
                                orderedURLs: orderedURLs,
                                isExpanded: expandedSearchFolders.contains(row.node.id),
                                controller: controller,
                                onDropFocusChanged: {
                                    updateDropFocus(for: row.node.id.path, isTargeted: $0)
                                },
                                toggleExpansion: {
                                    if expandedSearchFolders.contains(row.node.id) {
                                        expandedSearchFolders.remove(row.node.id)
                                    } else {
                                        expandedSearchFolders.insert(row.node.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private var normalizedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isRecursiveSearchActive: Bool {
        searchScope == .subfolders && !normalizedSearchQuery.isEmpty
    }

    private func searchInputChanged() {
        if isRecursiveSearchActive {
            scheduleRecursiveSearch()
        } else {
            recursiveSearchTask?.cancel()
            recursiveSearchTask = nil
            recursiveSearchRequestID = UUID()
            recursiveSearchRoots = []
            recursiveMatchCount = 0
            recursiveSearchError = nil
            recursiveSearchWasLimited = false
            isRecursiveSearchLoading = false
            expandedSearchFolders = []
            updateSelectionOrder()
        }
    }

    private func scheduleRecursiveSearch() {
        recursiveSearchTask?.cancel()
        let query = normalizedSearchQuery
        guard !query.isEmpty, searchScope == .subfolders else { return }
        let requestID = UUID()
        recursiveSearchRequestID = requestID
        isRecursiveSearchLoading = true
        recursiveSearchError = nil
        recursiveSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, requestID == recursiveSearchRequestID else { return }
            let scanTask = Task.detached(priority: .userInitiated) {
                Self.searchRecursively(in: folder, query: query)
            }
            let result = await withTaskCancellationHandler {
                await scanTask.value
            } onCancel: {
                scanTask.cancel()
            }
            guard !Task.isCancelled, requestID == recursiveSearchRequestID else { return }
            isRecursiveSearchLoading = false
            switch result {
            case let .success(scan):
                recursiveSearchRoots = scan.roots
                recursiveMatchCount = scan.matchCount
                recursiveSearchWasLimited = scan.wasLimited
                recursiveSearchError = nil
                expandedSearchFolders = Self.folderURLs(in: scan.roots)
                updateSelectionOrder()
            case let .failure(.message(message)):
                recursiveSearchRoots = []
                recursiveMatchCount = 0
                recursiveSearchWasLimited = false
                recursiveSearchError = message
                controller.updateCurrentDirectoryItems([])
            }
        }
    }

    private var flattenedRecursiveSearchRows: [RecursiveSearchRow] {
        var rows: [RecursiveSearchRow] = []
        func append(_ nodes: [RecursiveSearchNode], depth: Int) {
            for node in nodes {
                rows.append(RecursiveSearchRow(node: node, depth: depth))
                if expandedSearchFolders.contains(node.id) {
                    append(node.children, depth: depth + 1)
                }
            }
        }
        append(recursiveSearchRoots, depth: 0)
        return rows
    }

    private var recursiveFolderURLs: Set<URL> {
        Self.folderURLs(in: recursiveSearchRoots)
    }

    nonisolated private static func folderURLs(in nodes: [RecursiveSearchNode]) -> Set<URL> {
        var urls: Set<URL> = []
        func collect(_ nodes: [RecursiveSearchNode]) {
            for node in nodes where node.item.isDirectory && !node.children.isEmpty {
                urls.insert(node.id)
                collect(node.children)
            }
        }
        collect(nodes)
        return urls
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
        case .newFolder, .rename, .batchRename, .none: nil
        }
    }
    private var isBatchRenaming: Bool {
        if case .batchRename = controller.prompt { return true }
        return false
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
        if isRecursiveSearchActive {
            controller.updateCurrentDirectoryItems(flattenedRecursiveSearchRows.map { $0.node.item.url })
        } else {
            controller.updateCurrentDirectoryItems(visibleItems.map(\.url))
        }
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

private enum BatchRenameFocusedField: Hashable {
    case find
    case replacement
    case addedText
    case formatName
    case startIndex
}

private struct BatchRenameBar: View {
    @ObservedObject var controller: DockController
    @FocusState private var focusedField: BatchRenameFocusedField?

    private var itemCount: Int {
        if case let .batchRename(urls) = controller.prompt { return urls.count }
        return 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Rename \(itemCount) Finder Items:")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: controller.cancelPrompt) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Cancel batch rename (Esc)")
            }

            HStack(spacing: 8) {
                Picker("Rename mode", selection: $controller.batchRenameMode) {
                    ForEach(BatchRenameMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 132)

                batchControls
            }

            HStack(spacing: 8) {
                if let error = controller.batchRenameError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else {
                    Text("Example:")
                        .foregroundStyle(.secondary)
                    Text(controller.batchRenameExample)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Button("Cancel", action: controller.cancelPrompt)
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: controller.confirmPrompt)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!controller.canConfirmBatchRename)
            }
            .font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.07))
        .onAppear { focusPrimaryField() }
        .onChange(of: controller.batchRenameMode) { _, _ in
            controller.clearBatchRenameError()
            focusPrimaryField()
        }
        .onChange(of: controller.batchRenameFindText) { _, _ in controller.clearBatchRenameError() }
        .onChange(of: controller.batchRenameReplacementText) { _, _ in controller.clearBatchRenameError() }
        .onChange(of: controller.batchRenameAddedText) { _, _ in controller.clearBatchRenameError() }
        .onChange(of: controller.batchRenameFormatName) { _, _ in controller.clearBatchRenameError() }
        .onChange(of: controller.batchRenameFormat) { _, _ in controller.clearBatchRenameError() }
        .onChange(of: controller.batchRenamePosition) { _, _ in controller.clearBatchRenameError() }
        .onChange(of: controller.batchRenameStartIndex) { _, _ in controller.clearBatchRenameError() }
    }

    @ViewBuilder
    private var batchControls: some View {
        switch controller.batchRenameMode {
        case .replaceText:
            TextField("Find", text: $controller.batchRenameFindText)
                .focused($focusedField, equals: .find)
            TextField("Replace with", text: $controller.batchRenameReplacementText)
                .focused($focusedField, equals: .replacement)

        case .addText:
            TextField("Text to add", text: $controller.batchRenameAddedText)
                .focused($focusedField, equals: .addedText)
            Picker("Position", selection: $controller.batchRenamePosition) {
                ForEach(BatchRenamePosition.allCases) { position in
                    Text(position.rawValue).tag(position)
                }
            }
            .labelsHidden()
            .frame(width: 112)

        case .format:
            TextField("Custom Format", text: $controller.batchRenameFormatName)
                .focused($focusedField, equals: .formatName)
                .frame(minWidth: 92)
            Picker("Format", selection: $controller.batchRenameFormat) {
                ForEach(BatchRenameFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .labelsHidden()
            .frame(width: 132)
            Picker("Position", selection: $controller.batchRenamePosition) {
                ForEach(BatchRenamePosition.allCases) { position in
                    Text(position.rawValue).tag(position)
                }
            }
            .labelsHidden()
            .frame(width: 112)
            if controller.batchRenameFormat != .nameAndDate {
                TextField("Start", value: $controller.batchRenameStartIndex, format: .number)
                    .focused($focusedField, equals: .startIndex)
                    .frame(width: 54)
                    .help("Start numbers at")
            }
        }
    }

    private func focusPrimaryField() {
        DispatchQueue.main.async {
            switch controller.batchRenameMode {
            case .replaceText: focusedField = .find
            case .addText: focusedField = .addedText
            case .format: focusedField = .formatName
            }
        }
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
        case .newFolder, .rename, .batchRename: return ""
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
    @ObservedObject var controller: DockController
    let onDropFocusChanged: (Bool) -> Void
    @State private var isFileDropTarget = false

    private var isSelected: Bool { controller.selectedItemURLs.contains(item.url) }
    private var isRenaming: Bool {
        if case let .rename(url) = controller.prompt { return url == item.url }
        return false
    }

    var body: some View {
        FinderDragSource(
            urls: urlsForDrag,
            primaryAction: { controller.selectItem(item.url, orderedURLs: orderedURLs) },
            doubleAction: { controller.openInBrowser(item.url) },
            dragEnded: controller.externalFileDragEnded,
            contextMenu: { makeFileItemContextMenu(item: item, controller: controller) },
            isEnabled: !isRenaming
        ) {
            VStack(spacing: 7) {
                if item.isDirectory {
                    FileIcon(url: item.url, size: 42, tint: item.tags.first?.color)
                } else {
                    FilePreview(url: item.url, size: 42, modificationDate: item.modificationDate)
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
        .onDrop(of: [.fileURL], isTargeted: $isFileDropTarget) { providers in
            guard item.isDirectory else { return false }
            return controller.receiveFileDrop(providers, into: item.url)
        }
        .onChange(of: isFileDropTarget) { _, targeted in
            onDropFocusChanged(targeted)
        }
        .onDisappear {
            if isFileDropTarget {
                onDropFocusChanged(false)
            }
        }
    }

    private func urlsForDrag() -> [URL] {
        if !controller.selectedItemURLs.contains(item.url) {
            controller.selectOnly(item.url)
        }
        return controller.selectedItemsOr(item.url)
    }
}

private struct BrowserListRow: View {
    let item: BrowserItem
    let orderedURLs: [URL]
    let nameWidth: CGFloat
    let kindWidth: CGFloat
    let sizeWidth: CGFloat
    let dateWidth: CGFloat
    @ObservedObject var controller: DockController
    let onDropFocusChanged: (Bool) -> Void
    @State private var isFileDropTarget = false

    private var isSelected: Bool { controller.selectedItemURLs.contains(item.url) }
    private var isRenaming: Bool {
        if case let .rename(url) = controller.prompt { return url == item.url }
        return false
    }
    private var kind: String { item.kind }
    private var size: String {
        guard !item.isDirectory else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)
    }
    private var modified: String {
        guard let date = item.modificationDate else { return "—" }
        return compactBrowserDateFormatter.string(from: date)
    }

    var body: some View {
        FinderDragSource(
            urls: urlsForDrag,
            primaryAction: { controller.selectItem(item.url, orderedURLs: orderedURLs) },
            doubleAction: { controller.openInBrowser(item.url) },
            dragEnded: controller.externalFileDragEnded,
            contextMenu: { makeFileItemContextMenu(item: item, controller: controller) },
            isEnabled: !isRenaming
        ) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    if item.isDirectory {
                        FileIcon(url: item.url, size: 22, tint: item.tags.first?.color)
                    } else {
                        FilePreview(url: item.url, size: 22, modificationDate: item.modificationDate)
                    }
                    if isRenaming {
                        InlineNameField(controller: controller, centered: false)
                    } else {
                        Text(item.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    FinderTagDots(tags: item.tags)
                    Spacer(minLength: 26)
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
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            if item.isDirectory && isFileDropTarget {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .overlay(alignment: .leading) {
            if item.isDirectory {
                Button {
                    controller.openInBrowser(item.url)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Browse this folder")
                .offset(x: 20 + nameWidth - 24)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isFileDropTarget) { providers in
            guard item.isDirectory else { return false }
            return controller.receiveFileDrop(providers, into: item.url)
        }
        .onChange(of: isFileDropTarget) { _, targeted in
            onDropFocusChanged(targeted)
        }
        .onDisappear {
            if isFileDropTarget {
                onDropFocusChanged(false)
            }
        }
    }

    private func urlsForDrag() -> [URL] {
        if !controller.selectedItemURLs.contains(item.url) {
            controller.selectOnly(item.url)
        }
        return controller.selectedItemsOr(item.url)
    }
}

private struct RecursiveSearchResultRow: View {
    let row: RecursiveSearchRow
    let orderedURLs: [URL]
    let isExpanded: Bool
    @ObservedObject var controller: DockController
    let onDropFocusChanged: (Bool) -> Void
    let toggleExpansion: () -> Void
    @State private var isFileDropTarget = false

    private var item: BrowserItem { row.node.item }
    private var isSelected: Bool { controller.selectedItemURLs.contains(item.url) }

    var body: some View {
        FinderDragSource(
            urls: urlsForDrag,
            primaryAction: { controller.selectItem(item.url, orderedURLs: orderedURLs) },
            doubleAction: { controller.openInBrowser(item.url) },
            dragEnded: controller.externalFileDragEnded,
            contextMenu: { makeFileItemContextMenu(item: item, controller: controller) }
        ) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 18, height: 26)

                if item.isDirectory {
                    FileIcon(url: item.url, size: 22, tint: item.tags.first?.color)
                } else {
                    FilePreview(url: item.url, size: 22, modificationDate: item.modificationDate)
                }

                Text(item.name)
                    .font(.system(size: 12, weight: row.node.isMatch ? .semibold : .regular))
                    .lineLimit(1)
                FinderTagDots(tags: item.tags)
                Spacer(minLength: 8)
                if row.node.isMatch {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .help("Matches search")
                }
                Text(item.isDirectory ? "Folder" : item.kind)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)
            }
            .padding(.leading, CGFloat(row.depth) * 20)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.20) : (row.node.isMatch ? Color.accentColor.opacity(0.06) : .clear))
        }
        .overlay {
            if item.isDirectory && isFileDropTarget {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .overlay(alignment: .leading) {
            if item.isDirectory && !row.node.children.isEmpty {
                Button(action: toggleExpansion) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 18, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 10 + CGFloat(row.depth) * 20)
                .help(isExpanded ? "Collapse folder" : "Expand folder")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isFileDropTarget) { providers in
            guard item.isDirectory else { return false }
            return controller.receiveFileDrop(providers, into: item.url)
        }
        .onChange(of: isFileDropTarget) { _, targeted in
            onDropFocusChanged(targeted)
        }
        .onDisappear {
            if isFileDropTarget {
                onDropFocusChanged(false)
            }
        }
    }

    private func urlsForDrag() -> [URL] {
        if !controller.selectedItemURLs.contains(item.url) {
            controller.selectOnly(item.url)
        }
        return controller.selectedItemsOr(item.url)
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(
        title: String,
        symbolName: String? = nil,
        isEnabled: Bool = true,
        handler: @escaping () -> Void
    ) {
        self.handler = handler
        super.init(title: title, action: #selector(runHandler), keyEquivalent: "")
        target = self
        self.isEnabled = isEnabled
        if let symbolName {
            image = menuSymbol(named: symbolName, description: title)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runHandler() {
        handler()
    }
}

private final class TagPaletteButton: NSButton {
    weak var trackingMenu: NSMenu?
    private let handler: () -> Void

    init(tag: FinderTag, menu: NSMenu, handler: @escaping () -> Void) {
        self.handler = handler
        trackingMenu = menu
        super.init(frame: .zero)
        let dot = tag.menuImage
        dot.size = NSSize(width: 14, height: 14)
        image = dot
        imageScaling = .scaleNone
        isBordered = false
        setButtonType(.momentaryChange)
        toolTip = tag.name
        target = self
        action = #selector(runHandler)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 20).isActive = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runHandler() {
        trackingMenu?.cancelTracking()
        handler()
    }
}

private func menuSymbol(named name: String, description: String) -> NSImage? {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: description) else { return nil }
    image.isTemplate = true
    image.size = NSSize(width: 12, height: 12)
    return image
}

@MainActor
private func makeFileItemContextMenu(item: BrowserItem, controller: DockController) -> NSMenu {
    if !controller.selectedItemURLs.contains(item.url) {
        controller.selectOnly(item.url)
    }

    let targets = controller.selectedItemsOr(item.url)
    let targetCount = targets.count
    let actionSuffix = targetCount == 1 ? "" : " (\(targetCount) Items)"
    let menu = NSMenu()
    menu.autoenablesItems = false

    func addAction(
        _ title: String,
        symbol: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        menu.addItem(ClosureMenuItem(
            title: title,
            symbolName: symbol,
            isEnabled: isEnabled,
            handler: action
        ))
    }

    if item.isDirectory {
        addAction("Browse Here", symbol: "folder") { controller.openInBrowser(item.url) }
    }
    addAction("Open\(actionSuffix)", symbol: "arrow.up.forward.app") { controller.openItems(targets) }
    addAction("Quick Look", symbol: "eye") { controller.quickLook(targets) }
    menu.addItem(.separator())
    addAction("Move to Trash\(actionSuffix)", symbol: "trash") { controller.moveToTrash(targets) }
    menu.addItem(.separator())
    addAction("Get Info", symbol: "info.circle", isEnabled: targetCount == 1) {
        controller.showInfo(for: item.url)
    }
    addAction(
        targetCount == 1 ? "Rename…" : "Rename \(targetCount) Items…",
        symbol: "pencil"
    ) { controller.renameItems(targets) }
    addAction("Duplicate\(actionSuffix)", symbol: "plus.square.on.square") { controller.duplicate(targets) }
    addAction("Copy\(actionSuffix)", symbol: "doc.on.doc") { controller.copyToPasteboard(targets) }
    addAction("Cut\(actionSuffix)", symbol: "scissors") { controller.cutItems(targets) }
    addAction("Copy Path\(actionSuffix)", symbol: "link") { controller.copyPaths(targets) }
    menu.addItem(.separator())
    menu.addItem(makeTagPaletteMenuItem(menu: menu, targets: targets, controller: controller))
    menu.addItem(makeTagsSubmenuItem(targets: targets, controller: controller))
    menu.addItem(.separator())
    addAction("Show in Finder", symbol: "scope") {
        NSWorkspace.shared.activateFileViewerSelecting(targets)
    }
    return menu
}

@MainActor
private func makeTagPaletteMenuItem(
    menu: NSMenu,
    targets: [URL],
    controller: DockController
) -> NSMenuItem {
    let item = NSMenuItem()
    item.isEnabled = true
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false

    for tag in finderStandardTags {
        let finderTag = FinderTag(name: tag.name, colorIndex: tag.colorIndex)
        stack.addArrangedSubview(TagPaletteButton(tag: finderTag, menu: menu) {
            controller.addFinderTag(name: tag.name, colorIndex: tag.colorIndex, to: targets)
        })
    }

    container.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 34),
        stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
    ])
    item.view = container
    return item
}

@MainActor
private func makeTagsSubmenuItem(targets: [URL], controller: DockController) -> NSMenuItem {
    let item = NSMenuItem(title: "Tags…", action: nil, keyEquivalent: "")
    item.image = menuSymbol(named: "tag", description: "Tags")
    let submenu = NSMenu(title: "Tags")
    submenu.autoenablesItems = false

    for tag in finderStandardTags {
        let menuItem = ClosureMenuItem(title: tag.name) {
            controller.addFinderTag(name: tag.name, colorIndex: tag.colorIndex, to: targets)
        }
        menuItem.image = FinderTag(name: tag.name, colorIndex: tag.colorIndex).menuImage
        submenu.addItem(menuItem)
    }

    let existingTagNames = Array(Set(targets.flatMap { FinderTag.tags(for: $0).map(\.name) })).sorted()
    if !existingTagNames.isEmpty {
        submenu.addItem(.separator())
        let removeItem = NSMenuItem(title: "Remove Tag", action: nil, keyEquivalent: "")
        removeItem.image = menuSymbol(named: "tag.slash", description: "Remove Tag")
        let removeMenu = NSMenu(title: "Remove Tag")
        removeMenu.autoenablesItems = false
        for name in existingTagNames {
            removeMenu.addItem(ClosureMenuItem(title: name, symbolName: "tag.slash") {
                controller.removeFinderTag(named: name, from: targets)
            })
        }
        removeItem.submenu = removeMenu
        submenu.addItem(removeItem)
        submenu.addItem(ClosureMenuItem(title: "Clear Tags", symbolName: "xmark.circle") {
            controller.clearFinderTags(from: targets)
        })
    }

    item.submenu = submenu
    return item
}

struct FileIcon: View {
    let url: URL
    let size: CGFloat
    var tint: Color? = nil

    var body: some View {
        let icon = FileIconCache.icon(for: url)

        Group {
            if let tint {
                Image(nsImage: icon)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(tint)
            } else {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            }
        }
        .frame(width: size, height: size)
    }
}

@MainActor
private enum FileIconCache {
    static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    static func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let image = images.object(forKey: key) {
            return image
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        images.setObject(image, forKey: key)
        return image
    }
}
