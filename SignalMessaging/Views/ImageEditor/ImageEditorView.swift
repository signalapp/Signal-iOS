//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

extension UIView {
    public func renderAsImage() -> UIImage? {
        return renderAsImage(opaque: false, scale: UIScreen.main.scale)
    }

    public func renderAsImage(opaque: Bool, scale: CGFloat) -> UIImage? {
        if #available(iOS 10, *) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = opaque
            let renderer = UIGraphicsImageRenderer(bounds: self.bounds,
                                                   format: format)
            return renderer.image { (context) in
                self.layer.render(in: context.cgContext)
            }
        } else {
            UIGraphicsBeginImageContextWithOptions(bounds.size, opaque, scale)
            if let _ = UIGraphicsGetCurrentContext() {
                drawHierarchy(in: bounds, afterScreenUpdates: true)
                let image = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                return image
            }
            owsFailDebug("Could not create graphics context.")
            return nil
        }
    }
}

private class EditorTextLayer: CATextLayer {
    let itemId: String

    public init(itemId: String) {
        self.itemId = itemId

        super.init()
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }
}

// MARK: -

// A view for editing outgoing image attachments.
// It can also be used to render the final output.
@objc
public class ImageEditorView: UIView, ImageEditorModelDelegate, ImageEditorTextViewControllerDelegate, UIGestureRecognizerDelegate {

    private let model: ImageEditorModel

    enum EditorMode: String {
        // This is the default mode.  It is used for interacting with text items.
        case none
        case brush
        case crop
    }

    private var editorMode = EditorMode.none {
        didSet {
            AssertIsOnMainThread()

            updateGestureState()
        }
    }

    private static let defaultColor = UIColor.white
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
    private var tapGestureRecognizer: UITapGestureRecognizer?
    private var pinchGestureRecognizer: ImageEditorPinchGestureRecognizer?

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

        let editorGestureRecognizer = ImageEditorGestureRecognizer(target: self, action: #selector(handleEditorGesture(_:)))
        editorGestureRecognizer.canvasView = layersView
        editorGestureRecognizer.delegate = self
        self.addGestureRecognizer(editorGestureRecognizer)
        self.editorGestureRecognizer = editorGestureRecognizer

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        self.addGestureRecognizer(tapGestureRecognizer)
        self.tapGestureRecognizer = tapGestureRecognizer

        let pinchGestureRecognizer = ImageEditorPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        self.addGestureRecognizer(pinchGestureRecognizer)
        self.pinchGestureRecognizer = pinchGestureRecognizer

        // De-conflict the GRs.
        editorGestureRecognizer.require(toFail: tapGestureRecognizer)
        editorGestureRecognizer.require(toFail: pinchGestureRecognizer)

        updateGestureState()

        return true
    }

    private func commitTextEditingChanges(textItem: ImageEditorTextItem, textView: UITextView) {
        AssertIsOnMainThread()

        guard let text = textView.text?.ows_stripped(),
            text.count > 0 else {
                model.remove(item: textItem)
                return
        }

        // Model items are immutable; we _replace_ the item rather than modify it.
        let newItem = textItem.copy(withText: text)
        if model.has(itemForId: textItem.itemId) {
            model.replace(item: newItem, suppressUndo: false)
        } else {
            model.append(item: newItem)
        }
    }

    @objc
    public func updateImageView() -> Bool {

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
    private let newTextButton = UIButton(type: .custom)
    private var allButtons = [UIButton]()

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

        configure(button: newTextButton,
                  label: "Text",
                  selector: #selector(didTapNewText(sender:)))

        let redButton = colorButton(color: UIColor.red)
        let whiteButton = colorButton(color: UIColor.white)
        let blackButton = colorButton(color: UIColor.black)

        allButtons = [brushButton, cropButton, undoButton, redoButton, newTextButton, redButton, whiteButton, blackButton]

        let stackView = UIStackView(arrangedSubviews: allButtons)
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
        newTextButton.isSelected = false

        for button in allButtons {
            button.isHidden = isEditingTextItem
        }
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

    @objc func didTapNewText(sender: UIButton) {
        Logger.verbose("")

        let textItem = ImageEditorTextItem.empty(withColor: currentColor)

        edit(textItem: textItem)
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

    // MARK: - Gestures

    private func updateGestureState() {
        AssertIsOnMainThread()

        switch editorMode {
        case .none:
            editorGestureRecognizer?.shouldAllowOutsideView = true
            editorGestureRecognizer?.isEnabled = true
            tapGestureRecognizer?.isEnabled = true
            pinchGestureRecognizer?.isEnabled = true
        case .brush:
            // Brush strokes can start and end (and return from) outside the view.
            editorGestureRecognizer?.shouldAllowOutsideView = true
            editorGestureRecognizer?.isEnabled = true
            tapGestureRecognizer?.isEnabled = false
            pinchGestureRecognizer?.isEnabled = false
        case .crop:
            // Crop gestures can start and end (and return from) outside the view.
            editorGestureRecognizer?.shouldAllowOutsideView = true
            editorGestureRecognizer?.isEnabled = true
            tapGestureRecognizer?.isEnabled = false
            pinchGestureRecognizer?.isEnabled = false
        }
    }

    // MARK: - Tap Gesture

    @objc
    public func handleTapGesture(_ gestureRecognizer: UIGestureRecognizer) {
        AssertIsOnMainThread()

        guard gestureRecognizer.state == .recognized else {
            owsFailDebug("Unexpected state.")
            return
        }

        guard let textLayer = textLayer(forGestureRecognizer: gestureRecognizer) else {
            return
        }

        guard let textItem = model.item(forId: textLayer.itemId) as? ImageEditorTextItem else {
            owsFailDebug("Missing or invalid text item.")
            return
        }

        edit(textItem: textItem)
    }

    private var isEditingTextItem = false {
        didSet {
            AssertIsOnMainThread()

            updateButtons()
        }
    }

    private func edit(textItem: ImageEditorTextItem) {
        Logger.verbose("")

        toggle(editorMode: .none)

        guard let viewController = self.containingViewController() else {
            owsFailDebug("Can't find view controller.")
            return
        }

        isEditingTextItem = true

        let maxTextWidthPoints = imageView.width() * ImageEditorTextItem.kDefaultUnitWidth

        let textEditor = ImageEditorTextViewController(delegate: self, textItem: textItem, maxTextWidthPoints: maxTextWidthPoints)
        let navigationController = OWSNavigationController(rootViewController: textEditor)
        navigationController.modalPresentationStyle = .overFullScreen
        viewController.present(navigationController, animated: true) {
            // Do nothing.
        }
    }

    // MARK: - Pinch Gesture

    // These properties are valid while moving a text item.
    private var pinchingTextItem: ImageEditorTextItem?
    private var pinchHasChanged = false

    @objc
    public func handlePinchGesture(_ gestureRecognizer: ImageEditorPinchGestureRecognizer) {
        AssertIsOnMainThread()

        // We could undo an in-progress pinch if the gesture is cancelled, but it seems gratuitous.

        switch gestureRecognizer.state {
        case .began:
            let pinchState = gestureRecognizer.pinchStateStart
            guard let gestureRecognizerView = gestureRecognizer.view else {
                owsFailDebug("Missing gestureRecognizer.view.")
                return
            }
            let location = gestureRecognizerView.convert(pinchState.centroid, to: unitReferenceView)
            guard let textLayer = textLayer(forLocation: location) else {
                // The pinch needs to start centered on a text item.
                return
            }
            guard let textItem = model.item(forId: textLayer.itemId) as? ImageEditorTextItem else {
                owsFailDebug("Missing or invalid text item.")
                return
            }
            pinchingTextItem = textItem
            pinchHasChanged = false
        case .changed, .ended:
            guard let textItem = pinchingTextItem else {
                return
            }

            let locationDelta = CGPointSubtract(gestureRecognizer.pinchStateLast.centroid,
                                                gestureRecognizer.pinchStateStart.centroid)
            let unitLocationDelta = convertToUnit(location: locationDelta, shouldClamp: false)
            let unitCenter = CGPointClamp01(CGPointAdd(textItem.unitCenter, unitLocationDelta))

            // NOTE: We use max(1, ...) to avoid divide-by-zero.
            let newScaling = CGFloatClamp(textItem.scaling * gestureRecognizer.pinchStateLast.distance / max(1.0, gestureRecognizer.pinchStateStart.distance),
                                          ImageEditorTextItem.kMinScaling,
                                          ImageEditorTextItem.kMaxScaling)

            let newRotationRadians = textItem.rotationRadians + gestureRecognizer.pinchStateLast.angleRadians - gestureRecognizer.pinchStateStart.angleRadians

            let newItem = textItem.copy(withUnitCenter: unitCenter,
                                        scaling: newScaling,
                                        rotationRadians: newRotationRadians)

            if pinchHasChanged {
                model.replace(item: newItem, suppressUndo: true)
            } else {
                model.replace(item: newItem, suppressUndo: false)
                pinchHasChanged = true
            }

            if gestureRecognizer.state == .ended {
                pinchingTextItem = nil
            }
        default:
            pinchingTextItem = nil
        }
    }

    // MARK: - Editor Gesture

    @objc
    public func handleEditorGesture(_ gestureRecognizer: ImageEditorGestureRecognizer) {
        AssertIsOnMainThread()

        switch editorMode {
        case .none:
            handleDefaultGesture(gestureRecognizer)
            break
        case .brush:
            handleBrushGesture(gestureRecognizer)
        case .crop:
            handleCropGesture(gestureRecognizer)
        }
    }

    // These properties are valid while moving a text item.
    private var movingTextItem: ImageEditorTextItem?
    private var movingTextStartUnitLocation = CGPoint.zero
    private var movingTextStartUnitCenter = CGPoint.zero
    private var movingTextHasMoved = false

    @objc
    public func handleDefaultGesture(_ gestureRecognizer: ImageEditorGestureRecognizer) {
        AssertIsOnMainThread()

        // We could undo an in-progress move if the gesture is cancelled, but it seems gratuitous.

        switch gestureRecognizer.state {
        case .began:
            guard let gestureRecognizerView = gestureRecognizer.view else {
                owsFailDebug("Missing gestureRecognizer.view.")
                return
            }
            let location = gestureRecognizerView.convert(gestureRecognizer.startLocationInView, to: unitReferenceView)
            guard let textLayer = textLayer(forLocation: location) else {
                owsFailDebug("No text layer")
                return
            }
            guard let textItem = model.item(forId: textLayer.itemId) as? ImageEditorTextItem else {
                owsFailDebug("Missing or invalid text item.")
                return
            }
            movingTextStartUnitLocation = convertToUnit(location: location,
                                                        shouldClamp: false)

            movingTextItem = textItem
            movingTextStartUnitCenter = textItem.unitCenter
            movingTextHasMoved = false

        case .changed, .ended:
            guard let textItem = movingTextItem else {
                return
            }

            let unitLocation = unitSampleForGestureLocation(gestureRecognizer, shouldClamp: false)
            let unitLocationDelta = CGPointSubtract(unitLocation, movingTextStartUnitLocation)
            let unitCenter = CGPointClamp01(CGPointAdd(movingTextStartUnitCenter, unitLocationDelta))
            let newItem = textItem.copy(withUnitCenter: unitCenter)

            if movingTextHasMoved {
                model.replace(item: newItem, suppressUndo: true)
            } else {
                model.replace(item: newItem, suppressUndo: false)
                movingTextHasMoved = true
            }

            if gestureRecognizer.state == .ended {
                movingTextItem = nil
            }
        default:
            movingTextItem = nil
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

    private var unitReferenceView: UIView {
        return layersView
    }

    private func unitSampleForGestureLocation(_ gestureRecognizer: UIGestureRecognizer,
                                              shouldClamp: Bool) -> CGPoint {
        // TODO: Smooth touch samples before converting into stroke samples.
        let location = gestureRecognizer.location(in: unitReferenceView)
        return convertToUnit(location: location,
                             shouldClamp: shouldClamp)
    }

    private func convertToUnit(location: CGPoint,
                               shouldClamp: Bool) -> CGPoint {
        var x = CGFloatInverseLerp(location.x, 0, unitReferenceView.bounds.width)
        var y = CGFloatInverseLerp(location.y, 0, unitReferenceView.bounds.height)
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
        case .text:
            guard let textItem = item as? ImageEditorTextItem else {
                owsFailDebug("Item has unexpected type: \(type(of: item)).")
                return nil
            }
            return textLayerForItem(item: textItem, viewSize: viewSize)
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

    private class func textLayerForItem(item: ImageEditorTextItem,
                                        viewSize: CGSize) -> CALayer? {
        AssertIsOnMainThread()

        let layer = EditorTextLayer(itemId: item.itemId)
        layer.string = item.text
        layer.foregroundColor = item.color.cgColor
        layer.font = CGFont(item.font.fontName as CFString)
        layer.fontSize = item.font.pointSize
        layer.isWrapped = true
        layer.alignmentMode = kCAAlignmentCenter
        // I don't think we need to enable allowsFontSubpixelQuantization
        // or set truncationMode.

        // This text needs to be rendered at a scale that reflects the scaling.
        layer.contentsScale = UIScreen.main.scale * item.scaling

        // TODO: Min with measured width.
        let maxWidth = viewSize.width * item.unitWidth
        let maxSize = CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
        // TODO: Is there a more accurate way to measure text in a CATextLayer?
        //       CoreText?
        let textBounds = (item.text as NSString).boundingRect(with: maxSize,
                                                              options: [
                                                                .usesLineFragmentOrigin,
                                                                .usesFontLeading
            ],
                                                              attributes: [
                                                                .font: item.font
            ],
                                                              context: nil)
        let center = CGPoint(x: viewSize.width * item.unitCenter.x,
                             y: viewSize.height * item.unitCenter.y)
        let layerSize = CGSizeCeil(textBounds.size)
        layer.frame = CGRect(origin: CGPoint(x: center.x - layerSize.width * 0.5,
                                             y: center.y - layerSize.height * 0.5),
                             size: layerSize)

        let transform = CGAffineTransform.identity.scaledBy(x: item.scaling, y: item.scaling).rotated(by: item.rotationRadians)
        layer.setAffineTransform(transform)

        return layer
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
        let dstScale: CGFloat = 1.0 // The size is specified in pixels, not in points.

        let hasAlpha = NSData.hasAlpha(forValidImageFilePath: model.currentImagePath)

        guard let srcImage = UIImage(contentsOfFile: model.currentImagePath) else {
            owsFailDebug("Could not load src image.")
            return nil
        }

        // We use an UIImageView + UIView.renderAsImage() instead of a CGGraphicsContext
        // Because CALayer.renderInContext() doesn't honor CALayer properties like frame,
        // transform, etc.
        let imageView = UIImageView(image: srcImage)
        imageView.frame = CGRect(origin: .zero, size: dstSizePixels)
        for item in model.items() {
            guard let layer = layerForItem(item: item,
                                           viewSize: dstSizePixels) else {
                                            Logger.error("Couldn't create layer for item.")
                                            continue
            }
            layer.contentsScale = dstScale * item.outputScale()
            imageView.layer.addSublayer(layer)
        }
        let image = imageView.renderAsImage(opaque: !hasAlpha, scale: dstScale)
        return image
    }

    // MARK: - ImageEditorTextViewControllerDelegate

    public func textEditDidComplete(textItem: ImageEditorTextItem, text: String?) {
        AssertIsOnMainThread()

        isEditingTextItem = false

        guard let text = text?.ows_stripped(),
            text.count > 0 else {
                if model.has(itemForId: textItem.itemId) {
                    model.remove(item: textItem)
                }
                return
        }

        // Model items are immutable; we _replace_ the item rather than modify it.
        let newItem = textItem.copy(withText: text)
        if model.has(itemForId: textItem.itemId) {
            model.replace(item: newItem, suppressUndo: false)
        } else {
            model.append(item: newItem)
        }
    }

    public func textEditDidCancel() {
        isEditingTextItem = false
    }

    // MARK: - UIGestureRecognizerDelegate

    @objc public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let editorGestureRecognizer = editorGestureRecognizer else {
            owsFailDebug("Missing editorGestureRecognizer.")
            return false
        }
        guard editorGestureRecognizer == gestureRecognizer else {
            owsFailDebug("Unexpected gesture.")
            return false
        }
        guard editorMode == .none else {
            // We only filter touches when in default mode.
            return true
        }

        let isInTextArea = textLayer(forTouch: touch) != nil
        return isInTextArea
    }

    private func textLayer(forTouch touch: UITouch) -> EditorTextLayer? {
        let point = touch.location(in: layersView)
        return textLayer(forLocation: point)
    }

    private func textLayer(forGestureRecognizer gestureRecognizer: UIGestureRecognizer) -> EditorTextLayer? {
        let point = gestureRecognizer.location(in: layersView)
        return textLayer(forLocation: point)
    }

    private func textLayer(forLocation point: CGPoint) -> EditorTextLayer? {
        guard let sublayers = layersView.layer.sublayers else {
            return nil
        }
        for layer in sublayers {
            guard let textLayer = layer as? EditorTextLayer else {
                continue
            }
            if textLayer.hitTest(point) != nil {
                return textLayer
            }
        }
        return nil
    }
}
