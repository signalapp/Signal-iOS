//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalMessaging

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
class ImageEditorView: UIView {

    weak var delegate: ImageEditorViewDelegate?

    let model: ImageEditorModel

    let canvasView: ImageEditorCanvasView

    private let trashViewSize: CGFloat = 42
    private let trashViewHoverSize: CGFloat = 56
    private var trashSizeContstraints = [NSLayoutConstraint]()
    private lazy var trashView: UIView = {
        let image = UIImage(named: "trash-circle")
        let imageView = UIImageView(image: image)
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFill

        imageView.layer.cornerRadius = trashViewSize / 2
        imageView.backgroundColor = .ows_blackAlpha40
        imageView.isUserInteractionEnabled = false

        return imageView
    }()
    private var isTrashShowing: Bool {
        get {
            trashView.alpha > 0
        }
        set {
            trashView.alpha = newValue ? 1 : 0
        }
    }
    private var isHoveringOverTrash = false {
        didSet {
            guard isHoveringOverTrash != oldValue else { return }
            updateTrash(isHoveringOverTrash: isHoveringOverTrash)
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

        canvasView.contentView.addSubview(trashView)

        // Center trash view instead of aligning the bottom so that it
        // resizes from the center when hovering over it.
        // 20 spacing to bottom + half the height for the center point.
        let distanceFromCenterToBottom = 20 + trashViewSize / 2
        trashView.centerYAnchor.constraint(
            equalTo: canvasView.contentView.bottomAnchor,
            constant: -distanceFromCenterToBottom
        )
        .isActive = true

        trashView.autoHCenterInSuperview()
        trashSizeContstraints = trashView.autoSetDimensions(to: .square(trashViewSize))
        trashView.layer.zPosition = ImageEditorCanvasView.trashLazerZ
        isTrashShowing = false

        addGestureRecognizer(moveTextGestureRecognizer)
        addGestureRecognizer(tapGestureRecognizer)
        addGestureRecognizer(pinchGestureRecognizer)
        updateGestureRecognizers()

        let doubleTapGesture = UITapGestureRecognizer(target: nil, action: nil)
        doubleTapGesture.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGesture)
        tapGestureRecognizer.require(toFail: doubleTapGesture)
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

        let shouldShowTrash: Bool
        switch movingItem {
        case is ImageEditorStickerItem, is ImageEditorTextItem:
            shouldShowTrash = true
        default:
            shouldShowTrash = false
        }

        guard shouldShowTrash != isTrashShowing else { return }
        UIView.animate(withDuration: 0.15) {
            self.isTrashShowing = shouldShowTrash
        }
    }

    private func updateTrash(isHoveringOverTrash: Bool) {
        canvasView.shouldFadeTransformableItem = isHoveringOverTrash

        let size = isHoveringOverTrash ? self.trashViewHoverSize : self.trashViewSize
        self.trashSizeContstraints.forEach { $0.constant = size }

        UIView.animate(withDuration: 0.15) {
            self.trashView.layer.cornerRadius = size / 2
            self.layoutIfNeeded()
        }

        if isHoveringOverTrash {
            ImpactHapticFeedback.impactOccurred(style: .light)
        }
    }

    var shouldHideControls: Bool {
        // Hide controls during "text item move".
        return movingItem != nil
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

    var selectedTransformableItemID: String? {
        get {
            canvasView.selectedTransformableItemID
        }
        set {
            canvasView.selectedTransformableItemID = newValue
        }
    }

    func updateSelectedTextItem(withColor color: ColorPickerBarColor) {
        if let selectedTextItemId = selectedTransformableItemID,
           let textItem = model.item(forId: selectedTextItemId) as? ImageEditorTextItem {
            let newTextItem = textItem.copy(color: color)
            model.replace(item: newTextItem)
        }
    }

    func createNewTextItem(withColor color: ColorPickerBarColor = ColorPickerBarColor.white,
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

        let textItem = ImageEditorTextItem.empty(withColor: color,
                                                 textStyle: textStyle,
                                                 decorationStyle: decorationStyle,
                                                 unitWidth: textWidthUnit,
                                                 fontReferenceImageWidth: imageFrame.size.width,
                                                 scaling: scaling,
                                                 rotationRadians: rotationRadians)
        return textItem
    }

    func createNewStickerItem(with stickerInfo: StickerInfo) -> ImageEditorStickerItem {
        let viewSize = canvasView.gestureReferenceView.bounds.size
        let imageSize = model.srcImageSizePixels
        let imageFrame = ImageEditorCanvasView.imageFrame(
            forViewSize: viewSize,
            imageSize: imageSize,
            transform: model.currentTransform()
        )

        let rotationRadians = -model.currentTransform().rotationRadians
        let scaling = 1 / model.currentTransform().scaling

        return ImageEditorStickerItem(
            stickerInfo: stickerInfo,
            referenceImageWidth: imageFrame.size.width,
            rotationRadians: rotationRadians,
            scaling: scaling
        )
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
        guard let textLayer = transformableLayer(forLocation: location) else {
            // Different behavior when user taps on an empty area.

            // 1. Text objects are selectable: deselect anything previously selected.
            if textInteractionModes.contains(.select) {
                if selectedTransformableItemID != nil {
                    selectedTransformableItemID = nil
                    delegate?.imageEditorViewDidUpdateSelection(self)
                }
                return
            }

            // 2. Text objects aren't selectable: add a new text object.
            let newTextItem = createNewTextItem()
            delegate?.imageEditorView(self, didRequestAddTextItem: newTextItem)
            return
        }

        guard let itemID = textLayer.name,
              let item = model.item(forId: itemID) as? ImageEditorTransformable else {
            owsFailDebug("Missing or invalid text item.")
            return
        }

        // Text objects are selectable: select object if not selected yet...
        if textInteractionModes.contains(.select) && item.itemId != selectedTransformableItemID {
            selectedTransformableItemID = item.itemId
            delegate?.imageEditorViewDidUpdateSelection(self)
        }
        // ..otherwise report tap to delegate (this includes taps on selected text objects).
        else if let textItem = item as? ImageEditorTextItem {
            delegate?.imageEditorView(self, didTapTextItem: textItem)
        }
    }

    // MARK: - Pinch Gesture

    // These properties are valid while moving a text item.
    private var pinchingItem: (any ImageEditorTransformable)?
    private var pinchHasChanged = false

    @objc
    private func handlePinchGesture(_ gestureRecognizer: ImageEditorPinchGestureRecognizer) {
        AssertIsOnMainThread()

        // We could undo an in-progress pinch if the gesture is cancelled, but it seems gratuitous.

        switch gestureRecognizer.state {
        case .began:
            let pinchState = gestureRecognizer.pinchStateStart
            guard let textLayer = transformableLayer(forLocation: pinchState.centroid),
                  let itemID = textLayer.name,
                  itemID == selectedTransformableItemID else {
                // The pinch needs to start centered on selected text item.
                return
            }
            guard let item = model.item(forId: itemID) as? ImageEditorTransformable else {
                owsFailDebug("Missing or invalid text item.")
                return
            }
            pinchingItem = item
            pinchHasChanged = false

        case .changed, .ended:
            guard let item = pinchingItem else {
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
            let unitCenter = CGPointClamp01(item.unitCenter.plus(gestureDeltaImageUnit))

            // NOTE: We use max(1, ...) to avoid divide-by-zero.
            let newScaling = CGFloatClamp(item.scaling * gestureRecognizer.pinchStateLast.distance / max(1.0, gestureRecognizer.pinchStateStart.distance),
                                          ImageEditorTextItem.kMinScaling,
                                          ImageEditorTextItem.kMaxScaling)

            let newRotationRadians = item.rotationRadians + gestureRecognizer.pinchStateLast.angleRadians - gestureRecognizer.pinchStateStart.angleRadians

            let newItem = item.copy(unitCenter: unitCenter).copy(scaling: newScaling,
                                                                     rotationRadians: newRotationRadians)

            if pinchHasChanged {
                model.replace(item: newItem, suppressUndo: true)
            } else {
                model.replace(item: newItem, suppressUndo: false)
                pinchHasChanged = true
            }

            if gestureRecognizer.state == .ended {
                pinchingItem = nil
            }

        default:
            pinchingItem = nil
        }
    }

    // MARK: - Pan Gesture

    // These properties are valid while moving a text item.
    private var movingItem: (any ImageEditorTransformable)? {
        didSet {
            updateControls()
        }
    }
    private var movingTextStartUnitCenter: CGPoint?
    private var movingTextHasMoved = false

    private func transformableLayer(forLocation locationInView: CGPoint) -> CALayer? {
        let viewBounds = self.canvasView.gestureReferenceView.bounds
        let affineTransform = self.model.currentTransform().affineTransform(viewSize: viewBounds.size)
        let locationInCanvas = locationInView.minus(viewBounds.center).applyingInverse(affineTransform).plus(viewBounds.center)
        return canvasView.transformableLayer(forLocation: locationInCanvas)
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
            guard let textLayer = transformableLayer(forLocation: locationStart) else {
                owsFailDebug("No text layer")
                return
            }
            guard let itemID = textLayer.name,
                  let item = model.item(forId: itemID) as? ImageEditorTransformable else {
                owsFailDebug("Missing or invalid text item.")
                return
            }

            // Automatically make item selected if selections are allowed.
            if textInteractionModes.contains(.select) {
                selectedTransformableItemID = item.itemId
            }

            movingItem = item
            movingTextStartUnitCenter = item.unitCenter
            movingTextHasMoved = false

        case .changed, .ended:
            guard let item = movingItem else {
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
            let newItem = item.copy(unitCenter: unitCenter)

            if movingTextHasMoved {
                model.replace(item: newItem, suppressUndo: true)
            } else {
                model.replace(item: newItem, suppressUndo: false)
                movingTextHasMoved = true
            }

            isHoveringOverTrash = trashView.containsGestureLocation(gestureRecognizer)

            if gestureRecognizer.state == .ended {
                // Report that text object was moved.
                if let movingTextItem = movingItem as? ImageEditorTextItem {
                    delegate?.imageEditorView(self, didMoveTextItem: movingTextItem)
                }

                if isHoveringOverTrash, isTrashShowing {
                    // The last operation was moving the image over the trash.
                    // Pop that off the stack, so when the user presses undo
                    // after trashing an item, it goes to the position before
                    // the trash, instead of appearing over the trash.
                    model.undo()

                    model.remove(item: newItem)
                }

                movingItem = nil
                isHoveringOverTrash = false
            }
        default:
            movingItem = nil
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
        let isInTextArea = self.transformableLayer(forLocation: location) != nil
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
