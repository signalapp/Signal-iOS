//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public protocol ImageEditorViewDelegate: class {
    func imageEditor(presentFullScreenOverlay viewController: UIViewController)
}

// MARK: -

// A view for editing outgoing image attachments.
// It can also be used to render the final output.
@objc
public class ImageEditorView: UIView {

    weak var delegate: ImageEditorViewDelegate?

    private let model: ImageEditorModel

    private let canvasView: ImageEditorCanvasView

    enum EditorMode: String {
        // This is the default mode.  It is used for interacting with text items.
        case none
        case brush
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
    public required init(model: ImageEditorModel, delegate: ImageEditorViewDelegate) {
        self.model = model
        self.delegate = delegate
        self.canvasView = ImageEditorCanvasView(model: model)

        super.init(frame: .zero)

        model.add(observer: self)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: - Views

    private var moveTextGestureRecognizer: ImageEditorPanGestureRecognizer?
    private var brushGestureRecognizer: ImageEditorPanGestureRecognizer?
    private var tapGestureRecognizer: UITapGestureRecognizer?
    private var pinchGestureRecognizer: ImageEditorPinchGestureRecognizer?

    @objc
    public func configureSubviews() -> Bool {
        guard canvasView.configureSubviews() else {
            return false
        }
        self.addSubview(canvasView)
        canvasView.ows_autoPinToSuperviewEdges()

        self.isUserInteractionEnabled = true

        let moveTextGestureRecognizer = ImageEditorPanGestureRecognizer(target: self, action: #selector(handleMoveTextGesture(_:)))
        moveTextGestureRecognizer.maximumNumberOfTouches = 1
        moveTextGestureRecognizer.referenceView = canvasView.gestureReferenceView
        moveTextGestureRecognizer.delegate = self
        self.addGestureRecognizer(moveTextGestureRecognizer)
        self.moveTextGestureRecognizer = moveTextGestureRecognizer

        let brushGestureRecognizer = ImageEditorPanGestureRecognizer(target: self, action: #selector(handleBrushGesture(_:)))
        brushGestureRecognizer.maximumNumberOfTouches = 1
        brushGestureRecognizer.referenceView = canvasView.gestureReferenceView
        self.addGestureRecognizer(brushGestureRecognizer)
        self.brushGestureRecognizer = brushGestureRecognizer

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        self.addGestureRecognizer(tapGestureRecognizer)
        self.tapGestureRecognizer = tapGestureRecognizer

        let pinchGestureRecognizer = ImageEditorPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        pinchGestureRecognizer.referenceView = canvasView.gestureReferenceView
        self.addGestureRecognizer(pinchGestureRecognizer)
        self.pinchGestureRecognizer = pinchGestureRecognizer

        // De-conflict the GRs.
        //        editorGestureRecognizer.require(toFail: tapGestureRecognizer)
        //        editorGestureRecognizer.require(toFail: pinchGestureRecognizer)

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
        cropButton.isSelected = false
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

        presentCropTool()
    }

    @objc func didTapNewText(sender: UIButton) {
        Logger.verbose("")

        let viewSize = canvasView.gestureReferenceView.bounds.size
        let imageSize =  model.srcImageSizePixels
        let imageFrame = ImageEditorCanvasView.imageFrame(forViewSize: viewSize, imageSize: imageSize,
                                                          transform: model.currentTransform())

        let textWidthPoints = viewSize.width * ImageEditorTextItem.kDefaultUnitWidth
        let textWidthUnit = textWidthPoints / imageFrame.size.width

        let textItem = ImageEditorTextItem.empty(withColor: currentColor,
                                                 unitWidth: textWidthUnit,
                                                 fontReferenceImageWidth: imageFrame.size.width)

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
            moveTextGestureRecognizer?.isEnabled = true
            brushGestureRecognizer?.isEnabled = false
            tapGestureRecognizer?.isEnabled = true
            pinchGestureRecognizer?.isEnabled = true
        case .brush:
            // Brush strokes can start and end (and return from) outside the view.
            moveTextGestureRecognizer?.isEnabled = false
            brushGestureRecognizer?.isEnabled = true
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

        let location = gestureRecognizer.location(in: canvasView.gestureReferenceView)
        guard let textLayer = self.textLayer(forLocation: location) else {
            return
        }

        guard let textItem = model.item(forId: textLayer.itemId) as? ImageEditorTextItem else {
            owsFailDebug("Missing or invalid text item.")
            return
        }

        edit(textItem: textItem)
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
            guard let textLayer = self.textLayer(forLocation: pinchState.centroid) else {
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

            let view = self.canvasView.gestureReferenceView
            let viewBounds = view.bounds
            let locationStart = gestureRecognizer.pinchStateStart.centroid
            let locationNow = gestureRecognizer.pinchStateLast.centroid
            let gestureStartImageUnit = ImageEditorView.locationImageUnit(forLocationInView: locationStart,
                                                                          viewBounds: viewBounds,
                                                                          model: self.model,
                                                                          transform: self.model.currentTransform())
            let gestureNowImageUnit = ImageEditorView.locationImageUnit(forLocationInView: locationNow,
                                                                        viewBounds: viewBounds,
                                                                        model: self.model,
                                                                        transform: self.model.currentTransform())
            let gestureDeltaImageUnit = gestureNowImageUnit.minus(gestureStartImageUnit)
            let unitCenter = CGPointClamp01(textItem.unitCenter.plus(gestureDeltaImageUnit))

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

    // These properties are valid while moving a text item.
    private var movingTextItem: ImageEditorTextItem?
    private var movingTextStartUnitCenter: CGPoint?
    private var movingTextHasMoved = false

    private func textLayer(forLocation locationInView: CGPoint) -> EditorTextLayer? {
        let viewBounds = self.canvasView.gestureReferenceView.bounds
        let affineTransform = self.model.currentTransform().affineTransform(viewSize: viewBounds.size)
        let locationInCanvas = locationInView.minus(viewBounds.center).applyingInverse(affineTransform).plus(viewBounds.center)
        return canvasView.textLayer(forLocation: locationInCanvas)
    }

    @objc
    public func handleMoveTextGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer) {
        AssertIsOnMainThread()

        // We could undo an in-progress move if the gesture is cancelled, but it seems gratuitous.

        switch gestureRecognizer.state {
        case .began:
            guard let locationStart = gestureRecognizer.locationStart else {
                owsFailDebug("Missing locationStart.")
                return
            }
            guard let textLayer = self.textLayer(forLocation: locationStart) else {
                owsFailDebug("No text layer")
                return
            }
            guard let textItem = model.item(forId: textLayer.itemId) as? ImageEditorTextItem else {
                owsFailDebug("Missing or invalid text item.")
                return
            }
            movingTextItem = textItem
            movingTextStartUnitCenter = textItem.unitCenter
            movingTextHasMoved = false

        case .changed, .ended:
            guard let textItem = movingTextItem else {
                return
            }
            guard let locationStart = gestureRecognizer.locationStart else {
                owsFailDebug("Missing locationStart.")
                return
            }
            guard let movingTextStartUnitCenter = movingTextStartUnitCenter else {
                owsFailDebug("Missing movingTextStartUnitCenter.")
                return
            }

            let view = self.canvasView.gestureReferenceView
            let viewBounds = view.bounds
            let locationInView = gestureRecognizer.location(in: view)
            let gestureStartImageUnit = ImageEditorView.locationImageUnit(forLocationInView: locationStart,
                                                                          viewBounds: viewBounds,
                                                                          model: self.model,
                                                                          transform: self.model.currentTransform())
            let gestureNowImageUnit = ImageEditorView.locationImageUnit(forLocationInView: locationInView,
                                                                        viewBounds: viewBounds,
                                                                        model: self.model,
                                                                        transform: self.model.currentTransform())
            let gestureDeltaImageUnit = gestureNowImageUnit.minus(gestureStartImageUnit)
            let unitCenter = CGPointClamp01(movingTextStartUnitCenter.plus(gestureDeltaImageUnit))
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
            let view = self.canvasView.gestureReferenceView
            let viewBounds = view.bounds
            let locationInView = gestureRecognizer.location(in: view)
            let newSample = ImageEditorView.locationImageUnit(forLocationInView: locationInView,
                                                              viewBounds: viewBounds,
                                                              model: self.model,
                                                              transform: self.model.currentTransform())

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

    // MARK: - Coordinates

    private class func locationImageUnit(forLocationInView locationInView: CGPoint,
                                         viewBounds: CGRect,
                                         model: ImageEditorModel,
                                         transform: ImageEditorTransform) -> CGPoint {
        let imageFrame = ImageEditorCanvasView.imageFrame(forViewSize: viewBounds.size, imageSize: model.srcImageSizePixels, transform: transform)
        let affineTransformStart = transform.affineTransform(viewSize: viewBounds.size)
        let locationInContent = locationInView.minus(viewBounds.center).applyingInverse(affineTransformStart).plus(viewBounds.center)
        let locationImageUnit = locationInContent.toUnitCoordinates(viewBounds: imageFrame, shouldClamp: false)
        return locationImageUnit
    }

    // MARK: - Edit Text Tool

    private var isEditingTextItem = false {
        didSet {
            AssertIsOnMainThread()

            updateButtons()
        }
    }

    private func edit(textItem: ImageEditorTextItem) {
        Logger.verbose("")

        toggle(editorMode: .none)

        isEditingTextItem = true

        // TODO:
        let maxTextWidthPoints = model.srcImageSizePixels.width * ImageEditorTextItem.kDefaultUnitWidth
        //        let maxTextWidthPoints = canvasView.imageView.width() * ImageEditorTextItem.kDefaultUnitWidth

        let textEditor = ImageEditorTextViewController(delegate: self, textItem: textItem, maxTextWidthPoints: maxTextWidthPoints)
        self.delegate?.imageEditor(presentFullScreenOverlay: textEditor)
    }

    // MARK: - Crop Tool

    private func presentCropTool() {
        Logger.verbose("")

        toggle(editorMode: .none)

        guard let srcImage = canvasView.loadSrcImage() else {
            owsFailDebug("Couldn't load src image.")
            return
        }

        // We want to render a preview image that "flattens" all of the brush strokes, text items,
        // into the background image without applying the transform (e.g. rotating, etc.), so we
        // use a default transform.
        let previewTransform = ImageEditorTransform.defaultTransform(srcImageSizePixels: model.srcImageSizePixels)
        guard let previewImage = ImageEditorCanvasView.renderForOutput(model: model, transform: previewTransform) else {
            owsFailDebug("Couldn't generate preview image.")
            return
        }

        let cropTool = ImageEditorCropViewController(delegate: self, model: model, srcImage: srcImage, previewImage: previewImage)
        self.delegate?.imageEditor(presentFullScreenOverlay: cropTool)
    }}

// MARK: -

extension ImageEditorView: UIGestureRecognizerDelegate {

    @objc public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard moveTextGestureRecognizer == gestureRecognizer else {
            owsFailDebug("Unexpected gesture.")
            return false
        }
        guard editorMode == .none else {
            // We only filter touches when in default mode.
            return true
        }

        let location = touch.location(in: canvasView.gestureReferenceView)
        let isInTextArea = self.textLayer(forLocation: location) != nil
        return isInTextArea
    }
}

// MARK: -

extension ImageEditorView: ImageEditorModelObserver {

    public func imageEditorModelDidChange(before: ImageEditorContents,
                                          after: ImageEditorContents) {
        updateButtons()
    }

    public func imageEditorModelDidChange(changedItemIds: [String]) {
        updateButtons()
    }
}

// MARK: -

extension ImageEditorView: ImageEditorTextViewControllerDelegate {

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
}

// MARK: -

extension ImageEditorView: ImageEditorCropViewControllerDelegate {
    public func cropDidComplete(transform: ImageEditorTransform) {
        // TODO: Ignore no-change updates.
        model.replace(transform: transform)
    }

    public func cropDidCancel() {
        // TODO:
    }
}
