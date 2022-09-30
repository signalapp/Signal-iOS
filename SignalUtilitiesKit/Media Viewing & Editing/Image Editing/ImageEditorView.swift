//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import SessionUtilitiesKit

@objc
public protocol ImageEditorViewDelegate: AnyObject {
    func imageEditor(presentFullScreenView viewController: UIViewController,
                     isTransparent: Bool)
    func imageEditorUpdateNavigationBar()
    func imageEditorUpdateControls()
}

// MARK: -

// A view for editing outgoing image attachments.
// It can also be used to render the final output.
@objc
public class ImageEditorView: UIView {

    weak var delegate: ImageEditorViewDelegate?

    private let model: ImageEditorModel

    private let canvasView: ImageEditorCanvasView

    // TODO: We could hang this on the model or make this static
    //       if we wanted more color continuity.
    private var currentColor = ImageEditorColor.defaultColor()

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
    private var tapGestureRecognizer: UITapGestureRecognizer?
    private var pinchGestureRecognizer: ImageEditorPinchGestureRecognizer?

    @objc
    public func configureSubviews() -> Bool {
        canvasView.configureSubviews()
        self.addSubview(canvasView)
        canvasView.autoPinEdgesToSuperviewEdges()

        self.isUserInteractionEnabled = true

        let moveTextGestureRecognizer = ImageEditorPanGestureRecognizer(target: self, action: #selector(handleMoveTextGesture(_:)))
        moveTextGestureRecognizer.maximumNumberOfTouches = 1
        moveTextGestureRecognizer.referenceView = canvasView.gestureReferenceView
        moveTextGestureRecognizer.delegate = self
        self.addGestureRecognizer(moveTextGestureRecognizer)
        self.moveTextGestureRecognizer = moveTextGestureRecognizer

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

        return true
    }

    // MARK: - Navigation Bar

    private func updateNavigationBar() {
        delegate?.imageEditorUpdateNavigationBar()
    }

    public func navigationBarItems() -> [UIView] {
        guard !shouldHideControls else {
            return []
        }

        let undoButton = navigationBarButton(imageName: "image_editor_undo",
                                             selector: #selector(didTapUndo(sender:)))
        let brushButton = navigationBarButton(imageName: "image_editor_brush",
                                              selector: #selector(didTapBrush(sender:)))
        let cropButton = navigationBarButton(imageName: "image_editor_crop",
                                             selector: #selector(didTapCrop(sender:)))
        let newTextButton = navigationBarButton(imageName: "image_editor_text",
                                                selector: #selector(didTapNewText(sender:)))

        var buttons: [UIView]
        if model.canUndo() {
            buttons = [undoButton, newTextButton, brushButton, cropButton]
        } else {
            buttons = [newTextButton, brushButton, cropButton]
        }

        return buttons
    }

    private func updateControls() {
        delegate?.imageEditorUpdateControls()
    }

    public var shouldHideControls: Bool {
        // Hide controls during "text item move".
        return movingTextItem != nil
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

        let brushView = ImageEditorBrushViewController(
            delegate: self,
            model: model,
            currentColor: currentColor,
            bottomInset: ((self.superview?.frame.height ?? 0) - self.frame.height)
        )
        self.delegate?.imageEditor(presentFullScreenView: brushView,
                                   isTransparent: false)
    }

    @objc func didTapCrop(sender: UIButton) {
        Logger.verbose("")

        presentCropTool()
    }

    @objc func didTapNewText(sender: UIButton) {
        Logger.verbose("")

        createNewTextItem()
    }

    private func createNewTextItem() {
        Logger.verbose("")

        let viewSize = canvasView.gestureReferenceView.bounds.size
        let imageSize =  model.srcImageSizePixels
        let imageFrame = ImageEditorCanvasView.imageFrame(forViewSize: viewSize, imageSize: imageSize,
                                                          transform: model.currentTransform())

        let textWidthPoints = viewSize.width * ImageEditorTextItem.kDefaultUnitWidth
        let textWidthUnit = textWidthPoints / imageFrame.size.width

        // New items should be aligned "upright", so they should have the _opposite_
        // of the current transform rotation.
        let rotationRadians = -model.currentTransform().rotationRadians
        // Similarly, the size of the text item shuo
        let scaling = 1 / model.currentTransform().scaling

        let textItem = ImageEditorTextItem.empty(withColor: currentColor,
                                                 unitWidth: textWidthUnit,
                                                 fontReferenceImageWidth: imageFrame.size.width,
                                                 scaling: scaling,
                                                 rotationRadians: rotationRadians)

        edit(textItem: textItem, isNewItem: true)
    }

    @objc func didTapDone(sender: UIButton) {
        Logger.verbose("")
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
            // If there is no text item under the "tap", start a new one.
            createNewTextItem()
            return
        }

        guard let textItem = model.item(forId: textLayer.itemId) as? ImageEditorTextItem else {
            owsFailDebug("Missing or invalid text item.")
            return
        }

        edit(textItem: textItem, isNewItem: false)
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
            let gestureStartImageUnit = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationStart,
                                                                          viewBounds: viewBounds,
                                                                          model: self.model,
                                                                          transform: self.model.currentTransform())
            let gestureNowImageUnit = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationNow,
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

            let newItem = textItem.copy(unitCenter: unitCenter).copy(scaling: newScaling,
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
    private var movingTextItem: ImageEditorTextItem? {
        didSet {
            updateNavigationBar()
            updateControls()
        }
    }
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
            guard let locationStart = gestureRecognizer.locationFirst else {
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
            guard let locationStart = gestureRecognizer.locationFirst else {
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
            let gestureStartImageUnit = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationStart,
                                                                          viewBounds: viewBounds,
                                                                          model: self.model,
                                                                          transform: self.model.currentTransform())
            let gestureNowImageUnit = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationInView,
                                                                        viewBounds: viewBounds,
                                                                        model: self.model,
                                                                        transform: self.model.currentTransform())
            let gestureDeltaImageUnit = gestureNowImageUnit.minus(gestureStartImageUnit)
            let unitCenter = CGPointClamp01(movingTextStartUnitCenter.plus(gestureDeltaImageUnit))
            let newItem = textItem.copy(unitCenter: unitCenter)

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
            let newSample = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationInView,
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

        let strokeColor = currentColor.color
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

    // MARK: - Edit Text Tool

    private func edit(textItem: ImageEditorTextItem, isNewItem: Bool) {
        Logger.verbose("")

        // TODO:
        let maxTextWidthPoints = model.srcImageSizePixels.width * ImageEditorTextItem.kDefaultUnitWidth
        //        let maxTextWidthPoints = canvasView.imageView.width() * ImageEditorTextItem.kDefaultUnitWidth

        let textEditor = ImageEditorTextViewController(
            delegate: self,
            model: model,
            textItem: textItem,
            isNewItem: isNewItem,
            maxTextWidthPoints: maxTextWidthPoints,
            bottomInset: ((self.superview?.frame.height ?? 0) - self.frame.height)
        )
        self.delegate?.imageEditor(presentFullScreenView: textEditor,
                                   isTransparent: false)
    }

    // MARK: - Crop Tool

    private func presentCropTool() {
        Logger.verbose("")

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
        self.delegate?.imageEditor(presentFullScreenView: cropTool,
                                   isTransparent: false)
    }
}

// MARK: -

extension ImageEditorView: UIGestureRecognizerDelegate {

    @objc public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard moveTextGestureRecognizer == gestureRecognizer else {
            owsFailDebug("Unexpected gesture.")
            return false
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
        updateNavigationBar()
    }

    public func imageEditorModelDidChange(changedItemIds: [String]) {
        updateNavigationBar()
    }
}

// MARK: -

extension ImageEditorView: ImageEditorTextViewControllerDelegate {

    public func textEditDidComplete(textItem: ImageEditorTextItem) {
        AssertIsOnMainThread()

        // Model items are immutable; we _replace_ the item rather than modify it.
        if model.has(itemForId: textItem.itemId) {
            model.replace(item: textItem, suppressUndo: false)
        } else {
            model.append(item: textItem)
        }

        self.currentColor = textItem.color
    }

    public func textEditDidDelete(textItem: ImageEditorTextItem) {
        AssertIsOnMainThread()

        if model.has(itemForId: textItem.itemId) {
            model.remove(item: textItem)
        }
    }

    public func textEditDidCancel() {
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

extension ImageEditorView: ImageEditorBrushViewControllerDelegate {
    public func brushDidComplete(currentColor: ImageEditorColor) {
        self.currentColor = currentColor
    }
}
