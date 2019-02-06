//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
    case text
}

// MARK: -

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
public typealias ImageEditorSample = CGPoint

public typealias ImageEditorConversion = (ImageEditorSample) -> ImageEditorSample

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

    public func clone(withImageEditorConversion conversion: ImageEditorConversion) -> ImageEditorItem {
        return ImageEditorItem(itemId: itemId, itemType: itemType)
    }

    public func outputScale() -> CGFloat {
        return 1.0
    }
}

// MARK: -

@objc
public class ImageEditorStrokeItem: ImageEditorItem {
    // Until we need to serialize these items,
    // just use UIColor.
    @objc
    public let color: UIColor

    public typealias StrokeSample = ImageEditorSample

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

    public override func clone(withImageEditorConversion conversion: ImageEditorConversion) -> ImageEditorItem {
        // TODO: We might want to convert the unitStrokeWidth too.
        let convertedUnitSamples = unitSamples.map { (sample) in
            conversion(sample)
        }
        return ImageEditorStrokeItem(itemId: itemId,
                                     color: color,
                                     unitSamples: convertedUnitSamples,
                                     unitStrokeWidth: unitStrokeWidth)
    }
}

// MARK: -

@objc
public class ImageEditorTextItem: ImageEditorItem {
    // Until we need to serialize these items,
    // just use UIColor.
    @objc
    public let color: UIColor

    @objc
    public let font: UIFont

    @objc
    public let text: String

    @objc
    public let unitCenter: ImageEditorSample

    // Leave some margins against the edge of the image.
    @objc
    public static let kDefaultUnitWidth: CGFloat = 0.9

    // The max width of the text as a fraction of the image width.
    @objc
    public let unitWidth: CGFloat

    // 0 = no rotation.
    // CGFloat.pi * 0.5 = rotation 90 degrees clockwise.
    @objc
    public let rotationRadians: CGFloat

    @objc
    public static let kMaxScaling: CGFloat = 4.0
    @objc
    public static let kMinScaling: CGFloat = 0.5
    @objc
    public let scaling: CGFloat

    // This might be nil while the item is a "draft" item.
    // Once the item has been "committed" to the model, it
    // should always be non-nil,
    @objc
    public let imagePath: String?

    @objc
    public init(color: UIColor,
                font: UIFont,
                text: String,
                unitCenter: ImageEditorSample = CGPoint(x: 0.5, y: 0.5),
                unitWidth: CGFloat = ImageEditorTextItem.kDefaultUnitWidth,
                rotationRadians: CGFloat = 0.0,
                scaling: CGFloat = 1.0,
                imagePath: String? = nil) {
        self.color = color
        self.font = font
        self.text = text
        self.unitCenter = unitCenter
        self.unitWidth = unitWidth
        self.rotationRadians = rotationRadians
        self.scaling = scaling
        self.imagePath = imagePath

        super.init(itemType: .text)
    }

    private init(itemId: String,
                color: UIColor,
                font: UIFont,
                text: String,
                unitCenter: ImageEditorSample,
                unitWidth: CGFloat,
                rotationRadians: CGFloat,
                scaling: CGFloat,
                imagePath: String?) {
        self.color = color
        self.font = font
        self.text = text
        self.unitCenter = unitCenter
        self.unitWidth = unitWidth
        self.rotationRadians = rotationRadians
        self.scaling = scaling
        self.imagePath = imagePath

        super.init(itemId: itemId, itemType: .text)
    }

    @objc
    public class func empty(withColor color: UIColor) -> ImageEditorTextItem {
        let font = UIFont.boldSystemFont(ofSize: 30.0)
        return ImageEditorTextItem(color: color, font: font, text: "")
    }

    @objc
    public func copy(withText newText: String) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   color: color,
                                   font: font,
                                   text: newText,
                                   unitCenter: unitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling,
                                   imagePath: imagePath)
    }

    @objc
    public func copy(withUnitCenter newUnitCenter: CGPoint) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   color: color,
                                   font: font,
                                   text: text,
                                   unitCenter: newUnitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling,
                                   imagePath: imagePath)
    }

    @objc
    public func copy(withUnitCenter newUnitCenter: CGPoint,
                     scaling newScaling: CGFloat,
                     rotationRadians newRotationRadians: CGFloat) -> ImageEditorTextItem {
        return ImageEditorTextItem(itemId: itemId,
                                   color: color,
                                   font: font,
                                   text: text,
                                   unitCenter: newUnitCenter,
                                   unitWidth: unitWidth,
                                   rotationRadians: newRotationRadians,
                                   scaling: newScaling,
                                   imagePath: imagePath)
    }

    public override func clone(withImageEditorConversion conversion: ImageEditorConversion) -> ImageEditorItem {
        let convertedUnitCenter = conversion(unitCenter)
        let convertedUnitWidth = conversion(CGPoint(x: unitWidth, y: 0)).x

        return ImageEditorTextItem(itemId: itemId,
                                   color: color,
                                   font: font,
                                   text: text,
                                   unitCenter: convertedUnitCenter,
                                   unitWidth: convertedUnitWidth,
                                   rotationRadians: rotationRadians,
                                   scaling: scaling,
                                   imagePath: imagePath)
    }

    public override func outputScale() -> CGFloat {
        return scaling
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

    public func value(forKey key: KeyType) -> ValueType? {
        return keyValueMap[key]
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

    @objc
    public let imagePath: String

    @objc
    public let imageSizePixels: CGSize

    public typealias ItemMapType = OrderedDictionary<ImageEditorItem>

    // This represents the current state of each item,
    // a mapping of [itemId : item].
    var itemMap = ItemMapType()

    // Used to create an initial, empty instances of this class.
    public init(imagePath: String,
                imageSizePixels: CGSize) {
        self.imagePath = imagePath
        self.imageSizePixels = imageSizePixels
    }

    // Used to clone copies of instances of this class.
    public init(imagePath: String,
                imageSizePixels: CGSize,
                itemMap: ItemMapType) {
        self.imagePath = imagePath
        self.imageSizePixels = imageSizePixels
        self.itemMap = itemMap
    }

    // Since the contents are immutable, we only modify copies
    // made with this method.
    public func clone() -> ImageEditorContents {
        return ImageEditorContents(imagePath: imagePath,
                                   imageSizePixels: imageSizePixels,
                                   itemMap: itemMap.clone())
    }

    @objc
    public func item(forId itemId: String) -> ImageEditorItem? {
        return itemMap.value(forKey: itemId)
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
    // Used for large changes to the model, when the entire
    // model should be reloaded.
    func imageEditorModelDidChange(before: ImageEditorContents,
                                   after: ImageEditorContents)

    // Used for small narrow changes to the model, usually
    // to a single item.
    func imageEditorModelDidChange(changedItemIds: [String])
}

// MARK: -

@objc
public class ImageEditorModel: NSObject {

    @objc
    public static var isFeatureEnabled: Bool {
        return _isDebugAssertConfiguration()
    }

    @objc
    public weak var delegate: ImageEditorModelDelegate?

    @objc
    public let srcImagePath: String

    @objc
    public let srcImageSizePixels: CGSize

    private var contents: ImageEditorContents

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

        self.contents = ImageEditorContents(imagePath: srcImagePath,
                                            imageSizePixels: srcImageSizePixels)

        super.init()
    }

    @objc
    public var currentImagePath: String {
        return contents.imagePath
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
    public func has(itemForId itemId: String) -> Bool {
        return item(forId: itemId) != nil
    }

    @objc
    public func item(forId itemId: String) -> ImageEditorItem? {
        return contents.item(forId: itemId)
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

        let oldContents = self.contents
        self.contents = undoOperation.contents

        // We could diff here and yield a more narrow change event.
        delegate?.imageEditorModelDidChange(before: oldContents,
                                            after: self.contents)
    }

    @objc
    public func redo() {
        guard let redoOperation = redoStack.popLast() else {
            owsFailDebug("Cannot redo.")
            return
        }

        let undoOperation = ImageEditorOperation(contents: contents)
        undoStack.append(undoOperation)

        let oldContents = self.contents
        self.contents = redoOperation.contents

        // We could diff here and yield a more narrow change event.
        delegate?.imageEditorModelDidChange(before: oldContents,
                                            after: self.contents)
    }

    @objc
    public func append(item: ImageEditorItem) {
        performAction({ (oldContents) in
            let newContents = oldContents.clone()
            newContents.append(item: item)
            return newContents
        }, changedItemIds: [item.itemId])
    }

    @objc
    public func replace(item: ImageEditorItem,
                        suppressUndo: Bool = false) {
        performAction({ (oldContents) in
            let newContents = oldContents.clone()
            newContents.replace(item: item)
            return newContents
        }, changedItemIds: [item.itemId],
           suppressUndo: suppressUndo)
    }

    @objc
    public func remove(item: ImageEditorItem) {
        performAction({ (oldContents) in
            let newContents = oldContents.clone()
            newContents.remove(item: item)
            return newContents
        }, changedItemIds: [item.itemId])
    }

    // MARK: - Temp Files

    private var temporaryFilePaths = [String]()

    @objc
    public func temporaryFilePath(withFileExtension fileExtension: String) -> String {
        AssertIsOnMainThread()

        let filePath = OWSFileSystem.temporaryFilePath(withFileExtension: fileExtension)
        temporaryFilePaths.append(filePath)
        return filePath
    }

    deinit {
        AssertIsOnMainThread()

        let temporaryFilePaths = self.temporaryFilePaths

        DispatchQueue.global(qos: .background).async {
            for filePath in temporaryFilePaths {
                guard OWSFileSystem.deleteFile(filePath) else {
                    Logger.error("Could not delete temp file: \(filePath)")
                    continue
                }
            }
        }
    }

    // MARK: - Crop

    @objc
    public func crop(unitCropRect: CGRect) {
        guard let croppedImage = ImageEditorModel.crop(imagePath: contents.imagePath,
                                                 unitCropRect: unitCropRect) else {
                                                    // Not an error; user might have tapped or
                                                    // otherwise drawn an invalid crop region.
            Logger.warn("Could not crop image.")
            return
        }
        // Use PNG for temp files; PNG is lossless.
        guard let croppedImageData = UIImagePNGRepresentation(croppedImage) else {
            owsFailDebug("Could not convert cropped image to PNG.")
            return
        }
        let croppedImagePath = temporaryFilePath(withFileExtension: "png")
        do {
            try croppedImageData.write(to: NSURL.fileURL(withPath: croppedImagePath), options: .atomicWrite)
        } catch let error as NSError {
            owsFailDebug("File write failed: \(error)")
            return
        }
        let croppedImageSizePixels = CGSizeScale(croppedImage.size, croppedImage.scale)

        let left = unitCropRect.origin.x
        let right = unitCropRect.origin.x + unitCropRect.size.width
        let top = unitCropRect.origin.y
        let bottom = unitCropRect.origin.y + unitCropRect.size.height
        let conversion: ImageEditorConversion = { (point) in
            // Convert from the pre-crop unit coordinate system
            // to post-crop unit coordinate system using inverse
            // lerp.
            //
            // NOTE: Some post-conversion unit values will _NOT_
            //       be clamped. e.g. strokes outside the crop
            //       are that < 0 or > 1.  This is fine.
            //       We could hypothethically discard any items
            //       whose bounding box is entirely outside the
            //       new unit rectangle (e.g. have been completely
            //       cropped) but it doesn't seem worthwhile.
            let converted = CGPoint(x: CGFloatInverseLerp(point.x, left, right),
                                    y: CGFloatInverseLerp(point.y, top, bottom))
            return converted
        }

        performAction({ (oldContents) in
            let newContents = ImageEditorContents(imagePath: croppedImagePath,
                                                  imageSizePixels: croppedImageSizePixels)
            for oldItem in oldContents.items() {
                let newItem = oldItem.clone(withImageEditorConversion: conversion)
                newContents.append(item: newItem)
            }
            return newContents
        }, changedItemIds: nil)
    }

    private func performAction(_ action: (ImageEditorContents) -> ImageEditorContents,
                               changedItemIds: [String]?,
                               suppressUndo: Bool = false) {
        if !suppressUndo {
            let undoOperation = ImageEditorOperation(contents: contents)
            undoStack.append(undoOperation)
            redoStack.removeAll()
        }

        let oldContents = self.contents
        let newContents = action(oldContents)
        contents = newContents

        if let changedItemIds = changedItemIds {
            delegate?.imageEditorModelDidChange(changedItemIds: changedItemIds)
        } else {
            delegate?.imageEditorModelDidChange(before: oldContents,
                                                after: self.contents)
        }
    }

    // MARK: - Utilities

    // Returns nil on error.
    private class func crop(imagePath: String,
                            unitCropRect: CGRect) -> UIImage? {
        // TODO: Do we want to render off the main thread?
        AssertIsOnMainThread()

        guard let srcImage = UIImage(contentsOfFile: imagePath) else {
            owsFailDebug("Could not load image")
            return nil
        }
        let srcImageSize = srcImage.size
        // Convert from unit coordinates to src image coordinates.
        let cropRect = CGRect(x: round(unitCropRect.origin.x * srcImageSize.width),
                              y: round(unitCropRect.origin.y * srcImageSize.height),
                              width: round(unitCropRect.size.width * srcImageSize.width),
                              height: round(unitCropRect.size.height * srcImageSize.height))

        guard cropRect.origin.x >= 0,
            cropRect.origin.y >= 0,
            cropRect.origin.x + cropRect.size.width <= srcImageSize.width,
            cropRect.origin.y + cropRect.size.height <= srcImageSize.height else {
                owsFailDebug("Invalid crop rectangle.")
                return nil
        }
        guard cropRect.size.width > 0,
            cropRect.size.height > 0 else {
                // Not an error; indicates that the user tapped rather
                // than dragged.
                Logger.warn("Empty crop rectangle.")
                return nil
        }

        let hasAlpha = NSData.hasAlpha(forValidImageFilePath: imagePath)

        UIGraphicsBeginImageContextWithOptions(cropRect.size, !hasAlpha, srcImage.scale)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else {
            owsFailDebug("context was unexpectedly nil")
            return nil
        }
        context.interpolationQuality = .high

        // Draw source image.
        let dstFrame = CGRect(origin: CGPointInvert(cropRect.origin), size: srcImageSize)
        srcImage.draw(in: dstFrame)

        let dstImage = UIGraphicsGetImageFromCurrentImageContext()
        if dstImage == nil {
            owsFailDebug("could not generate dst image.")
        }
        return dstImage
    }
}
