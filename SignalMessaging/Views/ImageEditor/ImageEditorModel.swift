//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

// The image editor uses multiple coordinate systems.
//
// * Image unit coordinates.  Brush stroke and text content should be pegged to
//   image content, so they are specified relative to the bounds of the image.
// * Canvas coordinates.  We render the image, strokes and text into the "canvas",
//   a viewport that has the aspect ratio of the view.  Rendering is transformed, so
//   this is pre-tranform.
// * View coordinates.  The coordinates of the actual view (or rendered output).
//   Bounded by the view's bounds / viewport.
//
// Sometimes we use unit coordinates.  This facilitates a number of operations such
// as clamping to 0-1, etc.  So in practice almost all values will be in one of six
// coordinate systems:
//
// * unit image coordinates
// * image coordinates
// * unit canvas coordinates
// * canvas coordinates
// * unit view coordinates
// * view coordinates
//
// For simplicity, the canvas bounds are always identical to view bounds.
// If we wanted to manipulate output quality, we would use the layer's "scale".
// But canvas values are pre-transform and view values are post-transform so they
// are only identical if the transform has no scaling, rotation or translation.
//
// The "ImageEditorTransform" can be used to generate an CGAffineTransform
// for the layers used to render the content.  In practice, the affine transform
// is applied to a superlayer of the sublayers used to render content.
//
// CALayers apply their transform relative to the layer's anchorPoint, which
// by default is the center of the layer's bounds.  E.g. rotation occurs
// around the center of the layer.  Therefore when projecting absolute
// (but not relative) coordinates between the "view" and "canvas" coordinate
// systems, it's necessary to project them relative to the center of the
// view/canvas.
//
// To simplify our representation & operations, the default size of the image
// content is "exactly large enough to fill the canvas if rotation
// but not scaling or translation were applied".  This might seem unusual,
// but we have a key invariant: we always want the image to fill the canvas.
// It's far easier to ensure this if the transform is always (just barely)
// valid when scaling = 1 and translation = .zero.  The image size that
// fulfills this criteria is calculated using
// ImageEditorCanvasView.imageFrame(forViewSize:...).  Transforming between
// the "image" and "canvas" coordinate systems is done with that image frame.
@objc
public class ImageEditorTransform: NSObject {
    // The outputSizePixels is used to specify the aspect ratio and size of the
    // output.
    public let outputSizePixels: CGSize
    // The unit translation of the content, relative to the
    // canvas viewport.
    public let unitTranslation: CGPoint
    // Rotation about the center of the content.
    public let rotationRadians: CGFloat
    // x >= 1.0.
    public let scaling: CGFloat
    // Flipping is horizontal.
    public let isFlipped: Bool

    public init(outputSizePixels: CGSize,
                unitTranslation: CGPoint,
                rotationRadians: CGFloat,
                scaling: CGFloat,
                isFlipped: Bool) {
        self.outputSizePixels = outputSizePixels
        self.unitTranslation = unitTranslation
        self.rotationRadians = rotationRadians
        self.scaling = scaling
        self.isFlipped = isFlipped
    }

    public class func defaultTransform(srcImageSizePixels: CGSize) -> ImageEditorTransform {
        // It shouldn't be necessary normalize the default transform, but we do so to be safe.
        return ImageEditorTransform(outputSizePixels: srcImageSizePixels,
                                    unitTranslation: .zero,
                                    rotationRadians: 0.0,
                                    scaling: 1.0,
                                    isFlipped: false).normalize(srcImageSizePixels: srcImageSizePixels)
    }

    public var isNonDefault: Bool {
        return !isEqual(ImageEditorTransform.defaultTransform(srcImageSizePixels: outputSizePixels))
    }

    public func affineTransform(viewSize: CGSize) -> CGAffineTransform {
        let translation = unitTranslation.fromUnitCoordinates(viewSize: viewSize)
        // Order matters.  We need want SRT (scale-rotate-translate) ordering so that the translation
        // is not affected affected by the scaling or rotation, which shoud both be about the "origin"
        // (in this case the center of the content).
        //
        // NOTE: CGAffineTransform transforms are composed in reverse order.
        let transform = CGAffineTransform.identity.translate(translation).rotated(by: rotationRadians).scaledBy(x: scaling, y: scaling)
        return transform
    }

    // This method normalizes a "proposed" transform (self) into
    // one that is guaranteed to be valid.
    public func normalize(srcImageSizePixels: CGSize) -> ImageEditorTransform {
        // Normalize scaling.
        // The "src/background" image is rendered at a size that will fill
        // the canvas bounds if scaling = 1.0 and translation = .zero.
        // Therefore, any scaling >= 1.0 is valid.
        let minScaling: CGFloat = 1.0
        let scaling = max(minScaling, self.scaling)

        // We don't need to normalize rotation.

        // Normalize translation.
        //
        // This is decidedly non-trivial because of the way that
        // scaling, rotation and translation combine.  We need to
        // guarantee that the image _always_ fills the canvas
        // bounds.  So want to clamp the translation such that the
        // image can be moved _exactly_ to the edge of the canvas
        // and no further in a way that reflects the current
        // crop, scaling and rotation.
        //
        // We need to clamp the translation to the valid "translation
        // region" which is a rectangle centered on the origin.
        // However, this rectangle is axis-aligned in canvas
        // coordinates, not view coordinates.  e.g. if you have
        // a long image and a square output size, you could "slide"
        // the crop region along the image's contents.  That
        // movement would appear diagonal to the user in the view
        // but would be vertical on the canvas.

        // Normalize translation, Step 1:
        //
        // We project the viewport onto the canvas to determine
        // its bounding box.
        let viewBounds = CGRect(origin: .zero, size: self.outputSizePixels)
        // This "naive" transform represents the proposed transform
        // with no translation.
        let naiveTransform = ImageEditorTransform(outputSizePixels: outputSizePixels,
                                                  unitTranslation: .zero,
                                                  rotationRadians: rotationRadians,
                                                  scaling: scaling,
                                                  isFlipped: self.isFlipped)
        let naiveAffineTransform = naiveTransform.affineTransform(viewSize: viewBounds.size)
        var naiveViewportMinCanvas = CGPoint.zero
        var naiveViewportMaxCanvas = CGPoint.zero
        // Find the "naive" bounding box of the viewport on the canvas
        // by projecting its corners from view coordinates to canvas
        // coordinates.
        //
        // Due to symmetry, it should be sufficient to project 2 corners
        // but we do all four corners for safety.
        for viewCorner in [
            viewBounds.topLeft,
            viewBounds.topRight,
            viewBounds.bottomLeft,
            viewBounds.bottomRight
            ] {
                let naiveViewCornerInCanvas = viewCorner.minus(viewBounds.center).applyingInverse(naiveAffineTransform).plus(viewBounds.center)
                naiveViewportMinCanvas = naiveViewportMinCanvas.min(naiveViewCornerInCanvas)
                naiveViewportMaxCanvas = naiveViewportMaxCanvas.max(naiveViewCornerInCanvas)
        }
        let naiveViewportSizeCanvas: CGPoint = naiveViewportMaxCanvas.minus(naiveViewportMinCanvas)

        // Normalize translation, Step 2:
        //
        // Now determine the "naive" image frame on the canvas.
        let naiveImageFrameCanvas = ImageEditorCanvasView.imageFrame(forViewSize: viewBounds.size, imageSize: srcImageSizePixels, transform: naiveTransform)
        let naiveImageSizeCanvas = CGPoint(x: naiveImageFrameCanvas.width, y: naiveImageFrameCanvas.height)

        // Normalize translation, Step 3:
        //
        // The min/max translation can now by computed by diffing
        // the size of the bounding box of the naive viewport and
        // the size of the image on canvas.
        let maxTranslationCanvas = naiveImageSizeCanvas.minus(naiveViewportSizeCanvas).times(0.5).max(.zero)

        // Normalize translation, Step 4:
        //
        // Clamp the proposed translation to the "max translation"
        // from the last step.
        //
        // This is subtle.  We want to clamp in canvas coordinates
        // since the min/max translation is specified by a bounding
        // box in "unit canvas" coordinates.  However, because the
        // translation is applied in SRT order (scale-rotate-transform),
        // it effectively operates in view coordinates since it is
        // applied last.  So we project it from view coordinates
        // to canvas coordinates, clamp it, then project it back
        // into unit view coordinates using the "naive" (no translation)
        // transform.
        let translationInView = self.unitTranslation.fromUnitCoordinates(viewBounds: viewBounds)
        let translationInCanvas = translationInView.applyingInverse(naiveAffineTransform)
        // Clamp the translation to +/- maxTranslationCanvasUnit.
        let clampedTranslationInCanvas = translationInCanvas.min(maxTranslationCanvas).max(maxTranslationCanvas.inverse())
        let clampedTranslationInView = clampedTranslationInCanvas.applying(naiveAffineTransform)
        let unitTranslation = clampedTranslationInView.toUnitCoordinates(viewBounds: viewBounds, shouldClamp: false)

        return ImageEditorTransform(outputSizePixels: outputSizePixels,
                                    unitTranslation: unitTranslation,
                                    rotationRadians: rotationRadians,
                                    scaling: scaling,
                                    isFlipped: self.isFlipped)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImageEditorTransform  else {
            return false
        }
        return (outputSizePixels == other.outputSizePixels &&
            unitTranslation == other.unitTranslation &&
            rotationRadians == other.rotationRadians &&
            scaling == other.scaling &&
            isFlipped == other.isFlipped)
    }

    public override var hash: Int {
        return (outputSizePixels.width.hashValue ^
            outputSizePixels.height.hashValue ^
            unitTranslation.x.hashValue ^
            unitTranslation.y.hashValue ^
            rotationRadians.hashValue ^
            scaling.hashValue ^
            isFlipped.hashValue)
    }

    open override var description: String {
        return "[outputSizePixels: \(outputSizePixels), unitTranslation: \(unitTranslation), rotationRadians: \(rotationRadians), scaling: \(scaling), isFlipped: \(isFlipped)]"
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
    public static var isFeatureEnabled: Bool {
        return _isDebugAssertConfiguration()
    }

    @objc
    public let srcImagePath: String

    @objc
    public let srcImageSizePixels: CGSize

    private var contents: ImageEditorContents

    private var transform: ImageEditorTransform

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

        self.contents = ImageEditorContents()
        self.transform = ImageEditorTransform.defaultTransform(srcImageSizePixels: srcImageSizePixels)

        super.init()
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
