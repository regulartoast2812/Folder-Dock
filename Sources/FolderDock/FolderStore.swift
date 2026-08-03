import AppKit
import Foundation

struct SavedFolder: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: String

    init(url: URL) {
        id = UUID()
        name = url.lastPathComponent
        path = url.path
    }

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
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
        selectedSetID = set.id
        persist()
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
        let url = url.standardizedFileURL
        guard url.hasDirectoryPath,
              let index = folderSets.firstIndex(where: { $0.id == selectedSetID }),
              !folderSets[index].folders.contains(where: { $0.path == url.path }) else { return }
        folderSets[index].folders.append(SavedFolder(url: url))
        persist()
    }

    func remove(_ folder: SavedFolder) {
        guard let index = folderSets.firstIndex(where: { $0.id == selectedSetID }) else { return }
        folderSets[index].folders.removeAll { $0.id == folder.id }
        persist()
    }

    func open(_ folder: SavedFolder) {
        NSWorkspace.shared.open(folder.url)
    }

    func showInFinder(_ folder: SavedFolder) {
        NSWorkspace.shared.activateFileViewerSelecting([folder.url])
    }

    private static func removingMissingFolders(from set: FolderSet) -> FolderSet {
        var set = set
        set.folders.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        return set
    }

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(folderSets) else { return }
        UserDefaults.standard.set(data, forKey: setsDefaultsKey)
        UserDefaults.standard.set(selectedSetID.uuidString, forKey: selectedSetDefaultsKey)
    }
}
