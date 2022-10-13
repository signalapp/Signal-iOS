//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

protocol ImageEditorViewDelegate: AnyObject {

    func imageEditorView(_ imageEditorView: ImageEditorView, didRequestAddTextItem textItem: ImageEditorTextItem)

    func imageEditorView(_ imageEditorView: ImageEditorView, didTapTextItem textItem: ImageEditorTextItem)

    func imageEditorView(_ imageEditorView: ImageEditorView, didMoveTextItem textItem: ImageEditorTextItem)

    func imageEditorViewDidUpdateSelection(_ imageEditorView: ImageEditorView)

    func imageEditorDidRequestToolbarVisibilityUpdate(_ imageEditorView: ImageEditorView)
}

// MARK: -

// A view for editing outgoing image attachments.
// It can also be used to render the final output.
class ImageEditorView: AttachmentPrepContentView {

    weak var delegate: ImageEditorViewDelegate?

    let model: ImageEditorModel

    let canvasView: ImageEditorCanvasView

    override var contentLayoutMargins: UIEdgeInsets {
        didSet {
            canvasView.contentLayoutMargins = contentLayoutMargins
        }
    }

    required init(model: ImageEditorModel, delegate: ImageEditorViewDelegate?) {
        self.model = model
        self.delegate = delegate
        self.canvasView = ImageEditorCanvasView(model: model)

        super.init(frame: .zero)

        model.add(observer: self)
    }

    @available(*, unavailable, message: "use other init() instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Views

    private lazy var moveTextGestureRecognizer: ImageEditorPanGestureRecognizer = {
        let gestureRecognizer = ImageEditorPanGestureRecognizer(target: self, action: #selector(handleMoveTextGesture(_:)))
        gestureRecognizer.maximumNumberOfTouches = 1
        gestureRecognizer.referenceView = gestureReferenceView
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()
    private lazy var tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
    private lazy var pinchGestureRecognizer: ImageEditorPinchGestureRecognizer = {
        let gestureRecognizer = ImageEditorPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(_:)))
        gestureRecognizer.referenceView = gestureReferenceView
        return gestureRecognizer
    }()

    func configureSubviews() {
        canvasView.configureSubviews()
        addSubview(canvasView)
        canvasView.autoPinEdgesToSuperviewEdges()

        addGestureRecognizer(moveTextGestureRecognizer)
        addGestureRecognizer(tapGestureRecognizer)
        addGestureRecognizer(pinchGestureRecognizer)
        updateGestureRecognizers()
    }

    private func updateGestureRecognizers() {
        // Remove all gesture recognizers when interaction with text objects is disabled
        // so that they don't interfere with gesture recognizers added in view controller.

        moveTextGestureRecognizer.isEnabled = textInteractionModes.contains(.move)
        tapGestureRecognizer.isEnabled = textInteractionModes.contains(.tap)
        pinchGestureRecognizer.isEnabled = textInteractionModes.contains(.resize)
    }

    final var gestureReferenceView: UIView {
        canvasView.gestureReferenceView
    }

    // MARK: - Navigation Bar

    private func updateControls() {
        delegate?.imageEditorDidRequestToolbarVisibilityUpdate(self)
    }

    var shouldHideControls: Bool {
        // Hide controls during "text item move".
        return movingTextItem != nil
    }

    struct TextInteractionModes: OptionSet {
        let rawValue: Int

        static let tap    = TextInteractionModes(rawValue: 1 << 0)
        static let select = TextInteractionModes(rawValue: 1 << 1 | 1 << 0) // "select" requires "tap" to be supported
        static let move   = TextInteractionModes(rawValue: 1 << 2)
        static let resize = TextInteractionModes(rawValue: 1 << 3)

        static let all: TextInteractionModes = [ .tap, .select, .move, .resize ]
    }

    var textInteractionModes: TextInteractionModes = [] {
        didSet {
            updateGestureRecognizers()
        }
    }

    // MARK: - Tap Gesture

    var selectedTextItemId: String? {
        get {
            canvasView.selectedTextItemId
        }
        set {
            canvasView.selectedTextItemId = newValue
        }
    }

    func updateSelectedTextItem(withColor color: ColorPickerBarColor) {
        if let selectedTextItemId = selectedTextItemId,
           let textItem = model.item(forId: selectedTextItemId) as? ImageEditorTextItem {
            let newTextItem = textItem.copy(color: color)
            model.replace(item: newTextItem)
        }
    }

    func createNewTextItem(withColor color: ColorPickerBarColor? = nil,
                           textStyle: MediaTextView.TextStyle = .regular,
                           decorationStyle: MediaTextView.DecorationStyle = .none) -> ImageEditorTextItem {
        Logger.verbose("")

        let viewSize = canvasView.gestureReferenceView.bounds.size
        let imageSize = model.srcImageSizePixels
        let imageFrame = ImageEditorCanvasView.imageFrame(forViewSize: viewSize, imageSize: imageSize,
                                                          transform: model.currentTransform())

        let textWidthPoints = viewSize.width * ImageEditorTextItem.kDefaultUnitWidth
        let textWidthUnit = textWidthPoints / imageFrame.size.width

        // New items should be aligned "upright", so they should have the _opposite_
        // of the current transform rotation.
        let rotationRadians = -model.currentTransform().rotationRadians
        // Similarly, the size of the text item shuo
        let scaling = 1 / model.currentTransform().scaling

        let textItem = ImageEditorTextItem.empty(withColor: color ?? model.color,
                                                 textStyle: textStyle,
                                                 decorationStyle: decorationStyle,
                                                 unitWidth: textWidthUnit,
                                                 fontReferenceImageWidth: imageFrame.size.width,
                                                 scaling: scaling,
                                                 rotationRadians: rotationRadians)
        return textItem
    }

    @objc
    private func handleTapGesture(_ gestureRecognizer: UIGestureRecognizer) {
        AssertIsOnMainThread()

        guard gestureRecognizer.state == .recognized else {
            owsFailDebug("Unexpected state.")
            return
        }

        guard textInteractionModes.contains(.tap) else {
            owsFailDebug("Unexpected text interaction mode [\(textInteractionModes)].")
            return
        }

        let location = gestureRecognizer.location(in: canvasView.gestureReferenceView)
        guard let textLayer = textLayer(forLocation: location) else {
            // Different behavior when user taps on an empty area.

            // 1. Text objects are selectable: deselect anything previously selected.
            if textInteractionModes.contains(.select) {
                if selectedTextItemId != nil {
                    selectedTextItemId = nil
                    delegate?.imageEditorViewDidUpdateSelection(self)
                }
                return
            }

            // 2. Text objects aren't selectable: add a new text object.
            let newTextItem = createNewTextItem()
            delegate?.imageEditorView(self, didRequestAddTextItem: newTextItem)
            return
        }

        guard let textItem = model.item(forId: textLayer.itemId) as? ImageEditorTextItem else {
            owsFailDebug("Missing or invalid text item.")
            return
        }

        // Text objects are selectable: select object if not selected yet...
        if textInteractionModes.contains(.select) && textItem.itemId != selectedTextItemId {
            selectedTextItemId = textItem.itemId
            delegate?.imageEditorViewDidUpdateSelection(self)
        }
        // ..otherwise report tap to delegate (this includes taps on selected text objects).
        else {
            delegate?.imageEditorView(self, didTapTextItem: textItem)
        }
    }

    // MARK: - Pinch Gesture

    // These properties are valid while moving a text item.
    private var pinchingTextItem: ImageEditorTextItem?
    private var pinchHasChanged = false

    @objc
    private func handlePinchGesture(_ gestureRecognizer: ImageEditorPinchGestureRecognizer) {
        AssertIsOnMainThread()

        // We could undo an in-progress pinch if the gesture is cancelled, but it seems gratuitous.

        switch gestureRecognizer.state {
        case .began:
            let pinchState = gestureRecognizer.pinchStateStart
            guard let textLayer = textLayer(forLocation: pinchState.centroid),
                  textLayer.itemId == selectedTextItemId else {
                // The pinch needs to start centered on selected text item.
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

            let view = canvasView.gestureReferenceView
            let viewBounds = view.bounds
            let locationStart = gestureRecognizer.pinchStateStart.centroid
            let locationNow = gestureRecognizer.pinchStateLast.centroid
            let gestureStartImageUnit = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationStart,
                                                                                viewBounds: viewBounds,
                                                                                model: model,
                                                                                transform: model.currentTransform())
            let gestureNowImageUnit = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationNow,
                                                                              viewBounds: viewBounds,
                                                                              model: model,
                                                                              transform: model.currentTransform())
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
    private func handleMoveTextGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer) {
        AssertIsOnMainThread()

        guard textInteractionModes.contains(.move) else {
            owsFailDebug("Unexpected text interaction mode [\(textInteractionModes)].")
            return
        }

        // We could undo an in-progress move if the gesture is cancelled, but it seems gratuitous.

        switch gestureRecognizer.state {
        case .began:
            guard let locationStart = gestureRecognizer.locationFirst else {
                owsFailDebug("Missing locationStart.")
                return
            }
            guard let textLayer = textLayer(forLocation: locationStart) else {
                owsFailDebug("No text layer")
                return
            }
            guard let textItem = model.item(forId: textLayer.itemId) as? ImageEditorTextItem else {
                owsFailDebug("Missing or invalid text item.")
                return
            }

            // Automatically make item selected if selections are allowed.
            if textInteractionModes.contains(.select) {
                selectedTextItemId = textItem.itemId
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

            let view = canvasView.gestureReferenceView
            let viewBounds = view.bounds
            let locationInView = gestureRecognizer.location(in: view)
            let gestureStartImageUnit = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationStart,
                                                                          viewBounds: viewBounds,
                                                                          model: model,
                                                                          transform: model.currentTransform())
            let gestureNowImageUnit = ImageEditorCanvasView.locationImageUnit(forLocationInView: locationInView,
                                                                        viewBounds: viewBounds,
                                                                        model: model,
                                                                        transform: model.currentTransform())
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
                // Report that text object was moved.
                if let movingTextItem = movingTextItem {
                    delegate?.imageEditorView(self, didMoveTextItem: movingTextItem)
                }

                movingTextItem = nil
            }
        default:
            movingTextItem = nil
        }
    }
}

// MARK: - Corner Radius

extension ImageEditorView {

    static let defaultCornerRadius: CGFloat = 18

    func setHasRoundCorners(_ roundCorners: Bool, animationDuration: TimeInterval = 0) {
        canvasView.setCornerRadius(roundCorners ? ImageEditorView.defaultCornerRadius : 0,
                                   animationDuration: animationDuration)
    }
}

// MARK: -

extension ImageEditorView: UIGestureRecognizerDelegate {

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
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

    func imageEditorModelDidChange(before: ImageEditorContents, after: ImageEditorContents) {
    }

    func imageEditorModelDidChange(changedItemIds: [String]) {
    }
}
