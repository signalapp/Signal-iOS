//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc public enum ImageEditorError: Int, Error {
    case assertionError
    case invalidInput
}

// MARK: -

@objc
public class ImageEditorItem: NSObject {
    @objc
    public let itemId: String

    @objc
    public override required init() {
        self.itemId = UUID().uuidString

        super.init()
    }

    @objc
    public init(itemId: String) {
        self.itemId = itemId

        super.init()
    }
}

// MARK: -

public class ImageEditorContents: NSObject {

    var itemMap = [String: ImageEditorItem]()
    var itemIds = [String]()

    @objc
    public override init() {
    }

    @objc
    public init(itemMap: [String: ImageEditorItem],
                itemIds: [String]) {

        self.itemMap = itemMap
        self.itemIds = itemIds
    }

    @objc
    public func clone() -> ImageEditorContents {
        return ImageEditorContents(itemMap: itemMap, itemIds: itemIds)
    }

    @objc
    public func append(item: ImageEditorItem) {
        if itemMap[item.itemId] != nil {
            owsFail("Unexpected duplicate item in item map: \(item.itemId)")
        }
        itemMap[item.itemId] = item

        if itemIds.contains(item.itemId) {
            owsFail("Unexpected duplicate item in item list: \(item.itemId)")
        } else {
            itemIds.append(item.itemId)
        }

        if itemIds.count != itemMap.count {
            owsFailDebug("Invalid contents.")
        }
    }

    @objc
    public func replace(item: ImageEditorItem) {
        if itemMap[item.itemId] == nil {
            owsFail("Missing item in item map: \(item.itemId)")
        }
        itemMap[item.itemId] = item

        if !itemIds.contains(item.itemId) {
            owsFail("Missing item in item list: \(item.itemId)")
        }

        if itemIds.count != itemMap.count {
            owsFailDebug("Invalid contents.")
        }
    }

    @objc
    public func remove(item: ImageEditorItem) {
        remove(itemId: item.itemId)
    }

    @objc
    public func remove(itemId: String) {
        if itemMap[itemId] == nil {
            owsFail("Missing item in item map: \(itemId)")
        } else {
            itemMap.removeValue(forKey: itemId)
        }

        if !itemIds.contains(itemId) {
            owsFail("Missing item in item list: \(itemId)")
        } else {
            itemIds = itemIds.filter { $0 != itemId }
        }

        if itemIds.count != itemMap.count {
            owsFailDebug("Invalid contents.")
        }
    }

    @objc
    public func itemCount() -> Int {
        if itemIds.count != itemMap.count {
            owsFailDebug("Invalid contents.")
        }
        return itemIds.count
    }
}

// MARK: -

// Used to represent undo/redo operations.
private class ImageEditorOperation: NSObject {

    let contents: ImageEditorContents

    required init(contents: ImageEditorContents) {
        self.contents = contents
    }
}

// MARK: -

@objc
public class ImageEditorModel: NSObject {
    @objc
    public let srcImagePath: String

    @objc
    public let srcImageSize: CGSize

    private var contents = ImageEditorContents()

    private var undoStack = [ImageEditorOperation]()
    private var redoStack = [ImageEditorOperation]()

    @objc
    public required init(srcImagePath: String) throws {
        self.srcImagePath = srcImagePath

        let srcFileName = (srcImagePath as NSString).lastPathComponent
        let srcFileExtension = (srcFileName as NSString).pathExtension
        guard let mimeType = MIMETypeUtil.mimeType(forFileExtension: srcFileExtension) else {
            Logger.error("Couldn't determine MIME type for file.")
            throw ImageEditorError.invalidInput
        }
        guard MIMETypeUtil.isImage(mimeType) else {
            Logger.error("Invalid MIME type: \(mimeType).")
            throw ImageEditorError.invalidInput
        }

        let srcImageSize = NSData.imageSize(forFilePath: srcImagePath, mimeType: mimeType)
        guard srcImageSize.width > 0, srcImageSize.height > 0 else {
            Logger.error("Couldn't determine image size.")
            throw ImageEditorError.invalidInput
        }
        self.srcImageSize = srcImageSize

        super.init()
    }

    @objc
    public func itemCount() -> Int {
        return contents.itemCount()
    }

    @objc
    public func canUndo() -> Bool {
        return !undoStack.isEmpty
    }

    @objc
    public func canRedo() -> Bool {
        return !redoStack.isEmpty
    }

    @objc
    public func undo() {
        guard let undoOperation = undoStack.popLast() else {
            owsFailDebug("Cannot undo.")
            return
        }

        let redoOperation = ImageEditorOperation(contents: contents)
        redoStack.append(redoOperation)

        self.contents = undoOperation.contents
    }

    @objc
    public func redo() {
        guard let redoOperation = redoStack.popLast() else {
            owsFailDebug("Cannot redo.")
            return
        }

        let undoOperation = ImageEditorOperation(contents: contents)
        undoStack.append(undoOperation)

        self.contents = redoOperation.contents
    }

    @objc
    public func append(item: ImageEditorItem) {
        performAction { (newContents) in
            newContents.append(item: item)
        }
    }

    @objc
    public func replace(item: ImageEditorItem) {
        performAction { (newContents) in
            newContents.replace(item: item)
        }
    }

    @objc
    public func remove(item: ImageEditorItem) {
        performAction { (newContents) in
            newContents.remove(item: item)
        }
    }

    private func performAction(action: (ImageEditorContents) -> Void) {
        let undoOperation = ImageEditorOperation(contents: contents)
        undoStack.append(undoOperation)
        redoStack.removeAll()

        let newContents = contents.clone()
        action(newContents)
        contents = newContents
    }
}
