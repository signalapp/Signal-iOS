//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

public protocol ImageEditorCropViewControllerDelegate: class {
    func cropDidComplete(transform: ImageEditorTransform)
    func cropDidCancel()
}

// MARK: -

// A view for editing text item in image editor.
class ImageEditorCropViewController: OWSViewController {
    private weak var delegate: ImageEditorCropViewControllerDelegate?

    private let model: ImageEditorModel

    private let srcImage: UIImage

    private let previewImage: UIImage

    private var transform: ImageEditorTransform

    public let contentView = OWSLayerView()

    public let clipView = OWSLayerView()

    private var imageLayer = CALayer()

    private enum CropRegion {
        // The sides of the crop region.
        case left, right, top, bottom
        // The corners of the crop region.
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private class CropCornerView: UIView {
        let cropRegion: CropRegion

        init(cropRegion: CropRegion) {
            self.cropRegion = cropRegion
            super.init(frame: .zero)
        }

        @available(*, unavailable, message: "use other init() instead.")
        required public init?(coder aDecoder: NSCoder) {
            notImplemented()
        }
    }

    private let cropView = UIView()
    private let cropCornerViews: [CropCornerView] = [
        CropCornerView(cropRegion: .topLeft),
        CropCornerView(cropRegion: .topRight),
        CropCornerView(cropRegion: .bottomLeft),
        CropCornerView(cropRegion: .bottomRight)
    ]

    init(delegate: ImageEditorCropViewControllerDelegate,
         model: ImageEditorModel,
         srcImage: UIImage,
         previewImage: UIImage) {
        self.delegate = delegate
        self.model = model
        self.srcImage = srcImage
        self.previewImage = previewImage
        transform = model.currentTransform()

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - View Lifecycle

    override func loadView() {
        self.view = UIView()

        if (UIAccessibilityIsReduceTransparencyEnabled()) {
            self.view.backgroundColor = UIColor(white: 0.5, alpha: 0.5)
        } else {
            let alpha = OWSNavigationBar.backgroundBlurMutingFactor
            self.view.backgroundColor = UIColor(white: 0.5, alpha: alpha)

            let blurEffectView = UIVisualEffectView(effect: Theme.barBlurEffect)
            blurEffectView.layer.zPosition = -1
            self.view.addSubview(blurEffectView)
            blurEffectView.autoPinEdgesToSuperviewEdges()
        }

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 16
        stackView.layoutMargins = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stackView.isLayoutMarginsRelativeArrangement = true
        self.view.addSubview(stackView)
        stackView.ows_autoPinToSuperviewEdges()

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop,
                                                           target: self,
                                                           action: #selector(didTapBackButton))

        let wrapperView = UIView.container()
        wrapperView.backgroundColor = .clear
        wrapperView.isOpaque = false
        stackView.addArrangedSubview(wrapperView)

        // TODO: We could mask the clipped region with a semi-transparent overlay like WA.
        clipView.clipsToBounds = true
        clipView.backgroundColor = .clear
        clipView.isOpaque = false
        clipView.layoutCallback = { [weak self] (_) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updateCropViewLayout()
        }
        wrapperView.addSubview(clipView)

        imageLayer.contents = previewImage.cgImage
        imageLayer.contentsScale = previewImage.scale
        contentView.backgroundColor = .clear
        contentView.isOpaque = false
        contentView.layer.addSublayer(imageLayer)
        contentView.layoutCallback = { [weak self] (_) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updateContent()
        }
        clipView.addSubview(contentView)
        contentView.ows_autoPinToSuperviewEdges()

        let rotate90Button = OWSButton()
        rotate90Button.setTitle(NSLocalizedString("IMAGE_EDITOR_ROTATE_90_BUTTON", comment: "Label for button that rotates image 90 degrees."),
                                for: .normal)
        rotate90Button.block = { [weak self] in
            self?.rotate90ButtonPressed()
        }

        let rotate45Button = OWSButton()
        rotate45Button.setTitle(NSLocalizedString("IMAGE_EDITOR_ROTATE_45_BUTTON", comment: "Label for button that rotates image 45 degrees."),
                                for: .normal)
        rotate45Button.block = { [weak self] in
            self?.rotate45ButtonPressed()
        }

        let resetButton = OWSButton()
        resetButton.setTitle(NSLocalizedString("IMAGE_EDITOR_RESET_BUTTON", comment: "Label for button that resets crop & rotation state."),
                             for: .normal)
        resetButton.block = { [weak self] in
            self?.resetButtonPressed()
        }

        let zoom2xButton = OWSButton()
        zoom2xButton.setTitle("Zoom 2x",
                             for: .normal)
        zoom2xButton.block = { [weak self] in
            self?.zoom2xButtonPressed()
        }

        cropView.setContentHuggingLow()
        cropView.setCompressionResistanceLow()
        view.addSubview(cropView)
        for cropCornerView in cropCornerViews {
            cropView.addSubview(cropCornerView)

            switch cropCornerView.cropRegion {
            case .topLeft, .bottomLeft:
                cropCornerView.autoPinEdge(toSuperviewEdge: .left)
            case .topRight, .bottomRight:
                cropCornerView.autoPinEdge(toSuperviewEdge: .right)
                default:
                    owsFailDebug("Invalid crop region: \(cropRegion)")
            }
            switch cropCornerView.cropRegion {
            case .topLeft, .topRight:
                cropCornerView.autoPinEdge(toSuperviewEdge: .top)
            case .bottomLeft, .bottomRight:
                cropCornerView.autoPinEdge(toSuperviewEdge: .bottom)
            default:
                owsFailDebug("Invalid crop region: \(cropRegion)")
            }
        }

        let footer = UIStackView(arrangedSubviews: [rotate90Button, rotate45Button, resetButton, zoom2xButton])
        footer.axis = .horizontal
        footer.spacing = 16
        footer.backgroundColor = .clear
        footer.isOpaque = false
        stackView.addArrangedSubview(footer)

        updateClipViewLayout()

        configureGestures()
    }

    private static let desiredCornerSize: CGFloat = 30
    private static let minCropSize: CGFloat = desiredCornerSize * 2
    private var cornerSize = CGSize.zero

    private var clipViewConstraints = [NSLayoutConstraint]()

    private func updateClipViewLayout() {
        NSLayoutConstraint.deactivate(clipViewConstraints)
        clipViewConstraints = ImageEditorCanvasView.updateContentLayout(transform: transform,
                                                                        contentView: clipView)

        clipView.superview?.setNeedsLayout()
        clipView.superview?.layoutIfNeeded()
        updateCropViewLayout()
    }

    private var cropViewConstraints = [NSLayoutConstraint]()

    private func updateCropViewLayout() {
        NSLayoutConstraint.deactivate(cropViewConstraints)
        cropViewConstraints.removeAll()

        // TODO: Tune the size.
        let cornerSize = CGSize(width: min(clipView.width() * 0.5, ImageEditorCropViewController.desiredCornerSize),
                                height: min(clipView.height() * 0.5, ImageEditorCropViewController.desiredCornerSize))
        self.cornerSize = cornerSize
        for cropCornerView in cropCornerViews {
            cropViewConstraints.append(contentsOf: cropCornerView.autoSetDimensions(to: cornerSize))

            cropCornerView.addRedBorder()
            cropView.addRedBorder()
        }

        if !isCropGestureActive {
            cropView.frame = view.convert(clipView.bounds, from: clipView)
        }
    }

    internal func updateContent() {
        AssertIsOnMainThread()

        Logger.verbose("")

        let viewSize = contentView.bounds.size
        guard viewSize.width > 0,
                viewSize.height > 0 else {
                return
        }

        updateTransform(transform)
    }

    private func updateTransform(_ transform: ImageEditorTransform) {
        self.transform = transform

        // Don't animate changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        applyTransform()
        updateClipViewLayout()
        updateImageLayer()

        CATransaction.commit()
    }

    private func applyTransform() {
        Logger.verbose("")

        let viewSize = contentView.bounds.size
//        contentView.layer.anchorPoint = .zero
        contentView.layer.setAffineTransform(transform.affineTransform(viewSize: viewSize))
    }

    private func updateImageLayer() {
        let viewSize = contentView.bounds.size
        ImageEditorCanvasView.updateImageLayer(imageLayer: imageLayer, viewSize: viewSize, imageSize: model.srcImageSizePixels, transform: transform)
    }

    private func configureGestures() {
        self.view.isUserInteractionEnabled = true

        let pinchGestureRecognizer = ImageEditorPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        pinchGestureRecognizer.referenceView = self.clipView
        view.addGestureRecognizer(pinchGestureRecognizer)

        let panGestureRecognizer = ImageEditorPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer.maximumNumberOfTouches = 1
        panGestureRecognizer.referenceView = self.clipView
        view.addGestureRecognizer(panGestureRecognizer)
    }

    override public var canBecomeFirstResponder: Bool {
        return true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        _ = self.becomeFirstResponder()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        _ = self.becomeFirstResponder()
    }

    // MARK: - Pinch Gesture

    @objc
    public func handlePinchGesture(_ gestureRecognizer: ImageEditorPinchGestureRecognizer) {
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

            let locationUnitStart = self.locationUnit(forLocationInView: gestureRecognizer.pinchStateStart.centroid,
                                                      transform: gestureStartTransform)
            let locationUnitLast = self.locationUnit(forLocationInView: gestureRecognizer.pinchStateLast.centroid,
                                                     transform: gestureStartTransform)
            let locationUnitDelta = CGPointSubtract(locationUnitLast, locationUnitStart)
            let newUnitTranslation = CGPointAdd(gestureStartTransform.unitTranslation, locationUnitDelta)

            let newRotationRadians = gestureStartTransform.rotationRadians + gestureRecognizer.pinchStateLast.angleRadians - gestureRecognizer.pinchStateStart.angleRadians

            // NOTE: We use max(1, ...) to avoid divide-by-zero.
            //
            // TODO: The clamp limits are wrong.
            let newScaling = CGFloatClamp(gestureStartTransform.scaling * gestureRecognizer.pinchStateLast.distance / max(1.0, gestureRecognizer.pinchStateStart.distance),
                                          ImageEditorTextItem.kMinScaling,
                                          ImageEditorTextItem.kMaxScaling)

            updateTransform(ImageEditorTransform(outputSizePixels: gestureStartTransform.outputSizePixels,
                                             unitTranslation: newUnitTranslation,
                                             rotationRadians: newRotationRadians,
                                             scaling: newScaling).normalize())
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
    public func handlePanGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer) {
        AssertIsOnMainThread()

        Logger.verbose("")

        // We could undo an in-progress pinch if the gesture is cancelled, but it seems gratuitous.

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
    }

    private func handleCropPanGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer,
                                      panCropRegion: CropRegion) {
        AssertIsOnMainThread()

        Logger.verbose("")

        guard let locationStart = gestureRecognizer.locationStart else {
            owsFailDebug("Missing locationStart.")
            return
        }
        let locationNow = gestureRecognizer.location(in: self.clipView)

        // Crop pan gesture
        let locationDelta = CGPointSubtract(locationNow, locationStart)

        let cropRectangleStart = clipView.bounds
        var cropRectangleNow = cropRectangleStart

        let maxDeltaX = cropRectangleNow.size.width - cornerSize.width * 2
        let maxDeltaY = cropRectangleNow.size.height - cornerSize.height * 2

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

        cropView.frame = view.convert(cropRectangleNow, from: clipView)

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
        let croppedOutputSizePixels = CGSizeRound(CGSize(width: transform.outputSizePixels.width * cropRect.width / clipView.width(),
                                                         height: transform.outputSizePixels.height * cropRect.height / clipView.height()))

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
                                                  scaling: transform.scaling)
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
        // system of the crop rectangle).  Note that a CALayer's tranform
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
                                              scaling: scaling).normalize())
    }

    private func handleNormalPanGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer) {
        AssertIsOnMainThread()

        guard let gestureStartTransform = gestureStartTransform else {
            owsFailDebug("Missing pinchTransform.")
            return
        }
        guard let locationStart = gestureRecognizer.locationStart else {
            owsFailDebug("Missing locationStart.")
            return
        }
        let locationNow = gestureRecognizer.location(in: self.clipView)

        let locationUnitStart = self.locationUnit(forLocationInView: locationStart, transform: gestureStartTransform)
        let locationUnitNow = self.locationUnit(forLocationInView: locationNow, transform: gestureStartTransform)
        let locationUnitDelta = CGPointSubtract(locationUnitNow, locationUnitStart)
        let newUnitTranslation = CGPointAdd(gestureStartTransform.unitTranslation, locationUnitDelta)

        updateTransform(ImageEditorTransform(outputSizePixels: gestureStartTransform.outputSizePixels,
                                         unitTranslation: newUnitTranslation,
                                         rotationRadians: gestureStartTransform.rotationRadians,
                                         scaling: gestureStartTransform.scaling).normalize())
    }

    private func cropRegion(forGestureRecognizer gestureRecognizer: ImageEditorPanGestureRecognizer) -> CropRegion? {
        guard let location = gestureRecognizer.locationStart else {
            owsFailDebug("Missing locationStart.")
            return nil
        }

        let tolerance: CGFloat = ImageEditorCropViewController.desiredCornerSize * 2.0
        let left = tolerance
        let top = tolerance
        let right = clipView.width() - tolerance
        let bottom = clipView.height() - tolerance

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

    // MARK: - Coordinates

    private func locationUnit(forGestureRecognizer gestureRecognizer: UIGestureRecognizer,
                              transform: ImageEditorTransform) -> CGPoint {
        return ImageEditorCanvasView.locationUnit(forGestureRecognizer: gestureRecognizer, view: clipView, transform: transform)
    }

    private func locationUnit(forLocationInView locationInView: CGPoint,
                              transform: ImageEditorTransform) -> CGPoint {
        return ImageEditorCanvasView.locationUnit(forLocationInView: locationInView, viewSize: clipView.bounds.size, transform: transform)
    }

    // MARK: - Events

    @objc public func didTapBackButton() {
        completeAndDismiss()
    }

    private func completeAndDismiss() {
        // TODO:
        self.delegate?.cropDidComplete(transform: transform)

        self.dismiss(animated: true) {
            // Do nothing.
        }
    }

    @objc public func rotate90ButtonPressed() {
        rotateButtonPressed(angleRadians: CGFloat.pi * 0.5)
    }

    @objc public func rotate45ButtonPressed() {
        rotateButtonPressed(angleRadians: CGFloat.pi * 0.25)
    }

    private func rotateButtonPressed(angleRadians: CGFloat) {
        // Invert width and height.
        let outputSizePixels = CGSize(width: transform.outputSizePixels.height,
                                      height: transform.outputSizePixels.width)
        let unitTranslation = transform.unitTranslation
        let rotationRadians = transform.rotationRadians + angleRadians
        let scaling = transform.scaling
        updateTransform(ImageEditorTransform(outputSizePixels: outputSizePixels,
                                         unitTranslation: unitTranslation,
                                         rotationRadians: rotationRadians,
                                         scaling: scaling).normalize())
    }

    @objc public func zoom2xButtonPressed() {
        let outputSizePixels = transform.outputSizePixels
        let unitTranslation = transform.unitTranslation
        let rotationRadians = transform.rotationRadians
        let scaling = transform.scaling * 2.0
        updateTransform(ImageEditorTransform(outputSizePixels: outputSizePixels,
                                         unitTranslation: unitTranslation,
                                         rotationRadians: rotationRadians,
                                         scaling: scaling).normalize())
    }

    @objc public func resetButtonPressed() {
        updateTransform(ImageEditorTransform.defaultTransform(srcImageSizePixels: model.srcImageSizePixels))
    }
}
