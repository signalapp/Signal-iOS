//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

// The image editor uses multiple coordinate systems.
//
// * Image unit coordinates.  Brush stroke and text content should be pegged to
//   image content, so they are specified relative to the bounds of the image.
// * Canvas coordinates.  We render the image, strokes and text into the "canvas",
//   a viewport that has the aspect ratio of the view.  Rendering is transformed, so
//   this is pre-transform.
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

class ImageEditorTransform: NSObject {
    // The outputSizePixels is used to specify the aspect ratio and size of the
    // output.
    let outputSizePixels: CGSize
    // The unit translation of the content, relative to the
    // canvas viewport.
    let unitTranslation: CGPoint
    // Rotation about the center of the content.
    let rotationRadians: CGFloat
    // x >= 1.0.
    let scaling: CGFloat
    // Flipping is horizontal.
    let isFlipped: Bool

    init(outputSizePixels: CGSize,
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

    class func defaultTransform(srcImageSizePixels: CGSize) -> ImageEditorTransform {
        // It shouldn't be necessary normalize the default transform, but we do so to be safe.
        return ImageEditorTransform(outputSizePixels: srcImageSizePixels,
                                    unitTranslation: .zero,
                                    rotationRadians: 0.0,
                                    scaling: 1.0,
                                    isFlipped: false).normalize(srcImageSizePixels: srcImageSizePixels)
    }

    var isNonDefault: Bool {
        return !isEqual(ImageEditorTransform.defaultTransform(srcImageSizePixels: outputSizePixels))
    }

    func affineTransform(viewSize: CGSize) -> CGAffineTransform {
        let translation = unitTranslation.fromUnitCoordinates(viewSize: viewSize)
        // Order matters.  We need want SRT (scale-rotate-translate) ordering so that the translation
        // is not affected affected by the scaling or rotation, which should both be about the "origin"
        // (in this case the center of the content).
        //
        // NOTE: CGAffineTransform transforms are composed in reverse order.
        let transform = CGAffineTransform.identity.translate(translation).rotated(by: rotationRadians).scaledBy(x: scaling, y: scaling)
        return transform
    }

    func transform3D(viewSize: CGSize) -> CATransform3D {
        let translation = unitTranslation.fromUnitCoordinates(viewSize: viewSize)
        // Order matters.  We need want SRT (scale-rotate-translate) ordering so that the translation
        // is not affected affected by the scaling or rotation, which should both be about the "origin"
        // (in this case the center of the content).
        //
        // NOTE: CGAffineTransform transforms are composed in reverse order.
        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, translation.x, translation.y, 0)
        transform = CATransform3DRotate(transform, rotationRadians, 0, 0, 1)
        transform = CATransform3DScale(transform, scaling, scaling, 1)
        return transform
    }

    // This method normalizes a "proposed" transform (self) into
    // one that is guaranteed to be valid.
    func normalize(srcImageSizePixels: CGSize) -> ImageEditorTransform {
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
        var isFirstCorner = true
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
            if isFirstCorner {
                naiveViewportMinCanvas = naiveViewCornerInCanvas
                naiveViewportMaxCanvas = naiveViewCornerInCanvas
                isFirstCorner = false
            } else {
                naiveViewportMinCanvas = naiveViewportMinCanvas.min(naiveViewCornerInCanvas)
                naiveViewportMaxCanvas = naiveViewportMaxCanvas.max(naiveViewCornerInCanvas)
            }
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

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImageEditorTransform  else {
            return false
        }
        return (outputSizePixels == other.outputSizePixels &&
                unitTranslation == other.unitTranslation &&
                rotationRadians == other.rotationRadians &&
                scaling == other.scaling &&
                isFlipped == other.isFlipped)
    }

    override var hash: Int {
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
