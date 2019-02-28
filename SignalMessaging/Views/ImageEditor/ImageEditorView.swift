//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public protocol ImageEditorViewDelegate: class {
    func imageEditor(presentFullScreenOverlay viewController: UIViewController,
                     withNavigation: Bool)
    func imageEditorPresentCaptionView()
}

// MARK: -

// A view for editing outgoing image attachments.
// It can also be used to render the final output.
@objc
public class ImageEditorView: UIView {

    weak var delegate: ImageEditorViewDelegate?

    private let model: ImageEditorModel

    private let canvasView: ImageEditorCanvasView

    private let paletteView = ImageEditorPaletteView()

    enum EditorMode: String {
        // This is the default mode.  It is used for interacting with text items.
        case none
        case brush
        case text
    }

    private var editorMode = EditorMode.none {
        didSet {
            AssertIsOnMainThread()

            updateButtons()
            updateGestureState()
        }
    }

    private var currentColor: UIColor {
        get {
            return paletteView.selectedColor
        }
    }

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
        canvasView.autoPinEdgesToSuperviewEdges()

        paletteView.delegate = self

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

    // The model supports redo if we ever want to add it.
    private let undoButton = OWSButton()
    private let brushButton = OWSButton()
    private let cropButton = OWSButton()
    private let newTextButton = OWSButton()
    private let captionButton = OWSButton()
    private let doneButton = OWSButton()
    private let buttonStackView = UIStackView()

    // TODO: Should this method be private?
    @objc
    public func addControls(to containerView: UIView,
                            viewController: UIViewController) {
        configure(button: undoButton,
                  imageName: "image_editor_undo",
                  selector: #selector(didTapUndo(sender:)))

        configure(button: brushButton,
                  imageName: "image_editor_brush",
                  selector: #selector(didTapBrush(sender:)))

        configure(button: cropButton,
                  imageName: "image_editor_crop",
                  selector: #selector(didTapCrop(sender:)))

        configure(button: newTextButton,
                  imageName: "image_editor_text",
                  selector: #selector(didTapNewText(sender:)))

        configure(button: captionButton,
                  imageName: "image_editor_caption",
                  selector: #selector(didTapCaption(sender:)))

        configure(button: doneButton,
                  imageName: "image_editor_checkmark_full",
                  selector: #selector(didTapDone(sender:)))

        buttonStackView.axis = .horizontal
        buttonStackView.alignment = .center
        buttonStackView.spacing = 20

        containerView.addSubview(buttonStackView)
        buttonStackView.autoPin(toTopLayoutGuideOf: viewController, withInset: 0)
        buttonStackView.autoPinTrailingToSuperviewMargin(withInset: 18)

        containerView.addSubview(paletteView)
        paletteView.autoVCenterInSuperview()
        paletteView.autoPinLeadingToSuperviewMargin(withInset: 10)

        updateButtons()
    }

    private func configure(button: UIButton,
                           imageName: String,
                           selector: Selector) {
        if let image = UIImage(named: imageName) {
            button.setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
        } else {
            owsFailDebug("Missing asset: \(imageName)")
        }
        button.tintColor = .white
        button.addTarget(self, action: selector, for: .touchUpInside)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowRadius = 4
        button.layer.shadowOpacity = 0.66
    }

    private func updateButtons() {
        var buttons = [OWSButton]()

        var hasPalette = false
        switch editorMode {
        case .text:
            // TODO:
            hasPalette = true
            break
        case .brush:
            hasPalette = true

            if model.canUndo() {
                buttons =  [undoButton, doneButton]
            } else {
                buttons =  [doneButton]
            }
        case .none:
            if model.canUndo() {
                buttons =  [undoButton, newTextButton, brushButton, cropButton, captionButton]
            } else {
                buttons =  [newTextButton, brushButton, cropButton, captionButton]
            }
        }

        for subview in buttonStackView.subviews {
            subview.removeFromSuperview()
        }
        buttonStackView.addArrangedSubview(UIView.hStretchingSpacer())
        for button in buttons {
            buttonStackView.addArrangedSubview(button)
        }

        paletteView.isHidden = !hasPalette
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

    @objc func didTapBrush(sender: UIButton) {
        Logger.verbose("")

        self.editorMode = .brush
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

    @objc func didTapCaption(sender: UIButton) {
        Logger.verbose("")

        delegate?.imageEditorPresentCaptionView()

//        // TODO:
//        let maxTextWidthPoints = model.srcImageSizePixels.width * ImageEditorTextItem.kDefaultUnitWidth
//        //        let maxTextWidthPoints = canvasView.imageView.width() * ImageEditorTextItem.kDefaultUnitWidth
//
//        let textEditor = ImageEditorTextViewController(delegate: self, textItem: textItem, maxTextWidthPoints: maxTextWidthPoints)
//        self.delegate?.imageEditor(presentFullScreenOverlay: textEditor,
//                                   withNavigation: true)

        // TODO:
    }

    @objc func didTapDone(sender: UIButton) {
        Logger.verbose("")

        self.editorMode = .none
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
        case .text:
            moveTextGestureRecognizer?.isEnabled = false
            brushGestureRecognizer?.isEnabled = false
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

    private func edit(textItem: ImageEditorTextItem) {
        Logger.verbose("")

       self.editorMode = .text

        // TODO:
        let maxTextWidthPoints = model.srcImageSizePixels.width * ImageEditorTextItem.kDefaultUnitWidth
        //        let maxTextWidthPoints = canvasView.imageView.width() * ImageEditorTextItem.kDefaultUnitWidth

        let textEditor = ImageEditorTextViewController(delegate: self, textItem: textItem, maxTextWidthPoints: maxTextWidthPoints)
        self.delegate?.imageEditor(presentFullScreenOverlay: textEditor,
                                   withNavigation: true)
    }

    // MARK: - Crop Tool

    private func presentCropTool() {
        Logger.verbose("")

        self.editorMode = .none

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
        self.delegate?.imageEditor(presentFullScreenOverlay: cropTool,
                                   withNavigation: false)
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

        self.editorMode = .none

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
        self.editorMode = .none
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

// MARK: -

extension ImageEditorView: ImageEditorPaletteViewDelegate {
    public func selectedColorDidChange() {
        // TODO:
    }
}
