//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalMessaging
import UIKit

// Base class for all tool view controllers.

class ImageEditorViewController: OWSViewController {

    let model: ImageEditorModel

    // We only want to let users undo changes made in this view.
    // So we snapshot any older "operation id" and prevent
    // users from undoing it.
    private let firstUndoOperationId: String?

    let imageEditorView: ImageEditorView

    let topBar = ImageEditorTopBar()

    lazy var bottomBar: ImageEditorBottomBar = ImageEditorBottomBar(buttonProvider: self)

    enum Mode: Int {
        case draw = 1
        case blur
        case text
    }

    var mode: Mode = .draw {
        didSet {
            if oldValue != mode && isViewLoaded {
                updateUIForCurrentMode()
            }
        }
    }

    /**
     * Returns maximum width for the area with tool-specific UI elements in the toolbar at the bottom.
     * Such tool-specific elements are: color picker (for both text and drawing tools), text style selection button etc.
     * This maximum width is calculated as:
     * iPhone: screen width in portrait orientation minus standard horizontal margins.
     * iPad: value from iPhone 13 Max (428 - 2x20)
     */
    static let preferredToolbarContentWidth: CGFloat = {
        if UIDevice.current.isIPad {
            return 388
        } else {
            let screenWidth = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
            let inset: CGFloat = UIDevice.current.isPlusSizePhone ? 20 : 16
            return screenWidth - 2*inset
        }
    }()

    // Pen Tool UI
    var drawToolUIInitialized = false
    lazy var drawToolbar: DrawToolbar = {
        let toolbar = DrawToolbar(currentColor: model.color)
        toolbar.preservesSuperviewLayoutMargins = true
        toolbar.colorPickerView.delegate = self
        toolbar.strokeTypeButton.addTarget(self, action: #selector(strokeTypeButtonTapped(sender:)), for: .touchUpInside)
        return toolbar
    }()
    lazy var drawToolGestureRecognizer: ImageEditorPanGestureRecognizer = {
        let gestureRecognizer = ImageEditorPanGestureRecognizer(target: self, action: #selector(handleDrawToolGesture(_:)))
        gestureRecognizer.maximumNumberOfTouches = 1
        gestureRecognizer.referenceView = imageEditorView.gestureReferenceView
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()

    // Blur Tool UI
    var blurToolUIInitialized = false
    lazy var blurToolbar: UIStackView = {
        let drawAnywhereHint = UILabel()
        drawAnywhereHint.font = .dynamicTypeCaption1
        drawAnywhereHint.textColor = Theme.darkThemePrimaryColor
        drawAnywhereHint.textAlignment = .center
        drawAnywhereHint.numberOfLines = 0
        drawAnywhereHint.lineBreakMode = .byWordWrapping
        drawAnywhereHint.text = OWSLocalizedString("IMAGE_EDITOR_BLUR_HINT",
                                                   comment: "The image editor hint that you can draw blur")
        drawAnywhereHint.layer.shadowColor = UIColor.black.cgColor
        drawAnywhereHint.layer.shadowRadius = 2
        drawAnywhereHint.layer.shadowOpacity = 0.66
        drawAnywhereHint.layer.shadowOffset = .zero

        let stackView = UIStackView()
        stackView.alignment = .center
        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.addArrangedSubviews([ faceBlurContainer, drawAnywhereHint ])
        return stackView
    }()
    lazy var faceBlurContainer: UIView = {
        let containerView = PillView()
        containerView.layoutMargins = UIEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 8)

        let blurBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        containerView.addSubview(blurBackgroundView)
        blurBackgroundView.autoPinEdgesToSuperviewEdges()

        let autoBlurLabel = UILabel()
        autoBlurLabel.text = OWSLocalizedString("IMAGE_EDITOR_BLUR_SETTING",
                                                comment: "The image editor setting to blur faces")
        autoBlurLabel.font = .dynamicTypeSubheadlineClamped
        autoBlurLabel.textColor = Theme.darkThemePrimaryColor

        let stackView = UIStackView(arrangedSubviews: [ autoBlurLabel, faceBlurSwitch ])
        stackView.spacing = 12
        stackView.alignment = .center
        stackView.axis = .horizontal
        containerView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        return containerView
    }()
    lazy var faceBlurSwitch: UISwitch = {
        let faceBlurSwitch = UISwitch()
        faceBlurSwitch.addTarget(self, action: #selector(didToggleAutoBlur), for: .valueChanged)
        faceBlurSwitch.isOn = currentAutoBlurItem != nil
        return faceBlurSwitch
    }()
    lazy var blurToolGestureRecognizer: ImageEditorPanGestureRecognizer = {
        let gestureRecognizer = ImageEditorPanGestureRecognizer(target: self, action: #selector(handleBlurToolGesture(_:)))
        gestureRecognizer.maximumNumberOfTouches = 1
        gestureRecognizer.referenceView = imageEditorView.gestureReferenceView
        gestureRecognizer.delegate = self
        return gestureRecognizer
    }()
    // We persist an auto blur identifier for this session so
    // we can keep the toggle switch in sync with undo/redo behavior
    static let autoBlurItemIdentifier = "autoBlur"
    var currentAutoBlurItem: ImageEditorBlurRegionsItem? {
        return model.item(forId: ImageEditorViewController.autoBlurItemIdentifier) as? ImageEditorBlurRegionsItem
    }

    // Pen / Blur Drawing
    lazy var strokeWidthSlider: ImageEditorSlider = {
        let slider = ImageEditorSlider()
        slider.minimumValue = 0.2
        slider.maximumValue = 2
        slider.value = 1
        slider.addTarget(self, action: #selector(handleSliderTouchEvents(slider:)), for: .allTouchEvents)
        slider.addTarget(self, action: #selector(handleSliderValueChanged(slider:)), for: .valueChanged)
        return slider
    }()
    lazy var strokeWidthSliderContainer = UIView()
    lazy var strokeWidthPreviewDot: UIView = {
        let view = CircleView()
        view.layer.borderColor = UIColor.white.cgColor
        view.layer.borderWidth = 2
        strokeWidthPreviewDotSize = view.autoSetDimension(.width, toSize: 20)
        view.autoPinToSquareAspectRatio()
        return view
    }()
    var strokeWidthPreviewDotSize: NSLayoutConstraint?
    var strokeWidthSliderIsTrackingObservation: NSKeyValueObservation?
    var strokeWidthSliderRevealed = false
    var hideStrokeWidthSliderTimer: Timer?
    var strokeWidthSliderPosition: NSLayoutConstraint?
    var strokeWidthValues: [ImageEditorStrokeItem.StrokeType: Float] = [:]
    var currentStrokeType: ImageEditorStrokeItem.StrokeType = .pen {
        didSet {
            updateStrokeWidthSliderValue()
            updateStrokeWidthPreviewSize()
            updateStrokeWidthPreviewColor()
        }
    }
    var currentStroke: ImageEditorStrokeItem? {
        didSet {
            updateControlsVisibility()
            updateTopBar()
        }
    }
    var currentStrokeSamples = [ImageEditorStrokeItem.StrokeSample]()
    func currentStrokeUnitWidth() -> CGFloat {
        let unitStrokeWidth = ImageEditorStrokeItem.unitStrokeWidth(forStrokeType: currentStrokeType,
                                                                    widthAdjustmentFactor: CGFloat(strokeWidthSlider.value))
        return unitStrokeWidth / model.currentTransform().scaling
    }

    // Text UI
    var textUIInitialized = false
    var startEditingTextOnViewAppear = false
    var currentTextItem: (textItem: ImageEditorTextItem, isNewItem: Bool)?
    var pinchFontSizeStart: CGFloat = ImageEditorTextItem.defaultFontSize
    var textViewContainerBottomConstraint: NSLayoutConstraint? // to bottom of self.view
    lazy var textViewContainer: UIView = {
        let view = UIView(frame: view.bounds)
        view.preservesSuperviewLayoutMargins = true
        view.alpha = 0
        return view
    }()
    lazy var textView: MediaTextView = {
        let textView = MediaTextView()
        textView.delegate = self
        return textView
    }()
    lazy var textViewWrapperView = UIView()
    lazy var textViewBackgroundView = UIView()
    lazy var textViewAccessoryToolbar: TextStylingToolbar = {
        let toolbar = TextStylingToolbar(currentColor: currentTextItem?.textItem.color)
        toolbar.preservesSuperviewLayoutMargins = true
        toolbar.addTarget(self, action: #selector(textColorDidChange), for: .valueChanged)
        toolbar.textStyleButton.addTarget(self, action: #selector(didTapTextStyleButton(sender:)), for: .touchUpInside)
        toolbar.decorationStyleButton.addTarget(self, action: #selector(didTapDecorationStyleButton(sender:)), for: .touchUpInside)
        toolbar.doneButton.addTarget(self, action: #selector(didTapTextEditingDoneButton(sender:)), for: .touchUpInside)
        return toolbar
    }()

    init(model: ImageEditorModel) {
        self.model = model
        self.imageEditorView = ImageEditorView(model: model, delegate: nil)
        self.firstUndoOperationId = model.currentUndoOperationId()

        super.init()

        model.add(observer: self)
    }

    override func viewDidLoad() {
        view.backgroundColor = .black

        imageEditorView.configureSubviews()
        view.addSubview(imageEditorView)
        imageEditorView.autoPinWidthToSuperview()
        imageEditorView.autoPinEdge(toSuperviewSafeArea: .top)

        // Top toolbar
        updateTopBar()
        topBar.undoButton.addTarget(self, action: #selector(didTapUndo(sender:)), for: .touchUpInside)
        topBar.clearAllButton.addTarget(self, action: #selector(didTapClearAll(sender:)), for: .touchUpInside)
        topBar.install(in: view)

        // Bottom toolbar
        view.addSubview(bottomBar)
        bottomBar.autoPinWidthToSuperview()
        bottomBar.autoPinEdge(toSuperviewEdge: .bottom)
        bottomBar.autoPinEdge(.top, to: .bottom, of: imageEditorView)
        bottomBar.cancelButton.addTarget(self, action: #selector(didTapCancel(sender:)), for: .touchUpInside)
        bottomBar.doneButton.addTarget(self, action: #selector(didTapDone(sender:)), for: .touchUpInside)

        // Stroke width slider
        strokeWidthSliderContainer.addSubview(strokeWidthSlider)
        strokeWidthSlider.autoPinEdgesToSuperviewMargins()
        strokeWidthSliderContainer.layoutMargins = UIEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        strokeWidthSliderContainer.transform = CGAffineTransform(rotationAngle: -.halfPi)
        view.addSubview(strokeWidthSliderContainer)
        strokeWidthSliderContainer.autoVCenterInSuperview()
        strokeWidthSliderPosition = strokeWidthSliderContainer.centerXAnchor.constraint(equalTo: view.leadingAnchor)
        strokeWidthSliderPosition?.autoInstall()
        strokeWidthSliderContainer.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleSliderContainerTap(_:))))

        updateUIForCurrentMode()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        UIView.performWithoutAnimation {
            transitionUI(toState: .initial, animated: false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        transitionUI(toState: .final, animated: true) { finished in
            guard finished else { return }
            if self.startEditingTextOnViewAppear && self.canBeginTextEditingOnViewAppear {
                self.beginTextEditing()
            }
            self.startEditingTextOnViewAppear = false
        }
    }

    override func keyboardFrameDidChange(_ newFrame: CGRect, animationDuration: TimeInterval, animationOptions: UIView.AnimationOptions) {
        super.keyboardFrameDidChange(newFrame, animationDuration: animationDuration, animationOptions: animationOptions)

        updateTextViewContainerBottomLayoutConstraint(forKeyboardFrame: newFrame)
    }

    override var prefersStatusBarHidden: Bool {
        !UIDevice.current.hasIPhoneXNotch && !UIDevice.current.isIPad && !CurrentAppContext().hasActiveCall
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    // MARK: -

    private func updateUIForCurrentMode() {
        switch mode {
        case .draw, .blur:
            strokeWidthSliderContainer.isHidden = false
            finishTextEditing(applyEdits: true)

        case .text:
            strokeWidthSliderContainer.isHidden = true
        }

        imageEditorView.textInteractionModes = {
            switch mode {
            case .draw, .blur: return [ .select ]
            case .text: return .all
            }
        }()

        updateDrawToolUIVisibility()
        updateBlurToolUIVisibility()
        updateTextUIVisibility()

        for button in bottomBar.buttons {
            button.isSelected = mode.rawValue == button.tag
        }
    }

    private func updateTopBar() {
        let canUndo = canUndo
        topBar.isUndoButtonHidden = !canUndo
        topBar.isClearAllButtonHidden = !canUndo
    }

    private var shouldHideControls: Bool {
        switch mode {
        case .draw, .blur:
            return currentStroke != nil

        case .text:
            return imageEditorView.shouldHideControls
        }
    }

    private var canUndo: Bool {
        model.canUndo() && firstUndoOperationId != model.currentUndoOperationId()
    }

    func updateControlsVisibility() {
        setControls(hidden: shouldHideControls, animated: true, slideButtonsInOut: false)
    }

    private func setControls(hidden: Bool, animated: Bool, slideButtonsInOut: Bool, completion: ((Bool) -> Void)? = nil) {
        if animated {
            UIView.animate(withDuration: 0.15,
                           animations: {
                self.setControls(hidden: hidden, slideButtonsInOut: slideButtonsInOut)

                // Animate layout changes made within bottomBar.setControls(hidden:).
                if slideButtonsInOut {
                    self.bottomBar.setNeedsDisplay()
                    self.bottomBar.layoutIfNeeded()
                }
            },
                           completion: completion)
        } else {
            setControls(hidden: hidden, slideButtonsInOut: slideButtonsInOut)
            completion?(true)
        }
    }

    private func setControls(hidden: Bool, slideButtonsInOut: Bool) {
        let alpha: CGFloat = hidden ? 0 : 1
        topBar.alpha = alpha
        bottomBar.alpha = alpha
        if slideButtonsInOut {
            bottomBar.setControls(hidden: hidden)
        }

        switch mode {
        case .draw:
            updateDrawToolControlsVisibility()

        case .blur:
            updateBlurToolControlsVisibility()

        case .text:
            updateTextControlsVisibility()
        }
    }

    private func modelDidChange() {
        updateTopBar()

        if blurToolUIInitialized {
            // If we undo/redo, we may remove or re-apply the auto blur
            faceBlurSwitch.isOn = currentAutoBlurItem != nil
        }
    }

    private func undo() {
        Logger.verbose("")
        guard canUndo else {
            owsFailDebug("Can't undo.")
            return
        }
        model.undo()
    }

    private func clearAll() {
        Logger.verbose("")

        if mode == .text {
            finishTextEditing(applyEdits: false)
        }

        while canUndo {
            model.undo()
        }
    }
}

// MARK: - Presenting / Dismissing {

extension ImageEditorViewController {

    private func prepareToDismiss(completion: ((Bool) -> Void)?) {
        if mode == .text {
            finishTextEditing(applyEdits: false)
        }
        transitionUI(toState: .initial, animated: true, completion: completion)
    }

    private func prepareToFinish(completion: ((Bool) -> Void)?) {
        if mode == .text {
            finishTextEditing(applyEdits: true)
        }
        transitionUI(toState: .initial, animated: true, completion: completion)
    }

    private func discardAndDismiss() {
        if canUndo {
            askToDiscardAllChanges {
                self.prepareToDismiss { finished in
                    guard finished else { return }
                    self.dismiss(animated: false)
                }
            }
        } else {
            prepareToDismiss { finished in
                guard finished else { return }
                self.dismiss(animated: false)
            }
        }
    }

    private func completeAndDismiss() {
        prepareToFinish { finished in
            guard finished else { return }
            self.dismiss(animated: false)
        }
    }

    private func askToDiscardAllChanges(_ completionHandler: (() -> Void)?) {
        let actionSheetTitle = OWSLocalizedString("MEDIA_EDITOR_DISCARD_ALL_CONFIRMATION_TITLE",
                                                  comment: "Media Editor: Title for the 'Discard Changes' confirmation prompt.")
        let actionSheetMessage = OWSLocalizedString("MEDIA_EDITOR_DISCARD_ALL_CONFIRMATION_MESSAGE",
                                                    comment: "Media Editor: Message for the 'Discard Changes' confirmation prompt.")
        let discardChangesButton = OWSLocalizedString("MEDIA_EDITOR_DISCARD_ALL_BUTTON",
                                                      comment: "Media Editor: Title for the button in 'Discard Changes' confirmation prompt.")
        let actionSheet = ActionSheetController(title: actionSheetTitle, message: actionSheetMessage, theme: .translucentDark)
        actionSheet.addAction(ActionSheetAction(title: discardChangesButton, style: .destructive, handler: { _ in
            self.clearAll()
            if let completionHandler = completionHandler {
                completionHandler()
            }
        }))
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel, handler: nil))
        presentActionSheet(actionSheet)
    }

    private enum UIState {
        case initial
        case final
    }

    private func transitionUI(toState state: UIState, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        setControls(hidden: state == .initial, animated: animated, slideButtonsInOut: true, completion: completion)
        imageEditorView.setHasRoundCorners(state == .initial, animationDuration: animated ? 0.15 : 0)
    }
}

// MARK: - Actions

extension ImageEditorViewController {

    @objc
    private func didTapUndo(sender: UIButton) {
        undo()
    }

    @objc
    private func didTapClearAll(sender: UIButton) {
        askToDiscardAllChanges(nil)
    }

    @objc
    private func didTapCancel(sender: UIButton) {
        Logger.verbose("")

        discardAndDismiss()
    }

    @objc
    private func didTapDone(sender: UIButton) {
        Logger.verbose("")

        completeAndDismiss()
    }

    @objc
    private func didTapPen(sender: UIButton) {
        Logger.verbose("")

        // Second tap on Pen icon switches editor to "text" mode.
        mode = (mode == .draw) ? .text : .draw
    }

    @objc
    private func didTapAddText(sender: UIButton) {
        Logger.verbose("")

        let decorationStyle = textViewAccessoryToolbar.decorationStyle
        let textColor = textViewAccessoryToolbar.currentColorPickerValue
        let textItem = imageEditorView.createNewTextItem(withColor: textColor, decorationStyle: decorationStyle)
        selectTextItem(textItem, isNewItem: true, startEditing: true)
    }

    @objc
    private func didTapAddSticker(sender: UIButton) {
        Logger.verbose("")

        mode = .text
    }

    @objc
    private func didTapBlur(sender: UIButton) {
        Logger.verbose("")

        // Second tap on Blur icon switches editor to "text" mode.
        mode = (mode == .blur) ? .text : .blur
    }

    @objc
    private func textColorDidChange(sender: TextStylingToolbar) {
        let textItemColor = sender.currentColorPickerValue
        imageEditorView.updateSelectedTextItem(withColor: textItemColor)
        if textView.isFirstResponder {
            updateTextViewAttributes(using: textViewAccessoryToolbar)
        }
    }
}

// MARK: - Bottom Bar

extension ImageEditorViewController: ImageEditorBottomBarButtonProvider {

    var middleButtons: [UIButton] {
        let penButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-toolbar-pen"), backgroundStyle: .solid(.clear))
        penButton.tag = Mode.draw.rawValue
        penButton.addTarget(self, action: #selector(didTapPen(sender:)), for: .touchUpInside)

        let textButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-toolbar-text"), backgroundStyle: .solid(.clear))
        textButton.addTarget(self, action: #selector(didTapAddText(sender:)), for: .touchUpInside)

//        let stickerButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-toolbar-emoji"), backgroundStyle: .solid(.clear))
//        stickerButton.addTarget(self, action: #selector(didTapAddSticker(sender:)), for: .touchUpInside)

        let blurButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-toolbar-blur"), backgroundStyle: .solid(.clear))
        blurButton.tag = Mode.blur.rawValue
        blurButton.addTarget(self, action: #selector(didTapBlur(sender:)), for: .touchUpInside)

        let buttons = [ penButton, textButton, blurButton ]
        for button in buttons {
            button.setBackgroundColor(.ows_white, for: .highlighted)
            button.setBackgroundColor(.ows_white, for: .selected)
            if let image = button.image(for: .normal),
               let tintedImage = image.asTintedImage(color: .ows_black) {
                button.setImage(tintedImage, for: .highlighted)
                button.setImage(tintedImage, for: .selected)
            }
        }

        return buttons
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ImageEditorViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Ignore touches that begin inside the control areas.
        switch mode {
        case .draw:
            guard !drawToolbar.bounds.contains(touch.location(in: drawToolbar)) else {
                return false
            }
            guard !strokeWidthSliderContainer.bounds.contains(touch.location(in: strokeWidthSliderContainer)) else {
                return false
            }
            return true

        case .blur:
            return !blurToolbar.bounds.contains(touch.location(in: blurToolbar))

        default:
            return true
        }
    }
}

// MARK: - ImageEditorModelObserver

extension ImageEditorViewController: ImageEditorModelObserver {

    func imageEditorModelDidChange(before: ImageEditorContents, after: ImageEditorContents) {
        modelDidChange()
    }

    func imageEditorModelDidChange(changedItemIds: [String]) {
        modelDidChange()
    }
}

// MARK: - ImageEditorPaletteViewDelegate

extension ImageEditorViewController: ColorPickerBarViewDelegate {

    func colorPickerBarView(_ pickerView: ColorPickerBarView, didSelectColor color: ColorPickerBarColor) {
        switch mode {
        case .draw:
            model.color = color
            updateStrokeWidthPreviewColor()

        default:
            owsAssertDebug(false, "Invalid mode [\(mode)]")
        }
    }
}
