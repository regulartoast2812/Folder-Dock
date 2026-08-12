import AppKit
import Foundation

struct SavedFolder: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: String
    fileprivate var directoryHint: Bool?

    init(url: URL) {
        id = UUID()
        name = url.lastPathComponent
        path = url.path
        var isDirectory: ObjCBool = false
        directoryHint = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            ? isDirectory.boolValue
            : nil
    }

    var url: URL { URL(fileURLWithPath: path) }

    var isDirectory: Bool {
        if let directoryHint { return directoryHint }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

struct FolderSet: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var folders: [SavedFolder]

    init(name: String, folders: [SavedFolder] = []) {
        id = UUID()
        self.name = name
        self.folders = folders
    }
}

@MainActor
final class FolderStore: ObservableObject {
    @Published private(set) var folderSets: [FolderSet]
    @Published private(set) var selectedSetID: UUID

    private let setsDefaultsKey = "folderSets"
    private let selectedSetDefaultsKey = "selectedFolderSetID"
    private let legacyFoldersDefaultsKey = "savedFolders"

    var selectedSet: FolderSet? {
        folderSets.first { $0.id == selectedSetID }
    }

    var folders: [SavedFolder] {
        selectedSet?.folders ?? []
    }

    init() {
        var loadedSets: [FolderSet]
        if let data = UserDefaults.standard.data(forKey: setsDefaultsKey),
           let savedSets = try? JSONDecoder().decode([FolderSet].self, from: data),
           !savedSets.isEmpty {
            loadedSets = savedSets.map(Self.removingMissingFolders)
        } else {
            let legacyFolders: [SavedFolder]
            if let data = UserDefaults.standard.data(forKey: legacyFoldersDefaultsKey),
               let decoded = try? JSONDecoder().decode([SavedFolder].self, from: data) {
                legacyFolders = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
            } else {
                legacyFolders = []
            }
            loadedSets = [FolderSet(name: "General", folders: legacyFolders)]
        }

        if loadedSets.isEmpty {
            loadedSets = [FolderSet(name: "General")]
        }
        folderSets = loadedSets
        if let idString = UserDefaults.standard.string(forKey: selectedSetDefaultsKey),
           let savedID = UUID(uuidString: idString),
           loadedSets.contains(where: { $0.id == savedID }) {
            selectedSetID = savedID
        } else if let firstSet = loadedSets.first {
            selectedSetID = firstSet.id
        } else {
            let fallback = FolderSet(name: "General")
            folderSets = [fallback]
            selectedSetID = fallback.id
        }
        persist()
    }

    func selectSet(_ set: FolderSet) {
        guard selectedSetID != set.id,
              folderSets.contains(where: { $0.id == set.id }) else { return }
        selectedSetID = set.id
        persistSelection()
    }

    func createSet(named rawName: String) {
        let name = normalizedName(rawName)
        guard !name.isEmpty, !folderSets.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        let set = FolderSet(name: name)
        folderSets.append(set)
        selectedSetID = set.id
        persist()
    }

    func renameSet(_ set: FolderSet, to rawName: String) {
        let name = normalizedName(rawName)
        guard !name.isEmpty,
              !folderSets.contains(where: { $0.id != set.id && $0.name.caseInsensitiveCompare(name) == .orderedSame }),
              let index = folderSets.firstIndex(where: { $0.id == set.id }) else { return }
        folderSets[index].name = name
        persist()
    }

    func deleteSet(_ set: FolderSet) {
        guard folderSets.count > 1 else { return }
        folderSets.removeAll { $0.id == set.id }
        if selectedSetID == set.id, let firstSet = folderSets.first {
            selectedSetID = firstSet.id
        }
        persist()
    }

    func add(url: URL) {
        add(url: url, toSetID: selectedSetID)
    }

    func add(url: URL, toSetID setID: UUID) {
        let url = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let index = folderSets.firstIndex(where: { $0.id == setID }),
              !folderSets[index].folders.contains(where: { $0.path == url.path }) else { return }
        folderSets[index].folders.append(SavedFolder(url: url))
        persist()
    }

    func remove(_ folder: SavedFolder) {
        remove([folder])
    }

    func remove(_ folders: [SavedFolder]) {
        let ids = Set(folders.map(\.id))
        guard !ids.isEmpty,
              let index = folderSets.firstIndex(where: { $0.id == selectedSetID }) else { return }
        folderSets[index].folders.removeAll { ids.contains($0.id) }
        persist()
    }

    func open(_ folders: [SavedFolder]) {
        folders.forEach { NSWorkspace.shared.open($0.url) }
    }

    func showInFinder(_ folders: [SavedFolder]) {
        guard !folders.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(folders.map(\.url))
    }

    func moveSet(_ movingID: UUID, before targetID: UUID) {
        guard movingID != targetID,
              let source = folderSets.firstIndex(where: { $0.id == movingID }),
              let target = folderSets.firstIndex(where: { $0.id == targetID }) else { return }
        let set = folderSets.remove(at: source)
        let destination = source < target ? target - 1 : target
        folderSets.insert(set, at: destination)
        persist()
    }

    func moveFolder(_ movingID: UUID, before targetID: UUID) {
        moveFolders([movingID], before: targetID)
    }

    func moveFolders(_ movingIDs: [UUID], before targetID: UUID) {
        let movingSet = Set(movingIDs)
        guard !movingSet.isEmpty,
              !movingSet.contains(targetID),
              let setIndex = folderSets.firstIndex(where: { $0.id == selectedSetID }) else { return }

        let movingItems = folderSets[setIndex].folders.filter { movingSet.contains($0.id) }
        guard !movingItems.isEmpty else { return }
        folderSets[setIndex].folders.removeAll { movingSet.contains($0.id) }
        let destination = folderSets[setIndex].folders.firstIndex(where: { $0.id == targetID })
            ?? folderSets[setIndex].folders.endIndex
        folderSets[setIndex].folders.insert(contentsOf: movingItems, at: destination)
        persist()
    }

    func open(_ folder: SavedFolder) {
        open([folder])
    }

    func showInFinder(_ folder: SavedFolder) {
        showInFinder([folder])
    }

    private static func removingMissingFolders(from set: FolderSet) -> FolderSet {
        var set = set
        set.folders = set.folders.compactMap { savedItem -> SavedFolder? in
            var savedItem = savedItem
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: savedItem.path, isDirectory: &isDirectory) else {
                return nil
            }
            savedItem.directoryHint = isDirectory.boolValue
            return savedItem
        }
        return set
    }

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(folderSets) else { return }
        UserDefaults.standard.set(data, forKey: setsDefaultsKey)
        persistSelection()
    }

    private func persistSelection() {
        UserDefaults.standard.set(selectedSetID.uuidString, forKey: selectedSetDefaultsKey)
    }
}
