//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Represents a snapshot of canvas state.
struct ImageEditorContents {

    typealias ItemMap = OrderedDictionary<String, ImageEditorItem>

    // This represents the current state of each item,
    // a mapping of [itemId : item].
    private(set) var itemMap = ItemMap()

    func item(forId itemId: String) -> ImageEditorItem? {
        return itemMap[itemId]
    }

    mutating func append(item: ImageEditorItem) {
        itemMap.append(key: item.itemId, value: item)
    }

    mutating func replace(item: ImageEditorItem) {
        itemMap.replace(key: item.itemId, value: item)
    }

    mutating func remove(item: ImageEditorItem) {
        itemMap.remove(key: item.itemId)
    }

    mutating func remove(itemId: String) {
        itemMap.remove(key: itemId)
    }

    var itemCount: Int {
        return itemMap.count
    }

    var items: [ImageEditorItem] {
        return itemMap.orderedValues
    }

    var itemIds: [String] {
        return itemMap.orderedKeys
    }
}
