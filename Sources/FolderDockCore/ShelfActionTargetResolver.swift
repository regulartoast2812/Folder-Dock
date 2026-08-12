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
