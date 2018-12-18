//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc public enum ImageEditorError: Int, Error {
    case assertionError
    case invalidInput
}

@objc
public enum ImageEditorItemType: Int {
    case test
    case stroke
}

// MARK: -

// Instances of ImageEditorItem should be treated
// as immutable, once configured.
@objc
public class ImageEditorItem: NSObject {
    @objc
    public let itemId: String

    @objc
    public let itemType: ImageEditorItemType

    @objc
    public init(itemType: ImageEditorItemType) {
        self.itemId = UUID().uuidString
        self.itemType = itemType

        super.init()
    }

    @objc
    public init(itemId: String,
                itemType: ImageEditorItemType) {
        self.itemId = itemId
        self.itemType = itemType

        super.init()
    }
}

// MARK: -

@objc
public class ImageEditorStrokeItem: ImageEditorItem {
    // Until we need to serialize these items,
    // just use UIColor.
    @objc
    public let color: UIColor

    // Represented in a "ULO unit" coordinate system
    // for source image.
    //
    // "ULO" coordinate system is "upper-left-origin".
    //
    // "Unit" coordinate system means values are expressed
    // in terms of some other values, in this case the
    // width and height of the source image.
    //
    // * 0.0 = left edge
    // * 1.0 = right edge
    // * 0.0 = top edge
    // * 1.0 = bottom edge
    public typealias StrokeSample = CGPoint

    @objc
    public let unitSamples: [StrokeSample]

    // Expressed as a "Unit" value as a fraction of
    // min(width, height) of the destination viewport.
    @objc
    public let unitStrokeWidth: CGFloat

    @objc
    public init(color: UIColor,
                unitSamples: [StrokeSample],
                unitStrokeWidth: CGFloat) {
        self.color = color
        self.unitSamples = unitSamples
        self.unitStrokeWidth = unitStrokeWidth

        super.init(itemType: .stroke)
    }

    @objc
    public init(itemId: String,
                color: UIColor,
                unitSamples: [StrokeSample],
                unitStrokeWidth: CGFloat) {
        self.color = color
        self.unitSamples = unitSamples
        self.unitStrokeWidth = unitStrokeWidth

        super.init(itemId: itemId, itemType: .stroke)
    }

    @objc
    public class func defaultUnitStrokeWidth() -> CGFloat {
        return 0.02
    }

    @objc
    public class func strokeWidth(forUnitStrokeWidth unitStrokeWidth: CGFloat,
                                  dstSize: CGSize) -> CGFloat {
        return CGFloatClamp01(unitStrokeWidth) * min(dstSize.width, dstSize.height)
    }
}

// MARK: -

public class OrderedDictionary<ValueType>: NSObject {

    public typealias KeyType = String

    var keyValueMap = [KeyType: ValueType]()

    var orderedKeys = [KeyType]()

    public override init() {
    }

    // Used to clone copies of instances of this class.
    public init(keyValueMap: [KeyType: ValueType],
                orderedKeys: [KeyType]) {

        self.keyValueMap = keyValueMap
        self.orderedKeys = orderedKeys
    }

    // Since the contents are immutable, we only modify copies
    // made with this method.
    public func clone() -> OrderedDictionary<ValueType> {
        return OrderedDictionary(keyValueMap: keyValueMap, orderedKeys: orderedKeys)
    }

    public func append(key: KeyType, value: ValueType) {
        if keyValueMap[key] != nil {
            owsFailDebug("Unexpected duplicate key in key map: \(key)")
        }
        keyValueMap[key] = value

        if orderedKeys.contains(key) {
            owsFailDebug("Unexpected duplicate key in key list: \(key)")
        } else {
            orderedKeys.append(key)
        }

        if orderedKeys.count != keyValueMap.count {
            owsFailDebug("Invalid contents.")
        }
    }

    public func replace(key: KeyType, value: ValueType) {
        if keyValueMap[key] == nil {
            owsFailDebug("Missing key in key map: \(key)")
        }
        keyValueMap[key] = value

        if !orderedKeys.contains(key) {
            owsFailDebug("Missing key in key list: \(key)")
        }

        if orderedKeys.count != keyValueMap.count {
            owsFailDebug("Invalid contents.")
        }
    }

    public func remove(key: KeyType) {
        if keyValueMap[key] == nil {
            owsFailDebug("Missing key in key map: \(key)")
        } else {
            keyValueMap.removeValue(forKey: key)
        }

        if !orderedKeys.contains(key) {
            owsFailDebug("Missing key in key list: \(key)")
        } else {
            orderedKeys = orderedKeys.filter { $0 != key }
        }

        if orderedKeys.count != keyValueMap.count {
            owsFailDebug("Invalid contents.")
        }
    }

    public var count: Int {
        if orderedKeys.count != keyValueMap.count {
            owsFailDebug("Invalid contents.")
        }
        return orderedKeys.count
    }

    public func orderedValues() -> [ValueType] {
        var values = [ValueType]()
        for key in orderedKeys {
            guard let value = self.keyValueMap[key] else {
                owsFailDebug("Missing value")
                continue
            }
            values.append(value)
        }
        return values
    }
}

// MARK: -

// ImageEditorContents represents a snapshot of canvas
// state.
//
// Instances of ImageEditorContents should be treated
// as immutable, once configured.
public class ImageEditorContents: NSObject {

    public typealias ItemMapType = OrderedDictionary<ImageEditorItem>

    // This represents the current state of each item,
    // a mapping of [itemId : item].
    var itemMap = ItemMapType()

    // Used to create an initial, empty instances of this class.
    public override init() {
    }

    // Used to clone copies of instances of this class.
    public init(itemMap: ItemMapType) {
        self.itemMap = itemMap
    }

    // Since the contents are immutable, we only modify copies
    // made with this method.
    public func clone() -> ImageEditorContents {
        return ImageEditorContents(itemMap: itemMap.clone())
    }

    @objc
    public func append(item: ImageEditorItem) {
        Logger.verbose("\(item.itemId)")

        itemMap.append(key: item.itemId, value: item)
    }

    @objc
    public func replace(item: ImageEditorItem) {
        Logger.verbose("\(item.itemId)")

        itemMap.replace(key: item.itemId, value: item)
    }

    @objc
    public func remove(item: ImageEditorItem) {
        Logger.verbose("\(item.itemId)")

        itemMap.remove(key: item.itemId)
    }

    @objc
    public func remove(itemId: String) {
        Logger.verbose("\(itemId)")

        itemMap.remove(key: itemId)
    }

    @objc
    public func itemCount() -> Int {
        return itemMap.count
    }

    @objc
    public func items() -> [ImageEditorItem] {
        return itemMap.orderedValues()
    }
}

// MARK: -

// Used to represent undo/redo operations.
//
// Because the image editor's "contents" and "items"
// are immutable, these operations simply take a
// snapshot of the current contents which can be used
// (multiple times) to preserve/restore editor state.
private class ImageEditorOperation: NSObject {

    let contents: ImageEditorContents

    required init(contents: ImageEditorContents) {
        self.contents = contents
    }
}

// MARK: -

@objc
public protocol ImageEditorModelDelegate: class {
    func imageEditorModelDidChange()
}

// MARK: -

@objc
public class ImageEditorModel: NSObject {
    @objc
    public weak var delegate: ImageEditorModelDelegate?

    @objc
    public let srcImagePath: String

    @objc
    public let srcImageSizePixels: CGSize

    private var contents = ImageEditorContents()

    private var undoStack = [ImageEditorOperation]()
    private var redoStack = [ImageEditorOperation]()

    // We don't want to allow editing of images if:
    //
    // * They are invalid.
    // * We can't determine their size / aspect-ratio.
    @objc
    public required init(srcImagePath: String) throws {
        self.srcImagePath = srcImagePath

        let srcFileName = (srcImagePath as NSString).lastPathComponent
        let srcFileExtension = (srcFileName as NSString).pathExtension
        guard let mimeType = MIMETypeUtil.mimeType(forFileExtension: srcFileExtension) else {
            Logger.error("Couldn't determine MIME type for file.")
            throw ImageEditorError.invalidInput
        }
        guard MIMETypeUtil.isImage(mimeType),
            !MIMETypeUtil.isAnimated(mimeType) else {
            Logger.error("Invalid MIME type: \(mimeType).")
            throw ImageEditorError.invalidInput
        }

        let srcImageSizePixels = NSData.imageSize(forFilePath: srcImagePath, mimeType: mimeType)
        guard srcImageSizePixels.width > 0, srcImageSizePixels.height > 0 else {
            Logger.error("Couldn't determine image size.")
            throw ImageEditorError.invalidInput
        }
        self.srcImageSizePixels = srcImageSizePixels

        super.init()
    }

    @objc
    public func itemCount() -> Int {
        return contents.itemCount()
    }

    @objc
    public func items() -> [ImageEditorItem] {
        return contents.items()
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

        delegate?.imageEditorModelDidChange()
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

        delegate?.imageEditorModelDidChange()
    }

    @objc
    public func append(item: ImageEditorItem) {
        performAction({ (newContents) in
            newContents.append(item: item)
        })
    }

    @objc
    public func replace(item: ImageEditorItem,
                        suppressUndo: Bool = false) {
        performAction({ (newContents) in
            newContents.replace(item: item)
        }, suppressUndo: suppressUndo)
    }

    @objc
    public func remove(item: ImageEditorItem) {
        performAction({ (newContents) in
            newContents.remove(item: item)
        })
    }

    private func performAction(_ action: (ImageEditorContents) -> Void,
                               suppressUndo: Bool = false) {
        if !suppressUndo {
            let undoOperation = ImageEditorOperation(contents: contents)
            undoStack.append(undoOperation)
            redoStack.removeAll()
        }

        let newContents = contents.clone()
        action(newContents)
        contents = newContents

        delegate?.imageEditorModelDidChange()
    }
}
