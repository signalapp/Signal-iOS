//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

    // Transparent view whose frame reflects the current state of cropping.
    // Size of `clipView` is defined by both transform (defines aspect ratio) and
    // layout guide that `clipView` is currently constrained to (defines position and max size).
    // `clipView` also serves as the reference view for gesture recognizers.
    private let clipView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.isOpaque = false
        return view
    }()
    // This constraint reflects current aspec ratio of the clip rectangle.
    // This constraint gets updated using values from `transform` whenever user makes changes.
    private var clipViewAspectRatioConstraint: NSLayoutConstraint?

    private lazy var imageView = UIImageView(image: previewImage)

    // The purpose of these two layout guides is to make animation of transition to/from crop view seamless.
    // Seamlessness is achieved when image center stays the same in both "review" and "crop" screens.
    // Two layout guides define size and position of the visible content:
    // `initialStateContentLayoutGuide` designed to position content exacty as in `AttachmentPrepContentView`.
    // `finalStateContentLayoutGuide` has the same center that `initialStateContentLayoutGuide` has,
    // but with non-zero margins on the sides and its height sized to clear rotation control at the bottom.
    // When VC's view appears on the screen initially (with no animation) content is constrained to `initialStateContentLayoutGuide`.
    // Once view is visible content  is resized with animation to match `finalStateContentLayoutGuide`.
    private let initialStateContentLayoutGuide = UILayoutGuide()
    private let finalStateContentLayoutGuide = UILayoutGuide()
    // Constraints between `clipView` and one of the layout guides from above.
    // These constraints are updated when UI is switched from `initial` to `final` and vice versa
    // during present / dismiss animations.
    private var contentLayoutGuideConstraints = [NSLayoutConstraint]()

    // Full-screen view that serves purely as indication of current crop rectangle.
    // This view displays crop handles and grid and also dims cropped content.
    private let cropView = CropView(frame: UIScreen.main.bounds)
    // These insets control position of the visible crop frame within `clipView` via a set of four layout constraints below.
    // Insets are non-zero only temporarily:
    // • when user is resizing crop rectangle using crop handles.
    // • when animating change to a predefined aspect ratio.
    private var cropViewFrameInsets = UIEdgeInsets.zero {
        didSet {
            cropViewFrameLeading.constant = cropViewFrameInsets.leading
            cropViewFrameTop.constant = cropViewFrameInsets.top
            cropViewFrameTrailing.constant = -cropViewFrameInsets.trailing
            cropViewFrameBottom.constant = -cropViewFrameInsets.bottom
        }
    }
    private lazy var cropViewFrameLeading = cropView.cropFrameLayoutGuide.leadingAnchor.constraint(equalTo: clipView.leadingAnchor,
                                                                                                   constant: cropViewFrameInsets.leading)
    private lazy var cropViewFrameTop = cropView.cropFrameLayoutGuide.topAnchor.constraint(equalTo: clipView.topAnchor,
                                                                                      constant: cropViewFrameInsets.top)
    private lazy var cropViewFrameTrailing = cropView.cropFrameLayoutGuide.trailingAnchor.constraint(equalTo: clipView.trailingAnchor,
                                                                                                constant: -cropViewFrameInsets.trailing)
    private lazy var cropViewFrameBottom = cropView.cropFrameLayoutGuide.bottomAnchor.constraint(equalTo: clipView.bottomAnchor,
                                                                                            constant: -cropViewFrameInsets.bottom)

    // Controls.
    private lazy var resetButton: UIButton = {
        let button = RoundMediaButton(image: nil, backgroundStyle: .blur)
        let buttonTitle = OWSLocalizedString("MEDIA_EDITOR_RESET", comment: "Title for the button that resets photo to its initial state.")
        button.setTitle(buttonTitle, for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(hMargin: 26, vMargin: 15) // Make button 36pts tall at default text size.
        button.addTarget(self, action: #selector(didTapReset), for: .touchUpInside)
        return button
    }()
    private lazy var footerView: UIView = {
        let footerView = UIView()
        footerView.preservesSuperviewLayoutMargins = true
        if UIDevice.current.hasIPhoneXNotch {
            // No additional bottom margin if there's non-zero safe area.
            footerView.layoutMargins.bottom = 0
        }

        footerView.addSubview(rotationControl)
        rotationControl.autoPinTopToSuperviewMargin()
        rotationControl.autoHCenterInSuperview()
        rotationControl.autoPinEdge(.leading, to: .leading, of: footerView, withOffset: 0, relation: .greaterThanOrEqual)

        footerView.addSubview(bottomBar)
        bottomBar.autoPinWidthToSuperview()
        bottomBar.autoPinEdge(toSuperviewEdge: .bottom)
        bottomBar.autoPinEdge(.top, to: .bottom, of: rotationControl, withOffset: 18)

        return footerView
    }()
    private lazy var rotationControl = RotationControl()
    private lazy var bottomBar: ImageEditorBottomBar = {
        let bottomBar = ImageEditorBottomBar(buttonProvider: self)
        bottomBar.cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
        bottomBar.doneButton.addTarget(self, action: #selector(didTapDone), for: .touchUpInside)
        return bottomBar
    }()

    init(model: ImageEditorModel, srcImage: UIImage, previewImage: UIImage) {
        self.model = model
        self.srcImage = srcImage
        self.previewImage = previewImage
        self.transform = model.currentTransform()

        super.init()
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        view.backgroundColor = .black

        // MARK: - Clip view & content.
        view.addSubview(clipView)
        updateClipViewAspectRatio()

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.masksToBounds = true
        view.addSubview(imageView)
        // Image view is always co-centered with the clip view,
        // has aspect ratio of the image it displays and resized to fit current
        // content layout guide's frame (just like the clip view).
        // Everything user does to an image is applied as `UIView.transform` in `updateImageViewTransform`.
        let imageAspectRatio = previewImage.size.width / previewImage.size.height
        view.addConstraints([
            imageView.centerXAnchor.constraint(equalTo: clipView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: clipView.centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: imageAspectRatio)
        ])

        // MARK: - Crop frame
        view.addSubview(cropView)
        cropView.autoPinEdgesToSuperviewEdges()

        // Visible crop frame is constrained to clipView using auto layout.
        view.addConstraints([ cropViewFrameLeading, cropViewFrameTop, cropViewFrameTrailing, cropViewFrameBottom ])

        // MARK: - Footer
        view.addSubview(footerView)
        footerView.autoPinWidthToSuperview()
        footerView.autoPinEdge(toSuperviewEdge: .bottom)
        setupRotationControlActions()

        // MARK: - Layout guides for clip view
        initialStateContentLayoutGuide.identifier = "Content - Initial State"
        view.addLayoutGuide(initialStateContentLayoutGuide)
        let topConstraint: NSLayoutConstraint = {
            if UIDevice.current.hasIPhoneXNotch {
                return initialStateContentLayoutGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
            } else {
                return initialStateContentLayoutGuide.topAnchor.constraint(equalTo: view.topAnchor)
            }
        }()
        view.addConstraints([
            topConstraint,
            initialStateContentLayoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            initialStateContentLayoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            initialStateContentLayoutGuide.bottomAnchor.constraint(equalTo: bottomBar.topAnchor) ])

        finalStateContentLayoutGuide.identifier = "Content - Final State"
        view.addLayoutGuide(finalStateContentLayoutGuide)
        view.addConstraints([
            finalStateContentLayoutGuide.centerYAnchor.constraint(equalTo: initialStateContentLayoutGuide.centerYAnchor),
            finalStateContentLayoutGuide.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            finalStateContentLayoutGuide.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            finalStateContentLayoutGuide.bottomAnchor.constraint(equalTo: footerView.topAnchor) ])

        // MARK: - Reset Button
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        let mediaTopBar = MediaTopBar()
        mediaTopBar.addSubview(resetButton)
        mediaTopBar.addConstraints([ resetButton.topAnchor.constraint(equalTo: mediaTopBar.controlsLayoutGuide.topAnchor),
                                     resetButton.trailingAnchor.constraint(equalTo: mediaTopBar.controlsLayoutGuide.trailingAnchor),
                                     resetButton.bottomAnchor.constraint(equalTo: mediaTopBar.controlsLayoutGuide.bottomAnchor) ])
        mediaTopBar.install(in: view)
        updateResetButtonAppearance(animated: false)

        transitionUI(toState: .initial, animated: false)

        configureGestureRecognizers()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        transitionUI(toState: .final, animated: true)
    }

    public override var prefersStatusBarHidden: Bool {
        !UIDevice.current.hasIPhoneXNotch && !UIDevice.current.isIPad && !CurrentAppContext().hasActiveCall
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - Layout

    private func updateResetButtonAppearance(animated: Bool) {
        if transform.isNonDefault {
            resetButton.setIsHidden(false, animated: animated)
            return
        }
        // Transform might still report as `default` after cropping using pre-selected choices.
        let imageAspectRatio = srcImage.pixelSize.width / srcImage.pixelSize.height
        let cropRectAspectRation = transform.outputSizePixels.width / transform.outputSizePixels.height
        let hasChanges = abs(imageAspectRatio - cropRectAspectRation) > 0.005
        resetButton.setIsHidden(!hasChanges, animated: animated)
    }

    private func constrainContent(to layoutGuide: UILayoutGuide) {
        view.removeConstraints(contentLayoutGuideConstraints)

        var constraints = [NSLayoutConstraint]()

        // Center in the layout guide's frame.
        constraints.append(clipView.centerXAnchor.constraint(equalTo: layoutGuide.centerXAnchor))
        constraints.append(clipView.centerYAnchor.constraint(equalTo: layoutGuide.centerYAnchor))

        // Constrain width and height to be within layout guide's frame.
        constraints.append(clipView.widthAnchor.constraint(lessThanOrEqualTo: layoutGuide.widthAnchor))
        constraints.append(clipView.heightAnchor.constraint(lessThanOrEqualTo: layoutGuide.heightAnchor))

        // Constrain width and height to take as much space as possible.
        constraints.append(contentsOf: { () -> [NSLayoutConstraint] in
            let c1 = clipView.widthAnchor.constraint(equalTo: layoutGuide.widthAnchor)
            c1.priority = .defaultHigh
            let c2 = clipView.heightAnchor.constraint(equalTo: layoutGuide.heightAnchor)
            c2.priority = .defaultHigh
            return [ c1, c2 ]
        }())

        // Constrain image view to fit the current layout guide's frame.
        // Note that imageView isn't constrained to clipView (except for the center)
        // so that model's transform can easily be applied to imageView.
        constraints.append(imageView.widthAnchor.constraint(lessThanOrEqualTo: layoutGuide.widthAnchor))
        constraints.append(imageView.heightAnchor.constraint(lessThanOrEqualTo: layoutGuide.heightAnchor))

        view.addConstraints(constraints)
        contentLayoutGuideConstraints = constraints
    }

    private func updateClipViewAspectRatio() {
        // The only thing about clipView that changes as user performs crop/rotate operations
        // is clipView's aspect ratio, which is defined by the current transform.
        //
        // Constraint needs to be re-created because NSLayoutConstraint.multiplier is read-only.
        if let clipViewAspectRatioConstraint = clipViewAspectRatioConstraint {
            view.removeConstraint(clipViewAspectRatioConstraint)
        }
        let aspectRatio = transform.outputSizePixels

        let constraint = clipView.widthAnchor.constraint(equalTo: clipView.heightAnchor, multiplier: aspectRatio.width / aspectRatio.height)
        view.addConstraint(constraint)
        clipViewAspectRatioConstraint = constraint
    }

    private func applyTransformWithoutAnimation(_ transform: ImageEditorTransform) {
        self.transform = transform

        if !rotationControl.isTracking {
            rotationControl.angle = transform.rotationRadians.radiansToDegrees
        }

        UIView.performWithoutAnimation {
            updateClipViewAspectRatio()
            resetCropFrameInsets()
            updateImageViewTransform()
        }
    }

    private func applyTransformWithAnimation(_ transform: ImageEditorTransform, completion: ((Bool) -> Void)? = nil) {
        self.transform = transform

        if !rotationControl.isTracking {
            rotationControl.angle = transform.rotationRadians.radiansToDegrees
        }

        UIView.animate(withDuration: 0.25,
                       animations: {
            self.updateClipViewAspectRatio()
            self.resetCropFrameInsets()
            self.updateImageViewTransform()
            self.updateResetButtonAppearance(animated: false)
        }, completion: completion)
    }

    private func applyTransformHidingCropFrame(_ transform: ImageEditorTransform) {
        cropView.setIsHidden(true, animated: true) { _ in
            self.applyTransformWithAnimation(transform) { _ in
                self.updateResetButtonAppearance(animated: true)
                self.cropView.setIsHidden(false, animated: true)
            }
        }
    }

    private func updateImageViewTransform() {
        // Force all pendging layouts to be done now because we're grabbing the size of `clipView`.
        view.layoutIfNeeded()

        let viewSize = clipView.bounds.size
        let imageSize = imageView.bounds.size

        guard viewSize.width > 0 && viewSize.height > 0 else { return }
        guard imageSize.width > 0 && imageSize.height > 0 else { return }

        // Re-use this method that calculates bounding box rect for image with transform applied to it.
        // We only need size of the result returned by this method.
        let transformedFrame = ImageEditorCanvasView.imageFrame(forViewSize: viewSize, imageSize: imageSize, transform: transform)

        // Apply additional scaling to the image so that there's no empty areas when rotation is non-zero.
        var scaleX = transformedFrame.width / imageSize.width
        // Flip if necessary.
        if transform.isFlipped {
            scaleX *= -1
        }
        let scaleY = transformedFrame.height / imageSize.height

        let imageTransform = transform.affineTransform(viewSize: viewSize)
        imageView.transform = imageTransform.scaledBy(x: scaleX, y: scaleY)
    }

    // MARK: - Crop Frame

    private func setCropFrameInsets(fromClipViewRect rect: CGRect) {
        var insets = UIEdgeInsets.zero
        insets.left = rect.minX
        insets.top = rect.minY
        insets.right = clipView.bounds.maxX - rect.maxX
        insets.bottom = clipView.bounds.maxY - rect.maxY
        cropViewFrameInsets = insets
    }

    private func resetCropFrameInsets() {
        cropViewFrameInsets = .zero
    }

    private var setGridHiddenTimer: Timer?

    private func setCropFrameGridLines(hidden: Bool, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        if let timer = setGridHiddenTimer {
            timer.invalidate()
            setGridHiddenTimer = nil
        }

        cropView.setState(hidden ? .normal : .resizing, animated: animated, completion: completion)
    }

    private func setCropFrameGridLines(hidden: Bool, animated: Bool, afterDelay delay: TimeInterval) {
        guard delay > 0 else {
            setCropFrameGridLines(hidden: hidden, animated: animated)
            return
        }

        if let timer = setGridHiddenTimer {
            timer.invalidate()
            setGridHiddenTimer = nil
        }

        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.setCropFrameGridLines(hidden: hidden, animated: animated)
        }
        setGridHiddenTimer = timer
    }

    // MARK: - Present/dismiss animations

    private enum UIState {
        case initial
        case final
    }

    private func transitionUI(toState state: UIState, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        let layoutGuide: UILayoutGuide = {
            switch state {
            case .initial: return initialStateContentLayoutGuide
            case .final: return finalStateContentLayoutGuide
            }
        }()

        let hideControls = state == .initial
        let setControlsHiddenBlock = {
            let alpha: CGFloat = hideControls ? 0 : 1
            self.footerView.alpha = alpha
            self.cropView.setState(state == .initial ? .initial : .normal, animated: false)
            self.bottomBar.setControls(hidden: hideControls)
        }

        let animationDuration: TimeInterval = 0.15

        let imageCornerRadius: CGFloat = state == .initial ? ImageEditorView.defaultCornerRadius : 0
        if animated {
            let animation = CABasicAnimation(keyPath: #keyPath(CALayer.cornerRadius))
            animation.fromValue = imageView.layer.cornerRadius
            animation.toValue = imageCornerRadius
            animation.duration = animationDuration
            imageView.layer.add(animation, forKey: "cornerRadius")
        }
        imageView.layer.cornerRadius = imageCornerRadius

        if animated {
            UIView.animate(withDuration: animationDuration,
                           animations: {
                setControlsHiddenBlock()
                self.constrainContent(to: layoutGuide)
                self.updateImageViewTransform()
                // Animate layout changes made within bottomBar.setControls(hidden:).
                self.view.setNeedsDisplay()
                self.view.layoutIfNeeded()
            },
                           completion: completion)
        } else {
            setControlsHiddenBlock()
            constrainContent(to: layoutGuide)
            updateImageViewTransform()
            completion?(true)
        }
    }

    // MARK: - Gestures

    private func configureGestureRecognizers() {
        let pinchGestureRecognizer = ImageEditorPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        pinchGestureRecognizer.referenceView = clipView
        // Use this VC as a delegate to ensure that pinches only
        // receive touches that start inside of the cropped image bounds.
        pinchGestureRecognizer.delegate = self
        view.addGestureRecognizer(pinchGestureRecognizer)

        let panGestureRecognizer = ImageEditorPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer.maximumNumberOfTouches = 1
        panGestureRecognizer.referenceView = clipView
        // _DO NOT_ use this VC as a delegate to filter touches;
        // pan gestures can start outside the cropped image bounds.
        // Otherwise the edges of the crop rect are difficult to
        // "grab".
        view.addGestureRecognizer(panGestureRecognizer)

        // De-conflict the gestures; the pan gesture has priority.
        panGestureRecognizer.shouldBeRequiredToFail(by: pinchGestureRecognizer)
    }

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

        switch gestureRecognizer.state {
        case .began:
            gestureStartTransform = transform

        case .changed, .ended:
            guard let gestureStartTransform = gestureStartTransform else {
                owsFailDebug("Missing pinchTransform.")
                return
            }

            let unitTranslation =
            ImageEditorCropViewController.unitTranslation(oldLocationView: gestureRecognizer.pinchStateStart.centroid,
                                                          newLocationView: gestureRecognizer.pinchStateLast.centroid,
                                                          viewBounds: clipView.bounds,
                                                          oldTransform: gestureStartTransform)

            // NOTE: We use max(1, ...) to avoid divide-by-zero.
            let scaling = gestureStartTransform.scaling * gestureRecognizer.pinchStateLast.distance / max(1.0, gestureRecognizer.pinchStateStart.distance)
            let clampedScaling = scaling.clamp(ImageEditorTextItem.kMinScaling, ImageEditorTextItem.kMaxScaling)

            let newTransform = ImageEditorTransform(outputSizePixels: gestureStartTransform.outputSizePixels,
                                                    unitTranslation: unitTranslation,
                                                    rotationRadians: gestureStartTransform.rotationRadians,
                                                    scaling: clampedScaling,
                                                    isFlipped: gestureStartTransform.isFlipped)
            applyTransformWithoutAnimation(newTransform.normalize(srcImageSizePixels: model.srcImageSizePixels))
            updateResetButtonAppearance(animated: true)

        default:
            break
        }

        // Show grid lines immediately when gesture starts and hide with a small delay after gesture ends.
        switch gestureRecognizer.state {
        case .began:
            setCropFrameGridLines(hidden: false, animated: true)

        case .ended, .cancelled:
            setCropFrameGridLines(hidden: true, animated: true, afterDelay: 0.5)

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
            panCropRegion = nil

        default:
            break
        }

        // Show grid lines immediately when gesture starts and hide with a small delay after gesture ends.
        switch gestureRecognizer.state {
        case .began:
            setCropFrameGridLines(hidden: false, animated: true)

        case .ended, .cancelled:
            setCropFrameGridLines(hidden: true, animated: true, afterDelay: 0.5)

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
        let locationNow = gestureRecognizer.location(in: clipView)

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

        setCropFrameInsets(fromClipViewRect: cropRectangleNow)

        switch gestureRecognizer.state {
        case .ended:
            crop(toRect: cropRectangleNow, animated: true)

        default:
            break
        }
    }

    private func crop(toRect cropRect: CGRect, animated: Bool) {
        let viewBounds = clipView.bounds

        // TODO: The output size should be rounded, although this can cause crop to be slightly not WYSIWYG.
        let croppedOutputSizePixels = CGSizeRound(CGSize(width: transform.outputSizePixels.width * cropRect.width / viewBounds.width,
                                                         height: transform.outputSizePixels.height * cropRect.height / viewBounds.height))

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

        let newTransform = ImageEditorTransform(outputSizePixels: croppedOutputSizePixels,
                                                unitTranslation: unitTranslation,
                                                rotationRadians: transform.rotationRadians,
                                                scaling: scaling,
                                                isFlipped: transform.isFlipped)
        applyTransformWithAnimation(newTransform.normalize(srcImageSizePixels: model.srcImageSizePixels))
    }

    private func handleNormalPanGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer) {
        AssertIsOnMainThread()

        guard let gestureStartTransform = gestureStartTransform else {
            owsFailDebug("Missing pinchTransform.")
            return
        }
        guard let startLocation = gestureRecognizer.locationFirst else {
            owsFailDebug("Missing locationStart.")
            return
        }

        let currentLocation = gestureRecognizer.location(in: clipView)
        let unitTranslation = ImageEditorCropViewController.unitTranslation(oldLocationView: startLocation,
                                                                            newLocationView: currentLocation,
                                                                            viewBounds: clipView.bounds,
                                                                            oldTransform: gestureStartTransform)

        let newTransform = ImageEditorTransform(outputSizePixels: gestureStartTransform.outputSizePixels,
                                                unitTranslation: unitTranslation,
                                                rotationRadians: gestureStartTransform.rotationRadians,
                                                scaling: gestureStartTransform.scaling,
                                                isFlipped: gestureStartTransform.isFlipped)

        applyTransformWithoutAnimation(newTransform.normalize(srcImageSizePixels: model.srcImageSizePixels))
        updateResetButtonAppearance(animated: true)
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

        // Resize crop frame first and then update everything else.
        UIView.animate(withDuration: 0.15) {
            self.setCropFrameInsets(fromClipViewRect: newCropRect)
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        } completion: { _ in
            // Looks better if there's a very slight delay in between animations.
            DispatchQueue.main.async {
                self.crop(toRect: newCropRect, animated: true)
            }
        }
    }
}

// MARK: - Events

extension ImageEditorCropViewController {

    @objc
    private func didTapCancel() {
        transitionUI(toState: .initial, animated: true) { finished in
            guard finished else { return }
            self.dismiss(animated: false)
        }
    }

    @objc
    private func didTapDone() {
        model.replace(transform: transform)
        transitionUI(toState: .initial, animated: true) { finished in
            guard finished else { return }
            self.dismiss(animated: false)
        }
    }

    @objc
    private func didTapRotateImage() {
        Logger.verbose("")

        let outputSizePixels = CGSize(width: transform.outputSizePixels.height, height: transform.outputSizePixels.width)
        let rotationRadians = transform.rotationRadians - CGFloat.pi / 2
        let newTransform = ImageEditorTransform(outputSizePixels: outputSizePixels,
                                                unitTranslation: transform.unitTranslation,
                                                rotationRadians: rotationRadians,
                                                scaling: transform.scaling,
                                                isFlipped: transform.isFlipped)
        applyTransformHidingCropFrame(newTransform.normalize(srcImageSizePixels: model.srcImageSizePixels))
    }

    @objc
    private func didTapFlipImage() {
        Logger.verbose("")

        let newTransform = ImageEditorTransform(outputSizePixels: transform.outputSizePixels,
                                                unitTranslation: transform.unitTranslation,
                                                rotationRadians: transform.rotationRadians,
                                                scaling: transform.scaling,
                                                isFlipped: !transform.isFlipped)
        applyTransformHidingCropFrame(newTransform.normalize(srcImageSizePixels: model.srcImageSizePixels))
    }

    @objc
    private func didTapReset() {
        Logger.verbose("")

        let newTransform = ImageEditorTransform.defaultTransform(srcImageSizePixels: model.srcImageSizePixels)
        applyTransformWithAnimation(newTransform)
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
        let newAngle = sender.angle.degreesToRadians
        let newTransform = ImageEditorTransform(outputSizePixels: transform.outputSizePixels,
                                                unitTranslation: transform.unitTranslation,
                                                rotationRadians: newAngle,
                                                scaling: transform.scaling,
                                                isFlipped: transform.isFlipped)
        applyTransformWithoutAnimation(newTransform.normalize(srcImageSizePixels: model.srcImageSizePixels))
        updateResetButtonAppearance(animated: true)
    }

    @objc
    private func rotationControlDidBeginEditing(_ sender: RotationControl) {
        setCropFrameGridLines(hidden: false, animated: true)
    }

    @objc
    private func rotationControlDidEndEditing(_ sender: RotationControl) {
        setCropFrameGridLines(hidden: true, animated: true, afterDelay: 0.2)
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
