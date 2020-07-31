//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

// Used to represent undo/redo operations.
//
// Because the image editor's "contents" and "items"
// are immutable, these operations simply take a
// snapshot of the current contents which can be used
// (multiple times) to preserve/restore editor state.
private class ImageEditorOperation: NSObject {

    let operationId: String

    let contents: ImageEditorContents

    required init(contents: ImageEditorContents) {
        self.operationId = UUID().uuidString
        self.contents = contents
    }
}

// MARK: -

@objc
public protocol ImageEditorModelObserver: class {
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
    public let srcImagePath: String

    @objc
    public let srcImageSizePixels: CGSize

    private var contents: ImageEditorContents

    private var transform: ImageEditorTransform

    private var undoStack = [ImageEditorOperation]()
    private var redoStack = [ImageEditorOperation]()

    var blurredSourceImage: CGImage?

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

        self.contents = ImageEditorContents()
        self.transform = ImageEditorTransform.defaultTransform(srcImageSizePixels: srcImageSizePixels)

        super.init()
    }

    public func renderOutput() -> UIImage? {
        return ImageEditorCanvasView.renderForOutput(model: self, transform: currentTransform())
    }

    public func currentTransform() -> ImageEditorTransform {
        return transform
    }

    @objc
    public func isDirty() -> Bool {
        if itemCount() > 0 {
            return true
        }
        return transform != ImageEditorTransform.defaultTransform(srcImageSizePixels: srcImageSizePixels)
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
    public func itemIds() -> [String] {
        return contents.itemIds()
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
    public func currentUndoOperationId() -> String? {
        guard let operation = undoStack.last else {
            return nil
        }
        return operation.operationId
    }

    // MARK: - Observers

    private var observers = [Weak<ImageEditorModelObserver>]()

    @objc
    public func add(observer: ImageEditorModelObserver) {
        observers.append(Weak(value: observer))
    }

    private func fireModelDidChange(before: ImageEditorContents,
                                    after: ImageEditorContents) {
        // We could diff here and yield a more narrow change event.
        for weakObserver in observers {
            guard let observer = weakObserver.value else {
                continue
            }
            observer.imageEditorModelDidChange(before: before,
                                               after: after)
        }
    }

    private func fireModelDidChange(changedItemIds: [String]) {
        // We could diff here and yield a more narrow change event.
        for weakObserver in observers {
            guard let observer = weakObserver.value else {
                continue
            }
            observer.imageEditorModelDidChange(changedItemIds: changedItemIds)
        }
    }

    // MARK: -

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
        fireModelDidChange(before: oldContents, after: self.contents)
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
        fireModelDidChange(before: oldContents, after: self.contents)
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

    @objc
    public func replace(transform: ImageEditorTransform) {
        self.transform = transform

        // The contents haven't changed, but this event prods the
        // observers to reload everything, which is necessary if
        // the transform changes.
        fireModelDidChange(before: self.contents, after: self.contents)
    }

    // MARK: - Temp Files

    private var temporaryFilePaths = [String]()

    @objc
    public func temporaryFilePath(fileExtension: String) -> String {
        AssertIsOnMainThread()

        let filePath = OWSFileSystem.temporaryFilePath(fileExtension: fileExtension)
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
            fireModelDidChange(changedItemIds: changedItemIds)
        } else {
            fireModelDidChange(before: oldContents,
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
