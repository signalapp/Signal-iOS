//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

// ImageEditorContents represents a snapshot of canvas
// state.
//
// Instances of ImageEditorContents should be treated
// as immutable, once configured.
class ImageEditorContents: NSObject {

    typealias ItemMapType = OrderedDictionary<String, ImageEditorItem>

    // This represents the current state of each item,
    // a mapping of [itemId : item].
    var itemMap = ItemMapType()

    // Used to create an initial, empty instances of this class.
    override init() {
    }

    // Used to clone copies of instances of this class.
    init(itemMap: ItemMapType) {
        self.itemMap = itemMap
    }

    // Since the contents are immutable, we only modify copies
    // made with this method.
    func clone() -> ImageEditorContents {
        return ImageEditorContents(itemMap: itemMap)
    }

    @objc
    func item(forId itemId: String) -> ImageEditorItem? {
        return itemMap[itemId]
    }

    @objc
    func append(item: ImageEditorItem) {
        Logger.verbose("\(item.itemId)")

        itemMap.append(key: item.itemId, value: item)
    }

    @objc
    func replace(item: ImageEditorItem) {
        Logger.verbose("\(item.itemId)")

        itemMap.replace(key: item.itemId, value: item)
    }

    @objc
    func remove(item: ImageEditorItem) {
        Logger.verbose("\(item.itemId)")

        itemMap.remove(key: item.itemId)
    }

    @objc
    func remove(itemId: String) {
        Logger.verbose("\(itemId)")

        itemMap.remove(key: itemId)
    }

    @objc
    func itemCount() -> Int {
        return itemMap.count
    }

    @objc
    func items() -> [ImageEditorItem] {
        return itemMap.orderedValues
    }

    @objc
    func itemIds() -> [String] {
        return itemMap.orderedKeys
    }
}
