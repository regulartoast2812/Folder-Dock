import FolderDockCore
import Foundation

private struct Item: Equatable {
    let id: UUID
    let name: String

    init(_ name: String) {
        id = UUID()
        self.name = name
    }
}

@main
struct FolderDockGuardrails {
    static func main() {
        selectedClickTargetsCompleteSelectionInOrder()
        unselectedClickTargetsOnlyClickedItem()
        staleSelectionIsIgnored()
        missingOrderedSelectionFallsBackToClickedItem()
        autoScrollAdvancesPastVisibleItems()
        autoScrollStopsAtCollectionEdges()
        recursiveSearchKeepsSharedAncestorHierarchy()
        recursiveSearchMarksOnlyActualMatches()
        recursiveFileSearchFindsNestedMatches()
        print("Folder Dock guardrails passed")
    }

    private static func selectedClickTargetsCompleteSelectionInOrder() {
        let first = Item("First")
        let second = Item("Second")
        let third = Item("Third")
        let result = resolve(clicked: third, selected: [first.id, third.id], ordered: [first, second, third])
        require(result.map(\.id) == [first.id, third.id], "selected context action lost shelf order or selection")
    }

    private static func unselectedClickTargetsOnlyClickedItem() {
        let first = Item("First")
        let second = Item("Second")
        let result = resolve(clicked: second, selected: [first.id], ordered: [first, second])
        require(result.map(\.id) == [second.id], "unselected right-click inherited another selection")
    }

    private static func staleSelectionIsIgnored() {
        let first = Item("First")
        let second = Item("Second")
        let result = resolve(clicked: first, selected: [first.id, UUID()], ordered: [first, second])
        require(result.map(\.id) == [first.id], "stale selected IDs became action targets")
    }

    private static func missingOrderedSelectionFallsBackToClickedItem() {
        let clicked = Item("Clicked")
        let result = resolve(clicked: clicked, selected: [clicked.id], ordered: [])
        require(result.map(\.id) == [clicked.id], "empty ordered state produced no safe action target")
    }

    private static func autoScrollAdvancesPastVisibleItems() {
        let ids = (0..<6).map { _ in UUID() }
        let visible: Set<UUID> = [ids[2], ids[3]]
        let backward = ShelfAutoScrollTargetResolver.resolve(
            direction: .backward,
            orderedIDs: ids,
            visibleIDs: visible
        )
        let forward = ShelfAutoScrollTargetResolver.resolve(
            direction: .forward,
            orderedIDs: ids,
            visibleIDs: visible
        )
        require(backward == ids[1], "backward marquee auto-scroll chose the wrong target")
        require(forward == ids[4], "forward marquee auto-scroll chose the wrong target")
    }

    private static func autoScrollStopsAtCollectionEdges() {
        let ids = (0..<3).map { _ in UUID() }
        let allVisible = Set(ids)
        require(
            ShelfAutoScrollTargetResolver.resolve(direction: .backward, orderedIDs: ids, visibleIDs: allVisible) == nil,
            "backward marquee auto-scroll passed the first item"
        )
        require(
            ShelfAutoScrollTargetResolver.resolve(direction: .forward, orderedIDs: ids, visibleIDs: allVisible) == nil,
            "forward marquee auto-scroll passed the last item"
        )
    }

    private static func recursiveSearchKeepsSharedAncestorHierarchy() {
        let tree = SearchPathTreeBuilder.build(
            matchingPaths: [
                ["Project", "Assets", "Images", "logo.png"],
                ["Project", "Assets", "Audio", "logo-theme.mp3"],
                ["Project", "Exports", "logo-final.mov"]
            ],
            sortedBy: { $0.localizedStandardCompare($1) == .orderedAscending }
        )
        require(tree.map(\.value) == ["Project"], "recursive search duplicated the shared root")
        require(
            tree[0].children.map(\.value) == ["Assets", "Exports"],
            "recursive search attached results to the wrong branch"
        )
        require(
            tree[0].children[0].children.map(\.value) == ["Audio", "Images"],
            "recursive search lost nested sibling branches"
        )
    }

    private static func recursiveSearchMarksOnlyActualMatches() {
        let tree = SearchPathTreeBuilder.build(
            matchingPaths: [["Parent", "Match.txt"], ["Parent", "Match.txt"]],
            sortedBy: <
        )
        require(!tree[0].isMatch, "recursive search marked an ancestor as a result")
        require(tree[0].children.count == 1, "recursive search duplicated the same result")
        require(tree[0].children[0].isMatch, "recursive search failed to mark the actual result")
    }

    private static func recursiveFileSearchFindsNestedMatches() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderDockRecursiveSearch-\(UUID().uuidString)")
        let nestedFolder = root
            .appendingPathComponent("Donna Marie")
            .appendingPathComponent("Fitting")
        let matchingFile = nestedFolder.appendingPathComponent("Size M - Black white.mov")
        let ignoredFile = root.appendingPathComponent("green.mov")
        do {
            try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
            try Data().write(to: matchingFile)
            try Data().write(to: ignoredFile)
            defer { try? FileManager.default.removeItem(at: root) }

            let result = try RecursiveFileSearcher.search(in: root, query: "black")
            require(result.matchCount == 1, "recursive file search returned the wrong match count")
            require(
                result.matchingPaths.first?.map(\.lastPathComponent)
                    == ["Donna Marie", "Fitting", "Size M - Black white.mov"],
                "recursive file search lost the nested ancestor path"
            )
        } catch {
            require(false, "recursive file search fixture failed: \(error)")
        }
    }

    private static func resolve(clicked: Item, selected: Set<UUID>, ordered: [Item]) -> [Item] {
        ShelfActionTargetResolver.resolve(
            clickedItem: clicked,
            selectedIDs: selected,
            orderedItems: ordered,
            id: \.id
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("Guardrail failed: \(message)\n".utf8))
            exit(1)
        }
    }
}
