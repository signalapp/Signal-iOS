//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// Used to represent undo/redo operations.
//
// Because the image editor's "contents" and "items"
// are immutable, these operations simply take a
// snapshot of the current contents which can be used
// (multiple times) to preserve/restore editor state.
private class ImageEditorOperation: NSObject {

    let operationId: String

    let contents: ImageEditorContents

    init(contents: ImageEditorContents) {
        self.operationId = UUID().uuidString
        self.contents = contents
    }
}

// MARK: -

protocol ImageEditorModelObserver: AnyObject {
    // Used for large changes to the model, when the entire
    // model should be reloaded.
    func imageEditorModelDidChange(
        before: ImageEditorContents,
        after: ImageEditorContents,
    )

    // Used for small narrow changes to the model, usually
    // to a single item.
    func imageEditorModelDidChange(changedItemIds: [String])
}

// MARK: -

// Should be @MainActor.
class ImageEditorModel: NSObject {

    let srcImage: NormalizedImage
    let srcImageSizePixels: CGSize
    let srcImageMetadata: ImageMetadata

    private var contents: ImageEditorContents

    private var transform: ImageEditorTransform

    private var undoStack = [ImageEditorOperation]()
    private var redoStack = [ImageEditorOperation]()

    typealias StickerImageCache = LRUCache<String, ThreadSafeCacheHandle<UIImage>>
    var stickerViewCache = StickerImageCache(maxSize: 16, shouldEvacuateInBackground: true)

    var blurredSourceImage: CGImage?

    var color = ColorPickerBarColor.defaultColor

    init(normalizedImage: NormalizedImage) throws {
        self.srcImage = normalizedImage
        let srcImageMetadata = try normalizedImage.dataSource.imageSource().imageMetadata()
        guard let srcImageMetadata else {
            throw ImageEditorError.invalidInput
        }
        self.srcImageMetadata = srcImageMetadata
        let srcImageSizePixels = srcImageMetadata.pixelSize
        guard srcImageSizePixels.width > 0, srcImageSizePixels.height > 0 else {
            throw ImageEditorError.invalidInput
        }
        self.srcImageSizePixels = srcImageSizePixels

        self.contents = ImageEditorContents()
        self.transform = ImageEditorTransform.defaultTransform(srcImageSizePixels: srcImageSizePixels)

        super.init()
    }

    @MainActor
    func renderOutput() -> UIImage? {
        return ImageEditorCanvasView.renderForOutput(model: self, transform: currentTransform())
    }

    func currentTransform() -> ImageEditorTransform {
        return transform
    }

    var isDirty: Bool {
        if itemCount > 0 {
            return true
        }
        return transform != ImageEditorTransform.defaultTransform(srcImageSizePixels: srcImageSizePixels)
    }

    var itemCount: Int {
        contents.itemCount
    }

    var items: [ImageEditorItem] {
        contents.items
    }

    var itemIds: [String] {
        contents.itemIds
    }

    func has(itemForId itemId: String) -> Bool {
        return item(forId: itemId) != nil
    }

    func item(forId itemId: String) -> ImageEditorItem? {
        return contents.item(forId: itemId)
    }

    var canUndo: Bool {
        return !undoStack.isEmpty
    }

    var canRedo: Bool {
        return !redoStack.isEmpty
    }

    var currentUndoOperationId: String? {
        guard let operation = undoStack.last else {
            return nil
        }
        return operation.operationId
    }

    // MARK: - Observers

    private var observers = [Weak<ImageEditorModelObserver>]()

    func add(observer: ImageEditorModelObserver) {
        observers.append(Weak(value: observer))
    }

    private func fireModelDidChange(
        before: ImageEditorContents,
        after: ImageEditorContents,
    ) {
        // We could diff here and yield a more narrow change event.
        for weakObserver in observers {
            guard let observer = weakObserver.value else {
                continue
            }
            observer.imageEditorModelDidChange(
                before: before,
                after: after,
            )
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

    func undo() {
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

    func redo() {
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

    func append(item: ImageEditorItem) {
        performAction(
            { oldContents in
                var newContents = oldContents
                newContents.append(item: item)
                return newContents
            },
            changedItemIds: [item.itemId],
        )
    }

    func replace(item: ImageEditorItem, suppressUndo: Bool = false) {
        performAction(
            { oldContents in
                var newContents = oldContents
                newContents.replace(item: item)
                return newContents
            },
            changedItemIds: [item.itemId],
            suppressUndo: suppressUndo,
        )
    }

    func remove(item: ImageEditorItem) {
        performAction(
            { oldContents in
                var newContents = oldContents
                newContents.remove(item: item)
                return newContents
            },
            changedItemIds: [item.itemId],
        )
    }

    func replace(transform: ImageEditorTransform) {
        self.transform = transform

        // The contents haven't changed, but this event prods the
        // observers to reload everything, which is necessary if
        // the transform changes.
        fireModelDidChange(before: self.contents, after: self.contents)
    }

    // MARK: - Temp Files

    private var temporaryFilePaths = [String]()

    func temporaryFilePath(fileExtension: String) -> String {
        AssertIsOnMainThread()

        let filePath = OWSFileSystem.temporaryFilePath(
            fileExtension: fileExtension,
            isAvailableWhileDeviceLocked: false,
        )
        temporaryFilePaths.append(filePath)
        return filePath
    }

    deinit {
        AssertIsOnMainThread()

        let temporaryFilePaths = self.temporaryFilePaths

        DispatchQueue.sharedUtility.async {
            for filePath in temporaryFilePaths {
                guard OWSFileSystem.deleteFile(filePath) else {
                    Logger.error("Could not delete temp file: \(filePath)")
                    continue
                }
            }
        }
    }

    private func performAction(
        _ action: (ImageEditorContents) -> ImageEditorContents,
        changedItemIds: [String]?,
        suppressUndo: Bool = false,
    ) {
        if !suppressUndo {
            let undoOperation = ImageEditorOperation(contents: contents)
            undoStack.append(undoOperation)
            redoStack.removeAll()
        }

        let oldContents = self.contents
        let newContents = action(oldContents)
        contents = newContents

        if let changedItemIds {
            fireModelDidChange(changedItemIds: changedItemIds)
        } else {
            fireModelDidChange(
                before: oldContents,
                after: self.contents,
            )
        }
    }
}
