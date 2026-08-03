import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DockView: View {
    @ObservedObject var store: FolderStore
    @ObservedObject var controller: DockController
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            shelf

            if let currentFolder = controller.currentFolder {
                FolderBrowser(folder: currentFolder, controller: controller)
            } else if controller.isManagingSets {
                FolderSetManager(store: store, controller: controller)
            }
        }
    }

    private var shelf: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(store.folderSets) { set in
                        Button {
                            controller.selectSet(set)
                        } label: {
                            if set.id == store.selectedSetID {
                                Label(set.name, systemImage: "checkmark")
                            } else {
                                Text(set.name)
                            }
                        }
                }
                Divider()
                Button("New Folder Set…") {
                    controller.showSetManager()
                }
                Button("Manage Folder Sets…") {
                    controller.showSetManager()
                }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 11))
                        Text(store.selectedSet?.name ?? "General")
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .frame(height: 25)
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .help("Switch or manage folder sets")

                Button {
                    controller.switchSet(forward: false)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: 25)
                }
                .buttonStyle(.plain)
                .disabled(store.folderSets.count < 2)
                .opacity(store.folderSets.count < 2 ? 0.3 : 1)
                .help("Previous folder set (⌥⌘←)")

                Button {
                    controller.switchSet(forward: true)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: 25)
                }
                .buttonStyle(.plain)
                .disabled(store.folderSets.count < 2)
                .opacity(store.folderSets.count < 2 ? 0.3 : 1)
                .help("Next folder set (⌥⌘→)")

                Spacer()

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
            .padding(.horizontal, 12)
            .frame(height: 29)

            Divider()

            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if store.folders.isEmpty {
                            emptyState
                        } else {
                            ForEach(store.folders) { folder in
                                FolderTile(folder: folder, store: store, controller: controller)
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
        .frame(width: 460, height: 94)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor.opacity(0.9) : Color.white.opacity(0.16), lineWidth: isTargeted ? 2 : 1)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: acceptDrop(providers:))
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

private struct FolderTile: View {
    let folder: SavedFolder
    @ObservedObject var store: FolderStore
    @ObservedObject var controller: DockController

    var body: some View {
        PointerButton(
            primaryAction: { controller.browse(folder) },
            middleAction: { controller.openInNewFinderWindow(folder) }
        ) {
            VStack(spacing: 4) {
                FileIcon(url: folder.url, size: 29)
                Text(folder.name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 58)
            }
            .padding(.horizontal, 3)
            .frame(width: 66, height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .contextMenu {
            Button("Browse Here") { controller.browse(folder) }
            Button("Open in Finder") { store.open(folder) }
            Button("Open in New Finder Window") { controller.openInNewFinderWindow(folder) }
            Button("Show in Finder") { store.showInFinder(folder) }
            Divider()
            Button("Remove from Dock", role: .destructive) { store.remove(folder) }
        }
        .help("Click to browse. Middle-click to open a new Finder window.")
    }
}

private struct BrowserItem: Identifiable, Sendable {
    let url: URL
    let isDirectory: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

private enum DirectoryLoadFailure: Error, Sendable {
    case message(String)
}

private struct FolderBrowser: View {
    let folder: URL
    @ObservedObject var controller: DockController
    @State private var items: [BrowserItem] = []
    @State private var loadError: String?
    @State private var isLoading = false

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

                FileIcon(url: folder, size: 21)

                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(folder.path)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

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

            Group {
                if isLoading {
                    ProgressView("Loading \(folder.lastPathComponent)…")
                        .controlSize(.small)
                } else if let loadError {
                    ContentUnavailableView("Couldn't open this folder", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if items.isEmpty {
                    ContentUnavailableView("This folder is empty", systemImage: "folder")
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(items) { item in
                                BrowserItemTile(item: item, controller: controller)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 430)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .onAppear(perform: loadItems)
        .onChange(of: folder.path) { _, _ in loadItems() }
        .onChange(of: controller.directoryRevision) { _, _ in loadItems() }
    }

    private func loadItems() {
        let directory = folder
        isLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.readItems(in: directory)
            }.value

            guard directory == folder else { return }
            isLoading = false
            switch result {
            case let .success(loadedItems):
                items = loadedItems
                loadError = nil
            case let .failure(.message(message)):
                items = []
                loadError = message
            }
        }
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
}

private struct BrowserItemTile: View {
    let item: BrowserItem
    @ObservedObject var controller: DockController

    private var isSelected: Bool { controller.selectedItemURL == item.url }

    var body: some View {
        VStack(spacing: 7) {
            if item.isDirectory {
                FileIcon(url: item.url, size: 42)
            } else {
                FilePreview(url: item.url, size: 42)
            }
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(isSelected ? Color.accentColor.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(count: 2) {
            controller.openInBrowser(item.url)
        }
        .onTapGesture {
            controller.selectItem(item.url)
        }
        .contextMenu {
            if item.isDirectory {
                Button("Browse Here") { controller.openInBrowser(item.url) }
            }
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Quick Look") {
                controller.selectItem(item.url)
                controller.showQuickLook()
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
        .help(item.url.path)
    }
}

struct FileIcon: View {
    let url: URL
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
