//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import SignalCoreKit
import SignalServiceKit
import UIKit

private extension CGFloat {

    var degreesToRadians: CGFloat {
        return self / 180 * .pi
    }

    var radiansToDegrees: CGFloat {
        return self * 180 / .pi
    }
}

// MARK: -

// A view for editing text item in image editor.
class ImageEditorCropViewController: OWSViewController {

    private let model: ImageEditorModel

    private let srcImage: UIImage

    private let previewImage: UIImage

    private var transform: ImageEditorTransform

    let clipView = OWSLayerView()

    let contentAlignmentLayoutGuide = UILayoutGuide()

    let croppedContentView = OWSLayerView()
    let uncroppedContentView = UIView()

    private var imageLayer = CALayer()

    private let cropView = CropView(frame: UIScreen.main.bounds)
    private let rotationControl = RotationControl()

    private lazy var bottomBar = ImageEditorBottomBar(buttonProvider: self)

    // Holds both toolbar and rotation control.
    private let footerView = UIView()

    private var isGridHidden = true
    private var setGridHiddenTimer: Timer?

    init(model: ImageEditorModel, srcImage: UIImage, previewImage: UIImage) {
        self.model = model
        self.srcImage = srcImage
        self.previewImage = previewImage
        transform = model.currentTransform()

        super.init()
    }

    // MARK: - View Lifecycle

    private var resetButton: UIButton?

    override func loadView() {
        self.view = UIView()

        self.view.backgroundColor = .black
        self.view.layoutMargins = .zero

        // MARK: - Buttons

        let resetButtonTitle = OWSLocalizedString("MEDIA_EDITOR_RESET", comment: "Title for the button that resets photo to its initial state.")
        let resetButton = RoundMediaButton(image: nil, backgroundStyle: .blur)
        resetButton.setTitle(resetButtonTitle, for: .normal)
        resetButton.contentEdgeInsets = UIEdgeInsets(hMargin: 18, vMargin: 7) // Make button 36pts tall at default text size.
        resetButton.layoutMargins = .zero
        resetButton.addTarget(self, action: #selector(didTapReset), for: .touchUpInside)

        // MARK: - Canvas & Wrapper

        let wrapperView = UIView.container()
        wrapperView.isOpaque = false

        clipView.clipsToBounds = true
        clipView.isOpaque = false
        clipView.layoutCallback = { [weak self] (_) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updateCropViewLayout()
        }
        wrapperView.addSubview(clipView)
        clipView.setContentHuggingLow()

        croppedContentView.layoutCallback = { [weak self] (_) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updateContent()
        }
        clipView.addSubview(croppedContentView)
        croppedContentView.autoPinEdgesToSuperviewEdges()

        imageLayer.contents = previewImage.cgImage
        imageLayer.contentsScale = previewImage.scale
        uncroppedContentView.isOpaque = false
        uncroppedContentView.layer.addSublayer(imageLayer)
        wrapperView.addSubview(uncroppedContentView)
        uncroppedContentView.autoPin(toEdgesOf: croppedContentView)
        wrapperView.setContentHuggingLow()
        view.addSubview(wrapperView)

        // MARK: - Crop View

        cropView.setContentHuggingLow()
        cropView.setCompressionResistanceLow()
        view.addSubview(cropView)
        cropView.autoPinEdgesToSuperviewEdges()

        // MARK: - Footer

        footerView.addSubview(rotationControl)
        rotationControl.autoPinTopToSuperviewMargin()
        rotationControl.autoHCenterInSuperview()
        rotationControl.autoPinEdge(.leading, to: .leading, of: footerView, withOffset: 0, relation: .greaterThanOrEqual)

        bottomBar.cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
        bottomBar.doneButton.addTarget(self, action: #selector(didTapDone), for: .touchUpInside)
        footerView.addSubview(bottomBar)
        bottomBar.autoPinWidthToSuperview()
        bottomBar.autoPinEdge(toSuperviewEdge: .bottom)
        bottomBar.autoPinEdge(.top, to: .bottom, of: rotationControl, withOffset: 18)

        footerView.preservesSuperviewLayoutMargins = true
        view.addSubview(footerView)
        footerView.autoPinWidthToSuperview()
        footerView.autoPinEdge(toSuperviewEdge: .bottom)

        // MARK: - Content Layout Guide
        // The purpose of this layout logic is to make animation of transition to/from crop view seamless.
        // Seamlessness is achieved when image center stays the same in both "review" and "crop" screens.
        // This is why `contentAlignmentLayoutGuide` is constructed to copy `AttachmentPrepContentView.contentLayoutGuide`,
        // which defines image size and position in "review" screen.
        //
        // Top of the `contentAlignmentLayoutGuide` is constrained using logic
        // from `AttachmentApprovalViewController.updateContentLayoutMargins(for:)`.
        //
        // Bottom of the `contentAlignmentLayoutGuide` is constrained to the top of the `bottomBar`,
        // not `footerView` (which includes rotation control). This works because bottom content layout margin
        // in `AttachmentPrepContentView` is calculated as the height of ImageEditorBottomBar (same as `bottomBar` in this VC).
        view.addLayoutGuide(contentAlignmentLayoutGuide)
        if UIDevice.current.hasIPhoneXNotch {
            view.addConstraint(contentAlignmentLayoutGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor))
        } else {
            view.addConstraint(contentAlignmentLayoutGuide.topAnchor.constraint(equalTo: view.topAnchor))
        }
        view.addConstraint(contentAlignmentLayoutGuide.bottomAnchor.constraint(equalTo: bottomBar.topAnchor))
        view.addConstraints([
            contentAlignmentLayoutGuide.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            contentAlignmentLayoutGuide.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor) ])

        wrapperView.autoPinEdge(.bottom, to: .top, of: footerView, withOffset: 0, relation: .lessThanOrEqual)
        view.addConstraints([
            wrapperView.leadingAnchor.constraint(equalTo: contentAlignmentLayoutGuide.leadingAnchor),
            wrapperView.trailingAnchor.constraint(equalTo: contentAlignmentLayoutGuide.trailingAnchor),
            wrapperView.centerYAnchor.constraint(equalTo: contentAlignmentLayoutGuide.centerYAnchor) ])

        // MARK: - Reset Button
        view.addSubview(resetButton)
        resetButton.autoPinTopToSuperviewMargin()
        resetButton.autoPinTrailingToSuperviewMargin()
        self.resetButton = resetButton

        updateClipViewLayout()

        configureGestures()

        updateResetButtonAppearance()

        setupRotationControlActions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        setControls(hidden: true, animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        setControls(hidden: false, animated: true)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    private func updateResetButtonAppearance() {
        if transform.isNonDefault {
            resetButton?.isHidden = false
            return
        }
        // Transform might still report as `default` after cropping using pre-selected choices.
        let imageAspectRatio = srcImage.pixelSize.width / srcImage.pixelSize.height
        let cropRectAspectRation = transform.outputSizePixels.width / transform.outputSizePixels.height
        resetButton?.isHidden = abs(imageAspectRatio - cropRectAspectRation) < 0.005
    }

    private var clipViewConstraints = [NSLayoutConstraint]()

    private func updateClipViewLayout() {
        NSLayoutConstraint.deactivate(clipViewConstraints)
        clipViewConstraints = ImageEditorCanvasView.updateContentLayout(transform: transform,
                                                                        contentView: clipView)

        clipView.superview?.setNeedsLayout()
        clipView.superview?.layoutIfNeeded()
        updateCropViewLayout()
    }

    private func updateCropViewLayout() {
        cropView.updateLayout(using: clipView)
        if !isCropGestureActive {
            cropView.cropFrame = clipView.convert(clipView.bounds, to: cropView)
        }
        if !rotationControl.isTracking {
            rotationControl.angle = transform.rotationRadians.radiansToDegrees
        }
    }

    func updateContent() {
        AssertIsOnMainThread()

        Logger.verbose("")

        let viewSize = croppedContentView.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else {
            return
        }

        updateTransform(transform)
    }

    private func updateTransform(_ transform: ImageEditorTransform, animated: Bool = false) {
        self.transform = transform

        CATransaction.begin()
        if animated {
            // Note that animation duration is longer than crop fade-in/fade-out animation.
            // The animation sequence is:
            // • quickly hide crop frame
            // • apply image transform
            // • quickly show crop frame.
            CATransaction.setAnimationDuration(0.3)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            CATransaction.setCompletionBlock {
                UIView.animate(withDuration: 0.1) {
                    self.cropView.alpha = 1
                    self.updateResetButtonAppearance()
                }
            }
        } else {
            CATransaction.setDisableActions(true)
        }

        applyTransform(animated: animated)

        if animated {
            // Fade out the crop frame and update it's shape/position
            // while the crop frame is not visible.
            // Once image transform animation completes the crop frame will be
            // shown in its final position.
            UIView.animate(withDuration: 0.1,
                           animations: {
                self.cropView.alpha = 0
            },
                           completion: { _ in
                self.updateClipViewLayout()
            })
        } else {
            updateClipViewLayout()
            updateResetButtonAppearance()
        }

        updateImageLayer()

        CATransaction.commit()
    }

    private func applyTransform(animated: Bool) {
        let viewSize = croppedContentView.bounds.size
        let newTransform = transform.transform3D(viewSize: viewSize)

        var animation: CABasicAnimation?
        if animated {
            animation = CABasicAnimation()
            animation?.fromValue = croppedContentView.layer.transform // always the same as `uncroppedContentView.layer.transform`
            animation?.toValue = newTransform
        }

        croppedContentView.layer.transform = newTransform
        uncroppedContentView.layer.transform = newTransform

        if let animation = animation {
            croppedContentView.layer.add(animation, forKey: #keyPath(CALayer.transform))
            uncroppedContentView.layer.add(animation, forKey: #keyPath(CALayer.transform))
        }
    }

    private func updateImageLayer() {
        let viewSize = croppedContentView.bounds.size
        ImageEditorCanvasView.updateImageLayer(imageLayer: imageLayer, viewSize: viewSize, imageSize: model.srcImageSizePixels, transform: transform)
    }

    private func configureGestures() {
        self.view.isUserInteractionEnabled = true

        let pinchGestureRecognizer = ImageEditorPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        pinchGestureRecognizer.referenceView = self.clipView
        // Use this VC as a delegate to ensure that pinches only
        // receive touches that start inside of the cropped image bounds.
        pinchGestureRecognizer.delegate = self
        view.addGestureRecognizer(pinchGestureRecognizer)

        let panGestureRecognizer = ImageEditorPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer.maximumNumberOfTouches = 1
        panGestureRecognizer.referenceView = self.clipView
        // _DO NOT_ use this VC as a delegate to filter touches;
        // pan gestures can start outside the cropped image bounds.
        // Otherwise the edges of the crop rect are difficult to
        // "grab".
        view.addGestureRecognizer(panGestureRecognizer)

        // De-conflict the gestures; the pan gesture has priority.
        panGestureRecognizer.shouldBeRequiredToFail(by: pinchGestureRecognizer)
    }

    private func setControls(hidden: Bool, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        if animated {
            UIView.animate(withDuration: 0.15,
                           animations: {
                self.setControls(hidden: hidden)

                // Animate layout changes made within bottomBar.setControls(hidden:).
                self.bottomBar.setNeedsDisplay()
                self.bottomBar.layoutIfNeeded()
            },
                           completion: completion)
        } else {
            setControls(hidden: hidden)
            if let completion = completion {
                completion(true)
            }
        }
    }

    private func setControls(hidden: Bool) {
        let alpha: CGFloat = hidden ? 0 : 1
        footerView.alpha = alpha
        bottomBar.setControls(hidden: hidden)
    }

    // MARK: - Gestures

    private class func unitTranslation(oldLocationView: CGPoint,
                                       newLocationView: CGPoint,
                                       viewBounds: CGRect,
                                       oldTransform: ImageEditorTransform) -> CGPoint {

        // The beauty of using an SRT (scale-rotate-translation) transform ordering
        // is that the translation is applied last, so it's trivial to convert
        // translations from view coordinates to transform translation.
        // Our (view bounds == canvas bounds) so no need to convert.
        let translation = newLocationView.minus(oldLocationView)
        let translationUnit = translation.toUnitCoordinates(viewSize: viewBounds.size, shouldClamp: false)
        let newUnitTranslation = oldTransform.unitTranslation.plus(translationUnit)
        return newUnitTranslation
    }

    // MARK: - Pinch Gesture

    @objc
    private func handlePinchGesture(_ gestureRecognizer: ImageEditorPinchGestureRecognizer) {
        AssertIsOnMainThread()

        Logger.verbose("")

        // We could undo an in-progress pinch if the gesture is cancelled, but it seems gratuitous.

        switch gestureRecognizer.state {
        case .began:
            gestureStartTransform = transform
        case .changed, .ended:
            guard let gestureStartTransform = gestureStartTransform else {
                owsFailDebug("Missing pinchTransform.")
                return
            }

            let newUnitTranslation = ImageEditorCropViewController.unitTranslation(oldLocationView: gestureRecognizer.pinchStateStart.centroid,
                                                                                   newLocationView: gestureRecognizer.pinchStateLast.centroid,
                                                                                   viewBounds: clipView.bounds,
                                                                                   oldTransform: gestureStartTransform)

            var newRotationRadians = gestureStartTransform.rotationRadians + gestureRecognizer.pinchStateLast.angleRadians - gestureRecognizer.pinchStateStart.angleRadians
            // Convert to degrees and back to avoid any rounding issues.
            let newRotationDegrees = newRotationRadians.radiansToDegrees.clamp(-45, 45)
            newRotationRadians = newRotationDegrees.degreesToRadians

            // NOTE: We use max(1, ...) to avoid divide-by-zero.
            //
            // TODO: The clamp limits are wrong.
            let newScaling = CGFloatClamp(gestureStartTransform.scaling * gestureRecognizer.pinchStateLast.distance / max(1.0, gestureRecognizer.pinchStateStart.distance),
                                          ImageEditorTextItem.kMinScaling,
                                          ImageEditorTextItem.kMaxScaling)

            updateTransform(ImageEditorTransform(outputSizePixels: gestureStartTransform.outputSizePixels,
                                                 unitTranslation: newUnitTranslation,
                                                 rotationRadians: newRotationRadians,
                                                 scaling: newScaling,
                                                 isFlipped: gestureStartTransform.isFlipped).normalize(srcImageSizePixels: model.srcImageSizePixels))
        default:
            break
        }

        switch gestureRecognizer.state {
        case .began:
            setGridHidden(false, animated: true)

        case .ended, .cancelled:
            setGridHidden(true, animated: true, afterDelay: 0.5)

        default:
            break
        }
    }

    // MARK: - Pan Gesture

    private var gestureStartTransform: ImageEditorTransform?
    private var panCropRegion: CropRegion?
    private var isCropGestureActive: Bool {
        return panCropRegion != nil
    }

    @objc
    private func handlePanGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer) {
        AssertIsOnMainThread()

        // Ignore gestures that begin inside of the controls area at the bottom.
        // Upon cancellation gesture recognizer will send one last event with the state==.cancelled - should be ignored too.
        if footerView.point(inside: gestureRecognizer.location(in: footerView), with: nil) {
            switch gestureRecognizer.state {
            case .began:
                gestureRecognizer.isEnabled = false
                gestureRecognizer.isEnabled = true
                return

            case .cancelled:
                return

            default:
                break
            }
        }

        Logger.verbose("")

        // We could undo an in-progress pinch if the gesture is cancelled, but it seems gratuitous.

        // Handle the GR if necessary.
        switch gestureRecognizer.state {
        case .began:
            Logger.verbose("began: \(transform.unitTranslation)")
            gestureStartTransform = transform
            // Pans that start near the crop rectangle should be treated as crop gestures.
            panCropRegion = cropRegion(forGestureRecognizer: gestureRecognizer)
        case .changed, .ended:
            if let panCropRegion = panCropRegion {
                // Crop pan gesture
                handleCropPanGesture(gestureRecognizer, panCropRegion: panCropRegion)
            } else {
                handleNormalPanGesture(gestureRecognizer)
            }
        default:
            break
        }

        // Reset the GR if necessary.
        switch gestureRecognizer.state {
        case .ended, .failed, .cancelled, .possible:
            if panCropRegion != nil {
                panCropRegion = nil

                // Don't animate changes.
                CATransaction.begin()
                CATransaction.setDisableActions(true)

                updateCropViewLayout()

                CATransaction.commit()
            }
        default:
            break
        }

        // Show/hide grid lines.
        switch gestureRecognizer.state {
        case .began:
            setGridHidden(false, animated: true)

        case .ended, .cancelled:
            setGridHidden(true, animated: true, afterDelay: 0.5)

        default:
            break
        }
    }

    private func handleCropPanGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer,
                                      panCropRegion: CropRegion) {
        AssertIsOnMainThread()

        Logger.verbose("")

        guard let locationStart = gestureRecognizer.locationFirst else {
            owsFailDebug("Missing locationStart.")
            return
        }
        let locationNow = gestureRecognizer.location(in: self.clipView)

        // Crop pan gesture
        let locationDelta = CGPointSubtract(locationNow, locationStart)

        let cropRectangleStart = clipView.bounds
        var cropRectangleNow = cropRectangleStart

        // Derive the new crop rectangle.

        // We limit the crop rectangle's minimum size for two reasons.
        //
        // * To ensure that the crop rectangles "corner handles"
        //   can always be safely drawn.
        // * To avoid awkward interactions when the crop rectangle
        //   is very small.  Users can always crop multiple times.
        let maxDeltaX = cropRectangleNow.size.width - cropView.cornerSize.width * 2
        let maxDeltaY = cropRectangleNow.size.height - cropView.cornerSize.height * 2

        switch panCropRegion {
        case .left, .topLeft, .bottomLeft:
            let delta = min(maxDeltaX, max(0, locationDelta.x))
            cropRectangleNow.origin.x += delta
            cropRectangleNow.size.width -= delta
        case .right, .topRight, .bottomRight:
            let delta = min(maxDeltaX, max(0, -locationDelta.x))
            cropRectangleNow.size.width -= delta
        default:
            break
        }

        switch panCropRegion {
        case .top, .topLeft, .topRight:
            let delta = min(maxDeltaY, max(0, locationDelta.y))
            cropRectangleNow.origin.y += delta
            cropRectangleNow.size.height -= delta
        case .bottom, .bottomLeft, .bottomRight:
            let delta = min(maxDeltaY, max(0, -locationDelta.y))
            cropRectangleNow.size.height -= delta
        default:
            break
        }

        cropView.cropFrame = view.convert(cropRectangleNow, from: clipView)

        switch gestureRecognizer.state {
        case .ended:
            crop(toRect: cropRectangleNow)
        default:
            break
        }
    }

    private func crop(toRect cropRect: CGRect) {
        let viewBounds = clipView.bounds

        // TODO: The output size should be rounded, although this can
        //       cause crop to be slightly not WYSIWYG.
        let croppedOutputSizePixels = CGSizeRound(CGSize(width: transform.outputSizePixels.width * cropRect.width / clipView.width,
                                                         height: transform.outputSizePixels.height * cropRect.height / clipView.height))

        // We need to update the transform's unitTranslation and scaling properties
        // to reflect the crop.
        //
        // Cropping involves changing the output size AND aspect ratio.  The output aspect ratio
        // has complicated effects on the rendering behavior of the image background, since the
        // default rendering size of the image is an "aspect fill" of the output bounds.
        // Therefore, the simplest and more reliable way to update the scaling is to measure
        // the difference between the "before crop"/"after crop" image frames and adjust the
        // scaling accordingly.
        let naiveTransform = ImageEditorTransform(outputSizePixels: croppedOutputSizePixels,
                                                  unitTranslation: transform.unitTranslation,
                                                  rotationRadians: transform.rotationRadians,
                                                  scaling: transform.scaling,
                                                  isFlipped: transform.isFlipped)
        let naiveImageFrameOld = ImageEditorCanvasView.imageFrame(forViewSize: transform.outputSizePixels, imageSize: model.srcImageSizePixels, transform: naiveTransform)
        let naiveImageFrameNew = ImageEditorCanvasView.imageFrame(forViewSize: croppedOutputSizePixels, imageSize: model.srcImageSizePixels, transform: naiveTransform)
        let scalingDeltaX = naiveImageFrameNew.width / naiveImageFrameOld.width
        let scalingDeltaY = naiveImageFrameNew.height / naiveImageFrameOld.height
        // scalingDeltaX and scalingDeltaY should only differ by rounding error.
        let scalingDelta = (scalingDeltaX + scalingDeltaY) * 0.5
        let scaling = transform.scaling / scalingDelta

        // We also need to update the transform's translation, to ensure that the correct
        // content (background image and items) ends up in the crop region.
        //
        // To do this, we use the center of the image content.  Due to
        // scaling and rotation of the image content, it's far simpler to
        // use the center.
        let oldAffineTransform = transform.affineTransform(viewSize: viewBounds.size)
        // We determine the pre-crop render frame for the image.
        let oldImageFrameCanvas = ImageEditorCanvasView.imageFrame(forViewSize: viewBounds.size, imageSize: model.srcImageSizePixels, transform: transform)
        // We project it into pre-crop view coordinates (the coordinate
        // system of the crop rectangle).  Note that a CALayer's transform
        // is applied using its "anchor point", the center of the layer.
        // so we translate before and after the projection to be consistent.
        let oldImageCenterView = oldImageFrameCanvas.center.minus(viewBounds.center).applying(oldAffineTransform).plus(viewBounds.center)
        // We transform the "image content center" into the unit coordinates
        // of the crop rectangle.
        let newImageCenterUnit = oldImageCenterView.toUnitCoordinates(viewBounds: cropRect, shouldClamp: false)
        // The transform's "unit translation" represents a deviation from
        // the center of the output canvas, so we need to subtract the
        // unit midpoint.
        let unitTranslation = newImageCenterUnit.minus(CGPoint.unitMidpoint)

        // Clear the panCropRegion now so that the crop bounds are updated
        // immediately.
        panCropRegion = nil

        updateTransform(ImageEditorTransform(outputSizePixels: croppedOutputSizePixels,
                                             unitTranslation: unitTranslation,
                                             rotationRadians: transform.rotationRadians,
                                             scaling: scaling,
                                             isFlipped: transform.isFlipped).normalize(srcImageSizePixels: model.srcImageSizePixels))
    }

    private func handleNormalPanGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer) {
        AssertIsOnMainThread()

        guard let gestureStartTransform = gestureStartTransform else {
            owsFailDebug("Missing pinchTransform.")
            return
        }
        guard let oldLocationView = gestureRecognizer.locationFirst else {
            owsFailDebug("Missing locationStart.")
            return
        }

        let newLocationView = gestureRecognizer.location(in: self.clipView)
        let newUnitTranslation = ImageEditorCropViewController.unitTranslation(oldLocationView: oldLocationView,
                                                                               newLocationView: newLocationView,
                                                                               viewBounds: clipView.bounds,
                                                                               oldTransform: gestureStartTransform)

        updateTransform(ImageEditorTransform(outputSizePixels: gestureStartTransform.outputSizePixels,
                                             unitTranslation: newUnitTranslation,
                                             rotationRadians: gestureStartTransform.rotationRadians,
                                             scaling: gestureStartTransform.scaling,
                                             isFlipped: gestureStartTransform.isFlipped).normalize(srcImageSizePixels: model.srcImageSizePixels))
    }

    private func cropRegion(forGestureRecognizer gestureRecognizer: ImageEditorPanGestureRecognizer) -> CropRegion? {
        guard let location = gestureRecognizer.locationFirst else {
            owsFailDebug("Missing locationStart.")
            return nil
        }

        let tolerance: CGFloat = CropView.desiredCornerSize * 2.0
        let left = tolerance
        let top = tolerance
        let right = clipView.width - tolerance
        let bottom = clipView.height - tolerance

        // We could ignore touches far outside the crop rectangle.
        if location.x < left {
            if location.y < top {
                return .topLeft
            } else if location.y > bottom {
                return .bottomLeft
            } else {
                return .left
            }
        } else if location.x > right {
            if location.y < top {
                return .topRight
            } else if location.y > bottom {
                return .bottomRight
            } else {
                return .right
            }
        } else {
            if location.y < top {
                return .top
            } else if location.y > bottom {
                return .bottom
            } else {
                return nil
            }
        }
    }
}

// MARK: - ImageEditorBottomBarButtonProvider

extension ImageEditorCropViewController: ImageEditorBottomBarButtonProvider {

    var middleButtons: [UIButton] {
        let rotateButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-toolbar-rotate"), backgroundStyle: .none)
        rotateButton.addTarget(self, action: #selector(didTapRotateImage), for: .touchUpInside)

        let flipButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-toolbar-flip"), backgroundStyle: .none)
        flipButton.addTarget(self, action: #selector(didTapFlipImage), for: .touchUpInside)

        let aspectRatioButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-toolbar-aspect"), backgroundStyle: .none)
        aspectRatioButton.addTarget(self, action: #selector(didTapChooseAspectRatio), for: .touchUpInside)

        return [ rotateButton, flipButton, aspectRatioButton ]
    }
}

// MARK: - Grid

extension ImageEditorCropViewController {

    private func setGridHidden(_ hidden: Bool, animated: Bool) {
        if let timer = setGridHiddenTimer {
            timer.invalidate()
            setGridHiddenTimer = nil
        }
        isGridHidden = hidden
        cropView.setGrid(hidden: hidden, animated: animated)
    }

    private func setGridHidden(_ hidden: Bool, animated: Bool, afterDelay delay: TimeInterval) {
        guard delay > 0 else {
            setGridHidden(hidden, animated: animated)
            return
        }

        if let timer = setGridHiddenTimer {
            timer.invalidate()
            setGridHiddenTimer = nil
        }

        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.setGridHidden(hidden, animated: animated)
        }
        setGridHiddenTimer = timer
    }
}

// MARK: - Aspect Ratio

extension ImageEditorCropViewController {

    enum AspectRatio: CaseIterable {
        case original
        case square
        case fourByThree
        case threeByFour
        case sixteenByNine
        case nineBySixteen

        private static func aspectRatioXByYFormatString() -> String {
            return OWSLocalizedString("ASPECT_RATIO_X_BY_Y", comment: "Variable aspect ratio, eg 3:4. %1$@ and %2$@ are numbers.")
        }

        func localizedTitle() -> String {
            switch self {
            case .original:
                return OWSLocalizedString("ASPECT_RATIO_ORIGINAL", comment: "One of the choices for pre-defined aspect ratio of a photo in media editor.")
            case .square:
                return OWSLocalizedString("ASPECT_RATIO_SQUARE", comment: "One of the choices for pre-defined aspect ratio of a photo in media editor.")
            case .fourByThree:
                return String(format: AspectRatio.aspectRatioXByYFormatString(), OWSFormat.formatInt(4), OWSFormat.formatInt(3))
            case .threeByFour:
                return String(format: AspectRatio.aspectRatioXByYFormatString(), OWSFormat.formatInt(3), OWSFormat.formatInt(4))
            case .sixteenByNine:
                return String(format: AspectRatio.aspectRatioXByYFormatString(), OWSFormat.formatInt(16), OWSFormat.formatInt(9))
            case .nineBySixteen:
                return String(format: AspectRatio.aspectRatioXByYFormatString(), OWSFormat.formatInt(9), OWSFormat.formatInt(16))
            }
        }
    }

    private func isCurrentImageCompatibleWith(aspectRatio: AspectRatio) -> Bool {
        let currentAspectRatio = transform.outputSizePixels

        switch aspectRatio {
        case .original, .square:
            return true
        case .fourByThree, .sixteenByNine:
            return currentAspectRatio.width >= currentAspectRatio.height
        case .threeByFour, .nineBySixteen:
            return currentAspectRatio.height >= currentAspectRatio.width
        }
    }

    private func cropTo(aspectRatio: AspectRatio) {
        let imageSize = model.srcImageSizePixels
        let imageAspectRatio = imageSize.width / imageSize.height

        var currentCropRect = clipView.bounds
        var currentAspectRatio = currentCropRect.width / currentCropRect.height

        let aspectRatioEpsilon: CGFloat = 0.005

        // If image is already cropped we need to extend "source" cropping rect
        // to capture as much cropped content as possible.
        if currentAspectRatio - imageAspectRatio > aspectRatioEpsilon {
            // Image is cropped at top and bottom - extend source cropping frame vertically.
            let heightDiff = currentCropRect.height - currentCropRect.width / imageAspectRatio
            currentCropRect = currentCropRect.insetBy(dx: 0, dy: heightDiff/2)
        } else if imageAspectRatio - currentAspectRatio > aspectRatioEpsilon {
            // Image is cropped at left and right - extend source cropping frame horizontally.
            let widthDiff = currentCropRect.width - currentCropRect.height * imageAspectRatio
            currentCropRect = currentCropRect.insetBy(dx: widthDiff/2, dy: 0)
        }
        currentAspectRatio = currentCropRect.width / currentCropRect.height

        // Now resize the "source" cropping rectangle, which might be larger than
        // what actually is seen on the screen, to the new aspect ratio.
        let newAspectRatio: CGFloat = {
            switch aspectRatio {
            case .original:
                return imageAspectRatio

            case .square:
                return 1

            case .fourByThree:
                return 4/3

            case .threeByFour:
                return 3/4

            case .sixteenByNine:
                return 16/9

            case .nineBySixteen:
                return 9/16
            }
        }()
        var newCropRect: CGRect
        if newAspectRatio - currentAspectRatio > aspectRatioEpsilon {
            let heightDiff = currentCropRect.height - currentCropRect.width / newAspectRatio
            newCropRect = currentCropRect.insetBy(dx: 0, dy: heightDiff/2)
        } else if currentAspectRatio - newAspectRatio > aspectRatioEpsilon {
            let widthDiff = currentCropRect.width - currentCropRect.height * newAspectRatio
            newCropRect = currentCropRect.insetBy(dx: widthDiff/2, dy: 0)
        } else {
            newCropRect = currentCropRect
        }

        cropView.cropFrame = view.convert(newCropRect, from: clipView)
        crop(toRect: newCropRect)
        updateClipViewLayout()
        updateResetButtonAppearance()
    }
}

// MARK: - Events

extension ImageEditorCropViewController {

    @objc
    private func didTapCancel() {
        setControls(hidden: true, animated: true) { finished in
            guard finished else { return }
            self.dismiss(animated: false)
        }
    }

    @objc
    private func didTapDone() {
        model.replace(transform: transform)
        setControls(hidden: true, animated: true) { finished in
            guard finished else { return }
            self.dismiss(animated: false)
        }
    }

    @objc
    private func didTapRotateImage() {
        Logger.verbose("")
        // Invert width and height.
        let outputSizePixels = CGSize(width: transform.outputSizePixels.height, height: transform.outputSizePixels.width)
        let rotationAngle = -CGFloat.pi / 2
        let unitTranslation = transform.unitTranslation
        let rotationRadians = transform.rotationRadians + rotationAngle
        let scaling = transform.scaling
        updateTransform(ImageEditorTransform(outputSizePixels: outputSizePixels,
                                             unitTranslation: unitTranslation,
                                             rotationRadians: rotationRadians,
                                             scaling: scaling,
                                             isFlipped: transform.isFlipped).normalize(srcImageSizePixels: model.srcImageSizePixels),
                        animated: true)
    }

    @objc
    private func didTapFlipImage() {
        Logger.verbose("")
        updateTransform(ImageEditorTransform(outputSizePixels: transform.outputSizePixels,
                                             unitTranslation: transform.unitTranslation,
                                             rotationRadians: transform.rotationRadians,
                                             scaling: transform.scaling,
                                             isFlipped: !transform.isFlipped).normalize(srcImageSizePixels: model.srcImageSizePixels),
                        animated: true)
    }

    @objc
    private func didTapReset() {
        Logger.verbose("")
        updateTransform(ImageEditorTransform.defaultTransform(srcImageSizePixels: model.srcImageSizePixels), animated: true)
    }

    @objc
    private func didTapChooseAspectRatio() {
        let actionSheet = ActionSheetController(theme: .translucentDark)
        for aspectRatio in AspectRatio.allCases {
            guard isCurrentImageCompatibleWith(aspectRatio: aspectRatio) else { continue }
            actionSheet.addAction(
                ActionSheetAction(title: aspectRatio.localizedTitle(),
                                  style: .default,
                                  handler: { [weak self] _ in
                                      guard let self = self else { return }
                                      self.cropTo(aspectRatio: aspectRatio)
                                  }))
        }
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel))
        presentActionSheet(actionSheet)
    }
}

// MARK: - Rotation Control

extension ImageEditorCropViewController {

    private func setupRotationControlActions() {
        rotationControl.addTarget(self, action: #selector(rotationControlValueChanged), for: .valueChanged)
        rotationControl.addTarget(self, action: #selector(rotationControlDidBeginEditing), for: .editingDidBegin)
        rotationControl.addTarget(self, action: #selector(rotationControlDidEndEditing), for: .editingDidEnd)

    }

    @objc
    private func rotationControlValueChanged(_ sender: RotationControl) {
        let outputSizePixels = transform.outputSizePixels
        let unitTranslation = transform.unitTranslation
        let rotationRadians = sender.angle.degreesToRadians
        let scaling = transform.scaling
        updateTransform(ImageEditorTransform(outputSizePixels: outputSizePixels,
                                             unitTranslation: unitTranslation,
                                             rotationRadians: rotationRadians,
                                             scaling: scaling,
                                             isFlipped: transform.isFlipped).normalize(srcImageSizePixels: model.srcImageSizePixels))
    }

    @objc
    private func rotationControlDidBeginEditing(_ sender: RotationControl) {
        setGridHidden(false, animated: true)
    }

    @objc
    private func rotationControlDidEndEditing(_ sender: RotationControl) {
        setGridHidden(true, animated: true, afterDelay: 0.2)
    }
}

// MARK: -

extension ImageEditorCropViewController: UIGestureRecognizerDelegate {

    @objc
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Until the GR recognizes, it should only see touches that start within the content.
        guard gestureRecognizer.state == .possible else {
            return true
        }
        let location = touch.location(in: clipView)
        return clipView.bounds.contains(location)
    }
}
