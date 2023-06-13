//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// ImageEditorContents represents a snapshot of canvas
// state.
//
// Instances of ImageEditorContents should be treated
// as immutable, once configured.
class ImageEditorContents {

    typealias ItemMapType = OrderedDictionary<String, ImageEditorItem>

    // This represents the current state of each item,
    // a mapping of [itemId : item].
    private(set) var itemMap: ItemMapType

    // Used to clone copies of instances of this class.
    init(itemMap: ItemMapType? = nil) {
        self.itemMap = itemMap ?? ItemMapType()
    }

    // Since the contents are immutable, we only modify copies
    // made with this method.
    func clone() -> ImageEditorContents {
        return ImageEditorContents(itemMap: itemMap)
    }

    func item(forId itemId: String) -> ImageEditorItem? {
        return itemMap[itemId]
    }

    func append(item: ImageEditorItem) {
        Logger.verbose("\(item.itemId)")

        itemMap.append(key: item.itemId, value: item)
    }

    func replace(item: ImageEditorItem) {
        Logger.verbose("\(item.itemId)")

        itemMap.replace(key: item.itemId, value: item)
    }

    func remove(item: ImageEditorItem) {
        Logger.verbose("\(item.itemId)")

        itemMap.remove(key: item.itemId)
    }

    func remove(itemId: String) {
        Logger.verbose("\(itemId)")

        itemMap.remove(key: itemId)
    }

    func itemCount() -> Int {
        return itemMap.count
    }

    func items() -> [ImageEditorItem] {
        return itemMap.orderedValues
    }

    func itemIds() -> [String] {
        return itemMap.orderedKeys
    }
}
