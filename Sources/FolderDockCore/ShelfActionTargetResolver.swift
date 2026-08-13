public enum ShelfActionTargetResolver {
    public static func resolve<Item, ID: Hashable>(
        clickedItem: Item,
        selectedIDs: Set<ID>,
        orderedItems: [Item],
        id: (Item) -> ID
    ) -> [Item] {
        let clickedID = id(clickedItem)
        guard selectedIDs.contains(clickedID) else { return [clickedItem] }
        let selectedItems = orderedItems.filter { selectedIDs.contains(id($0)) }
        return selectedItems.isEmpty ? [clickedItem] : selectedItems
    }
}

public enum ShelfAutoScrollDirection: Equatable, Sendable {
    case backward
    case forward
}

public enum ShelfAutoScrollTargetResolver {
    public static func resolve<ID: Hashable>(
        direction: ShelfAutoScrollDirection,
        orderedIDs: [ID],
        visibleIDs: Set<ID>
    ) -> ID? {
        let visibleIndexes = orderedIDs.indices.filter { visibleIDs.contains(orderedIDs[$0]) }
        guard let firstVisible = visibleIndexes.first,
              let lastVisible = visibleIndexes.last else { return nil }

        switch direction {
        case .backward:
            guard firstVisible > orderedIDs.startIndex else { return nil }
            return orderedIDs[orderedIDs.index(before: firstVisible)]
        case .forward:
            guard lastVisible < orderedIDs.index(before: orderedIDs.endIndex) else { return nil }
            return orderedIDs[orderedIDs.index(after: lastVisible)]
        }
    }
}

public struct SearchPathTreeNode<Value: Hashable & Sendable>: Sendable, Equatable {
    public let value: Value
    public let isMatch: Bool
    public let children: [SearchPathTreeNode<Value>]

    public init(value: Value, isMatch: Bool, children: [SearchPathTreeNode<Value>]) {
        self.value = value
        self.isMatch = isMatch
        self.children = children
    }
}

private final class MutableSearchPathTreeNode<Value: Hashable & Sendable> {
    let value: Value
    var isMatch = false
    var children: [Value: MutableSearchPathTreeNode<Value>] = [:]

    init(value: Value) {
        self.value = value
    }

    func frozen(sortedBy order: (Value, Value) -> Bool) -> SearchPathTreeNode<Value> {
        SearchPathTreeNode(
            value: value,
            isMatch: isMatch,
            children: children.values
                .sorted { order($0.value, $1.value) }
                .map { $0.frozen(sortedBy: order) }
        )
    }
}

public enum SearchPathTreeBuilder {
    public static func build<Value: Hashable & Sendable>(
        matchingPaths: [[Value]],
        sortedBy areInIncreasingOrder: (Value, Value) -> Bool
    ) -> [SearchPathTreeNode<Value>] {
        var roots: [Value: MutableSearchPathTreeNode<Value>] = [:]
        for path in matchingPaths where !path.isEmpty {
            var parent: MutableSearchPathTreeNode<Value>?
            for (index, value) in path.enumerated() {
                let existing = parent?.children[value] ?? roots[value]
                let node = existing ?? MutableSearchPathTreeNode(value: value)
                if existing == nil {
                    if let parent {
                        parent.children[value] = node
                    } else {
                        roots[value] = node
                    }
                }
                if index == path.indices.last { node.isMatch = true }
                parent = node
            }
        }
        return roots.values.sorted { areInIncreasingOrder($0.value, $1.value) }
            .map { $0.frozen(sortedBy: areInIncreasingOrder) }
    }
}
