import Foundation

public struct RecursiveFileSearchResult: Sendable, Equatable {
    public let matchingPaths: [[URL]]
    public let matchCount: Int
    public let wasLimited: Bool

    public init(matchingPaths: [[URL]], matchCount: Int, wasLimited: Bool) {
        self.matchingPaths = matchingPaths
        self.matchCount = matchCount
        self.wasLimited = wasLimited
    }
}

public enum RecursiveFileSearchError: Error, Sendable {
    case unreadableRoot
}

public enum RecursiveFileSearcher {
    public static func search(
        in root: URL,
        query: String,
        maximumMatches: Int = 500,
        maximumVisitedItems: Int = 20_000
    ) throws -> RecursiveFileSearchResult {
        let normalizedRoot = root.standardizedFileURL
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return RecursiveFileSearchResult(matchingPaths: [], matchCount: 0, wasLimited: false)
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isHiddenKey,
            .isPackageKey,
            .isSymbolicLinkKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: normalizedRoot,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            throw RecursiveFileSearchError.unreadableRoot
        }

        var matchingPaths: [[URL]] = []
        var matchCount = 0
        var visitedCount = 0
        var wasLimited = false

        while let rawURL = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            visitedCount += 1
            if visitedCount > maximumVisitedItems {
                wasLimited = true
                break
            }

            let url = rawURL.standardizedFileURL
            let values = try? url.resourceValues(forKeys: resourceKeys)
            if values?.isHidden == true { continue }
            let isDirectory = values?.isDirectory ?? false
            if isDirectory && (values?.isPackage == true || values?.isSymbolicLink == true) {
                enumerator.skipDescendants()
            }
            let kind = isDirectory
                ? "Folder"
                : (url.pathExtension.isEmpty ? "Document" : url.pathExtension.uppercased())
            guard url.lastPathComponent.localizedCaseInsensitiveContains(normalizedQuery)
                    || kind.localizedCaseInsensitiveContains(normalizedQuery) else { continue }

            if matchCount == maximumMatches {
                wasLimited = true
                break
            }
            guard let path = pathFromRoot(normalizedRoot, to: url) else { continue }
            matchingPaths.append(path)
            matchCount += 1
        }

        return RecursiveFileSearchResult(
            matchingPaths: matchingPaths,
            matchCount: matchCount,
            wasLimited: wasLimited
        )
    }

    private static func pathFromRoot(_ root: URL, to descendant: URL) -> [URL]? {
        var current = descendant.standardizedFileURL
        var reversedPath: [URL] = []
        while current != root {
            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent != current else { return nil }
            reversedPath.append(current)
            current = parent
        }
        return reversedPath.reversed()
    }
}
