//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

// A view for editing outgoing image attachments.
// It can also be used to render the final output.
@objc
public class ImageEditorView: UIView, ImageEditorModelDelegate {
    private let model: ImageEditorModel

    enum EditorMode: String {
        case none
        case brush
        case crop
    }

    private var editorMode = EditorMode.none {
        didSet {
            AssertIsOnMainThread()

            switch editorMode {
            case .none:
                editorGestureRecognizer?.isEnabled = false
            case .brush:
                // Brush strokes can start and end (and return from) outside the view.
                editorGestureRecognizer?.shouldAllowOutsideView = true
                editorGestureRecognizer?.isEnabled = true
            case .crop:
                // Crop gestures can start and end (and return from) outside the view.
                editorGestureRecognizer?.shouldAllowOutsideView = true
                editorGestureRecognizer?.isEnabled = true
            }
        }
    }

    // TODO:
    private static let defaultColor = UIColor.ows_signalBlue
    private var currentColor = ImageEditorView.defaultColor

    @objc
    public required init(model: ImageEditorModel) {
        self.model = model

        super.init(frame: .zero)

        model.delegate = self
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - Views

    private let imageView = UIImageView()
    private var imageViewConstraints = [NSLayoutConstraint]()
    private let layersView = OWSLayerView()
    private var editorGestureRecognizer: ImageEditorGestureRecognizer?

    @objc
    public func configureSubviews() -> Bool {
        self.addSubview(imageView)

        guard updateImageView() else {
            return false
        }

        layersView.clipsToBounds = true
        layersView.layoutCallback = { [weak self] (_) in
            self?.updateAllContent()
        }
        self.addSubview(layersView)
        layersView.autoPin(toEdgesOf: imageView)

        self.isUserInteractionEnabled = true
        layersView.isUserInteractionEnabled = true
        let editorGestureRecognizer = ImageEditorGestureRecognizer(target: self, action: #selector(handleTouchGesture(_:)))
        editorGestureRecognizer.canvasView = layersView
        self.addGestureRecognizer(editorGestureRecognizer)
        self.editorGestureRecognizer = editorGestureRecognizer
        editorGestureRecognizer.isEnabled = false

        return true
    }

    @objc
    public func updateImageView() -> Bool {
        Logger.verbose("")

        guard let image = UIImage(contentsOfFile: model.currentImagePath) else {
            owsFailDebug("Could not load image")
            return false
        }
        guard image.size.width > 0 && image.size.height > 0 else {
            owsFailDebug("Could not load image")
            return false
        }

        imageView.image = image
        imageView.layer.minificationFilter = kCAFilterTrilinear
        imageView.layer.magnificationFilter = kCAFilterTrilinear
        let aspectRatio = image.size.width / image.size.height
        for constraint in imageViewConstraints {
            constraint.autoRemove()
        }
        imageViewConstraints = applyScaleAspectFitLayout(view: imageView, aspectRatio: aspectRatio)

        return true
    }

    private func applyScaleAspectFitLayout(view: UIView, aspectRatio: CGFloat) -> [NSLayoutConstraint] {
        // This emulates the behavior of contentMode = .scaleAspectFit using
        // iOS auto layout constraints.
        //
        // This allows ConversationInputToolbar to place the "cancel" button
        // in the upper-right hand corner of the preview content.
        var constraints = [NSLayoutConstraint]()
        constraints.append(contentsOf: view.autoCenterInSuperview())
        constraints.append(view.autoPin(toAspectRatio: aspectRatio))
        constraints.append(view.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual))
        constraints.append(view.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual))
        return constraints
    }

    private let undoButton = UIButton(type: .custom)
    private let redoButton = UIButton(type: .custom)
    private let brushButton = UIButton(type: .custom)
    private let cropButton = UIButton(type: .custom)

    @objc
    public func addControls(to containerView: UIView) {
        configure(button: undoButton,
                  label: NSLocalizedString("BUTTON_UNDO", comment: "Label for undo button."),
                  selector: #selector(didTapUndo(sender:)))

        configure(button: redoButton,
                  label: NSLocalizedString("BUTTON_REDO", comment: "Label for redo button."),
                  selector: #selector(didTapRedo(sender:)))

        configure(button: brushButton,
                  label: NSLocalizedString("IMAGE_EDITOR_BRUSH_BUTTON", comment: "Label for brush button in image editor."),
                  selector: #selector(didTapBrush(sender:)))

        configure(button: cropButton,
                  label: NSLocalizedString("IMAGE_EDITOR_CROP_BUTTON", comment: "Label for crop button in image editor."),
                  selector: #selector(didTapCrop(sender:)))

        let redButton = colorButton(color: UIColor.red)
        let whiteButton = colorButton(color: UIColor.white)
        let blackButton = colorButton(color: UIColor.black)

        let stackView = UIStackView(arrangedSubviews: [brushButton, cropButton, undoButton, redoButton, redButton, whiteButton, blackButton])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10

        containerView.addSubview(stackView)
        stackView.autoAlignAxis(toSuperviewAxis: .horizontal)
        stackView.autoPinTrailingToSuperviewMargin(withInset: 10)

        updateButtons()
    }

    private func configure(button: UIButton,
                           label: String,
                           selector: Selector) {
        button.setTitle(label, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(.gray, for: .disabled)
        button.setTitleColor(UIColor.ows_materialBlue, for: .selected)
        button.titleLabel?.font = UIFont.ows_dynamicTypeBody.ows_mediumWeight()
        button.addTarget(self, action: selector, for: .touchUpInside)
    }

    private func colorButton(color: UIColor) -> UIButton {
        let button = OWSButton { [weak self] in
            self?.didSelectColor(color)
        }
        let size: CGFloat = 20
        let swatch = UIImage(color: color, size: CGSize(width: size, height: size))
        button.setImage(swatch, for: .normal)
        button.addBorder(with: UIColor.white)
        return button
    }

    private func updateButtons() {
        undoButton.isEnabled = model.canUndo()
        redoButton.isEnabled = model.canRedo()
        brushButton.isSelected = editorMode == .brush
        cropButton.isSelected = editorMode == .crop
    }

    // MARK: - Actions

    @objc func didTapUndo(sender: UIButton) {
        Logger.verbose("")
        guard model.canUndo() else {
            owsFailDebug("Can't undo.")
            return
        }
        model.undo()
    }

    @objc func didTapRedo(sender: UIButton) {
        Logger.verbose("")
        guard model.canRedo() else {
            owsFailDebug("Can't redo.")
            return
        }
        model.redo()
    }

    @objc func didTapBrush(sender: UIButton) {
        Logger.verbose("")

        toggle(editorMode: .brush)
    }

    @objc func didTapCrop(sender: UIButton) {
        Logger.verbose("")

        toggle(editorMode: .crop)
    }

    func toggle(editorMode: EditorMode) {
        if self.editorMode == editorMode {
            self.editorMode = .none
        } else {
            self.editorMode = editorMode
        }
        updateButtons()
    }

    @objc func didSelectColor(_ color: UIColor) {
        Logger.verbose("")

        currentColor = color
    }

    @objc
    public func handleTouchGesture(_ gestureRecognizer: UIGestureRecognizer) {
        AssertIsOnMainThread()

        switch editorMode {
        case .none:
            break
        case .brush:
            handleBrushGesture(gestureRecognizer)
        case .crop:
            handleCropGesture(gestureRecognizer)
        }
    }

    // MARK: - Brush

    // These properties are non-empty while drawing a stroke.
    private var currentStroke: ImageEditorStrokeItem?
    private var currentStrokeSamples = [ImageEditorStrokeItem.StrokeSample]()

    @objc
    public func handleBrushGesture(_ gestureRecognizer: UIGestureRecognizer) {
        AssertIsOnMainThread()

        let removeCurrentStroke = {
            if let stroke = self.currentStroke {
                self.model.remove(item: stroke)
            }
            self.currentStroke = nil
            self.currentStrokeSamples.removeAll()
        }
        let tryToAppendStrokeSample = {
            let newSample = self.unitSampleForGestureLocation(gestureRecognizer, shouldClamp: false)
            if let prevSample = self.currentStrokeSamples.last,
                    prevSample == newSample {
                // Ignore duplicate samples.
                return
            }
            self.currentStrokeSamples.append(newSample)
        }

        let strokeColor = currentColor
        // TODO: Tune stroke width.
        let unitStrokeWidth = ImageEditorStrokeItem.defaultUnitStrokeWidth()

        switch gestureRecognizer.state {
        case .began:
            removeCurrentStroke()

            tryToAppendStrokeSample()

            let stroke = ImageEditorStrokeItem(color: strokeColor, unitSamples: currentStrokeSamples, unitStrokeWidth: unitStrokeWidth)
            model.append(item: stroke)
            currentStroke = stroke

        case .changed, .ended:
            tryToAppendStrokeSample()

            guard let lastStroke = self.currentStroke else {
                owsFailDebug("Missing last stroke.")
                removeCurrentStroke()
                return
            }

            // Model items are immutable; we _replace_ the
            // stroke item rather than modify it.
            let stroke = ImageEditorStrokeItem(itemId: lastStroke.itemId, color: strokeColor, unitSamples: currentStrokeSamples, unitStrokeWidth: unitStrokeWidth)
            model.replace(item: stroke, suppressUndo: true)

            if gestureRecognizer.state == .ended {
                currentStroke = nil
                currentStrokeSamples.removeAll()
            } else {
                currentStroke = stroke
            }
        default:
            removeCurrentStroke()
        }
    }

    private func unitSampleForGestureLocation(_ gestureRecognizer: UIGestureRecognizer,
                                              shouldClamp: Bool) -> CGPoint {
        let referenceView = layersView
        // TODO: Smooth touch samples before converting into stroke samples.
        let location = gestureRecognizer.location(in: referenceView)
        var x = CGFloatInverseLerp(location.x, 0, referenceView.bounds.width)
        var y = CGFloatInverseLerp(location.y, 0, referenceView.bounds.height)
        if shouldClamp {
            x = CGFloatClamp01(x)
            y = CGFloatClamp01(y)
        }
        return CGPoint(x: x, y: y)
    }

    // MARK: - Crop

    private var cropStartUnit = CGPoint.zero
    private var cropEndUnit = CGPoint.zero
    private var cropLayer1 = CAShapeLayer()
    private var cropLayer2 = CAShapeLayer()
    private var cropLayers: [CAShapeLayer] {
        return [cropLayer1, cropLayer2]
    }

    @objc
    public func handleCropGesture(_ gestureRecognizer: UIGestureRecognizer) {
        AssertIsOnMainThread()

        let kCropDashLength: CGFloat = 3
        let cancelCrop = {
            for cropLayer in self.cropLayers {
                cropLayer.removeFromSuperlayer()
                cropLayer.removeAllAnimations()
            }
        }
        let updateCropLayer = { (cropLayer: CAShapeLayer) in
            cropLayer.fillColor = nil
            cropLayer.lineWidth = 1.0
            cropLayer.lineDashPattern = [NSNumber(value: Double(kCropDashLength)), NSNumber(value: Double(kCropDashLength))]

            let viewSize = self.layersView.bounds.size
            cropLayer.frame = CGRect(origin: .zero, size: viewSize)

            // Find the upper-left and bottom-right corners of the
            // crop rectangle, in unit coordinates.
            let unitMin = CGPointMin(self.cropStartUnit, self.cropEndUnit)
            let unitMax = CGPointMax(self.cropStartUnit, self.cropEndUnit)

            let transformSampleToPoint = { (unitSample: CGPoint) -> CGPoint in
                return CGPoint(x: viewSize.width * unitSample.x,
                               y: viewSize.height * unitSample.y)
            }

            // Convert from unit coordinates to view coordinates.
            let pointMin = transformSampleToPoint(unitMin)
            let pointMax = transformSampleToPoint(unitMax)
            let cropRect = CGRect(x: pointMin.x,
                                  y: pointMin.y,
                                  width: pointMax.x - pointMin.x,
                                  height: pointMax.y - pointMin.y)
            let bezierPath = UIBezierPath(rect: cropRect)
            cropLayer.path = bezierPath.cgPath
        }
        let updateCrop = {
            updateCropLayer(self.cropLayer1)
            updateCropLayer(self.cropLayer2)
            self.cropLayer1.strokeColor = UIColor.white.cgColor
            self.cropLayer2.strokeColor = UIColor.black.cgColor
            self.cropLayer1.lineDashPhase = 0
            self.cropLayer2.lineDashPhase = self.cropLayer1.lineDashPhase + kCropDashLength
        }
        let startCrop = {
            for cropLayer in self.cropLayers {
                self.layersView.layer.addSublayer(cropLayer)
            }

            updateCrop()
        }
        let endCrop = {
            updateCrop()

            for cropLayer in self.cropLayers {
                cropLayer.removeFromSuperlayer()
                cropLayer.removeAllAnimations()
            }

            // Find the upper-left and bottom-right corners of the
            // crop rectangle, in unit coordinates.
            let unitMin = CGPointClamp01(CGPointMin(self.cropStartUnit, self.cropEndUnit))
            let unitMax = CGPointClamp01(CGPointMax(self.cropStartUnit, self.cropEndUnit))
            let unitCropRect = CGRect(x: unitMin.x,
                                      y: unitMin.y,
                                      width: unitMax.x - unitMin.x,
                                      height: unitMax.y - unitMin.y)
            self.model.crop(unitCropRect: unitCropRect)
        }

        let currentUnitSample = {
            self.unitSampleForGestureLocation(gestureRecognizer, shouldClamp: true)
        }

        switch gestureRecognizer.state {
        case .began:
            let unitSample = currentUnitSample()
            cropStartUnit = unitSample
            cropEndUnit = unitSample
            startCrop()

        case .changed:
            cropEndUnit = currentUnitSample()
            updateCrop()
        case .ended:
            cropEndUnit = currentUnitSample()
            endCrop()
        default:
            cancelCrop()
        }
    }

    // MARK: - ImageEditorModelDelegate

    public func imageEditorModelDidChange(before: ImageEditorContents,
                                          after: ImageEditorContents) {

        if before.imagePath != after.imagePath {
            _ = updateImageView()
        }

        updateAllContent()

        updateButtons()
    }

    public func imageEditorModelDidChange(changedItemIds: [String]) {
        updateContent(changedItemIds: changedItemIds)

        updateButtons()
    }

    // MARK: - Accessor Overrides

    @objc public override var bounds: CGRect {
        didSet {
            if oldValue != bounds {
                updateAllContent()
            }
        }
    }

    @objc public override var frame: CGRect {
        didSet {
            if oldValue != frame {
                updateAllContent()
            }
        }
    }

    // MARK: - Content

    var contentLayerMap = [String: CALayer]()

    internal func updateAllContent() {
        AssertIsOnMainThread()

        // Don't animate changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for layer in contentLayerMap.values {
            layer.removeFromSuperlayer()
        }
        contentLayerMap.removeAll()

        if bounds.width > 0,
            bounds.height > 0 {

            for item in model.items() {
                let viewSize = layersView.bounds.size
                guard let layer = ImageEditorView.layerForItem(item: item,
                                                               viewSize: viewSize) else {
                                                                continue
                }

                layersView.layer.addSublayer(layer)
                contentLayerMap[item.itemId] = layer
            }
        }

        CATransaction.commit()
    }

    internal func updateContent(changedItemIds: [String]) {
        AssertIsOnMainThread()

        // Don't animate changes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Remove all changed items.
        for itemId in changedItemIds {
            if let layer = contentLayerMap[itemId] {
                layer.removeFromSuperlayer()
            }
            contentLayerMap.removeValue(forKey: itemId)
        }

        if bounds.width > 0,
            bounds.height > 0 {

            // Create layers for inserted and updated items.
            for itemId in changedItemIds {
                guard let item = model.item(forId: itemId) else {
                    // Item was deleted.
                    continue
                }

                // Item was inserted or updated.
                let viewSize = layersView.bounds.size
                guard let layer = ImageEditorView.layerForItem(item: item,
                                                               viewSize: viewSize) else {
                                                                continue
                }

                layersView.layer.addSublayer(layer)
                contentLayerMap[item.itemId] = layer
            }
        }

        CATransaction.commit()
    }

    private class func layerForItem(item: ImageEditorItem,
                                    viewSize: CGSize) -> CALayer? {
        AssertIsOnMainThread()

        switch item.itemType {
        case .test:
            owsFailDebug("Unexpected test item.")
            return nil
        case .stroke:
            guard let strokeItem = item as? ImageEditorStrokeItem else {
                owsFailDebug("Item has unexpected type: \(type(of: item)).")
                return nil
            }
            return strokeLayerForItem(item: strokeItem, viewSize: viewSize)
        }
    }

    private class func strokeLayerForItem(item: ImageEditorStrokeItem,
                                          viewSize: CGSize) -> CALayer? {
        AssertIsOnMainThread()

        let strokeWidth = ImageEditorStrokeItem.strokeWidth(forUnitStrokeWidth: item.unitStrokeWidth,
                                                            dstSize: viewSize)
        let unitSamples = item.unitSamples
        guard unitSamples.count > 0 else {
            // Not an error; the stroke doesn't have enough samples to render yet.
            return nil
        }

        let shapeLayer = CAShapeLayer()
        shapeLayer.lineWidth = strokeWidth
        shapeLayer.strokeColor = item.color.cgColor
        shapeLayer.frame = CGRect(origin: .zero, size: viewSize)

        let transformSampleToPoint = { (unitSample: CGPoint) -> CGPoint in
            return CGPoint(x: viewSize.width * unitSample.x,
                           y: viewSize.height * unitSample.y)
        }

        // TODO: Use bezier curves to smooth stroke.
        let bezierPath = UIBezierPath()

        let points = applySmoothing(to: unitSamples.map { (unitSample) in
            transformSampleToPoint(unitSample)
        })
        var previousForwardVector = CGPoint.zero
        for index in 0..<points.count {
            let point = points[index]

            let forwardVector: CGPoint
            if points.count <= 1 {
                // Skip forward vectors.
                forwardVector = .zero
            } else if index == 0 {
                // First sample.
                let nextPoint = points[index + 1]
                forwardVector = CGPointSubtract(nextPoint, point)
            } else if index == points.count - 1 {
                // Last sample.
                let previousPoint = points[index - 1]
                forwardVector = CGPointSubtract(point, previousPoint)
            } else {
                // Middle samples.
                let previousPoint = points[index - 1]
                let previousPointForwardVector = CGPointSubtract(point, previousPoint)
                let nextPoint = points[index + 1]
                let nextPointForwardVector = CGPointSubtract(nextPoint, point)
                forwardVector = CGPointScale(CGPointAdd(previousPointForwardVector, nextPointForwardVector), 0.5)
            }

            if index == 0 {
                // First sample.
                bezierPath.move(to: point)

                if points.count == 1 {
                    bezierPath.addLine(to: point)
                }
            } else {
                let previousPoint = points[index - 1]
                // We apply more than one kind of smoothing.
                // This smoothing avoids rendering "angled segments"
                // by drawing the stroke as a series of curves.
                // We use bezier curves and infer the control points
                // from the "next" and "prev" points.
                //
                // This factor controls how much we're smoothing.
                //
                // * 0.0 = No smoothing.
                //
                // TODO: Tune this variable once we have stroke input.
                let controlPointFactor: CGFloat = 0.25
                let controlPoint1 = CGPointAdd(previousPoint, CGPointScale(previousForwardVector, +controlPointFactor))
                let controlPoint2 = CGPointAdd(point, CGPointScale(forwardVector, -controlPointFactor))
                // We're using Cubic curves.
                bezierPath.addCurve(to: point, controlPoint1: controlPoint1, controlPoint2: controlPoint2)
            }
            previousForwardVector = forwardVector
        }

        shapeLayer.path = bezierPath.cgPath
        shapeLayer.fillColor = nil
        shapeLayer.lineCap = kCALineCapRound
        shapeLayer.lineJoin = kCALineJoinRound

        return shapeLayer
    }

    // We apply more than one kind of smoothing.
    //
    // This (simple) smoothing reduces jitter from the touch sensor.
    private class func applySmoothing(to points: [CGPoint]) -> [CGPoint] {
        AssertIsOnMainThread()

        var result = [CGPoint]()

        for index in 0..<points.count {
            let point = points[index]

            if index == 0 {
                // First sample.
                result.append(point)
            } else if index == points.count - 1 {
                // Last sample.
                result.append(point)
            } else {
                // Middle samples.
                let lastPoint = points[index - 1]
                let nextPoint = points[index + 1]
                let alpha: CGFloat = 0.1
                let smoothedPoint = CGPointAdd(CGPointScale(point, 1.0 - 2.0 * alpha),
                                               CGPointAdd(CGPointScale(lastPoint, alpha),
                                                          CGPointScale(nextPoint, alpha)))
                result.append(smoothedPoint)
            }
        }

        return result
    }

    // MARK: - Actions

    // Returns nil on error.
    @objc
    public class func renderForOutput(model: ImageEditorModel) -> UIImage? {
        // TODO: Do we want to render off the main thread?
        AssertIsOnMainThread()

        // Render output at same size as source image.
        let dstSizePixels = model.srcImageSizePixels

        let hasAlpha = NSData.hasAlpha(forValidImageFilePath: model.currentImagePath)

        guard let srcImage = UIImage(contentsOfFile: model.currentImagePath) else {
            owsFailDebug("Could not load src image.")
            return nil
        }

        let dstScale: CGFloat = 1.0 // The size is specified in pixels, not in points.
        UIGraphicsBeginImageContextWithOptions(dstSizePixels, !hasAlpha, dstScale)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else {
            owsFailDebug("Could not create output context.")
            return nil
        }
        context.interpolationQuality = .high

        // Draw source image.
        let dstFrame = CGRect(origin: .zero, size: model.srcImageSizePixels)
        srcImage.draw(in: dstFrame)

        for item in model.items() {
            guard let layer = layerForItem(item: item,
                                           viewSize: dstSizePixels) else {
                Logger.error("Couldn't create layer for item.")
                continue
            }
            // This might be superfluous, but ensure that the layer renders
            // at "point=pixel" scale.
            layer.contentsScale = 1.0

            layer.render(in: context)
        }

        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        if scaledImage == nil {
            owsFailDebug("could not generate dst image.")
        }
        return scaledImage
    }
}
