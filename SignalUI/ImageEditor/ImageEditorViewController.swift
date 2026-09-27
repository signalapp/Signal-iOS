//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

// Base class for all tool view controllers.

class ImageEditorViewController: OWSViewController, UIGestureRecognizerDelegate, UITextViewDelegate,
    ImageEditorModelObserver, ImageEditorViewDelegate, StickerPickerDelegate, StoryStickerPickerDelegate
{
    let model: ImageEditorModel
    private weak var stickerSheetDelegate: StickerPickerSheetDelegate?

    // We only want to let users undo changes made in this view.
    // So we snapshot any older "operation id" and prevent
    // users from undoing it.
    private let firstUndoOperationId: String?

    private let initialStateContentLayoutGuide = UILayoutGuide()
    private let finalStateContentLayoutGuide = UILayoutGuide()

    // Presenting view controller will set those before presenting.
    // The intent is to position image in the same position and with the same size
    // as in "review" screen (AttachmentPrepViewController).
    var initialContentInsets: UIEdgeInsets = .zero

    // Constraints between `imageEditorView` and one of the layout guides from above.
    // These constraints are updated when UI is switched from `initial` to `final` and vice versa
    // during present / dismiss animations.
    private var contentLayoutGuideConstraints = [NSLayoutConstraint]()

    let imageEditorView: ImageEditorView

    let topBar = ImageEditorTopBar()

    lazy var bottomBar = ImageEditorToolbar(tools: [.draw, .text, .sticker, .blur])

    enum Mode: Int {
        case draw = 1
        case blur
        case text
        case sticker
    }

    var mode: Mode = .draw {
        didSet {
            if oldValue != mode, isViewLoaded {
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
        guard let window = CurrentAppContext().mainWindow, UIDevice.current.isIPad == false else {
            return 388
        }
        let screenWidth = window.bounds.size.smallerAxis
        let inset = OWSTableViewController2.defaultHOuterMargin
        return screenWidth - 2 * inset
    }()

    static var toolbarSpacing: CGFloat = 24

    // Pen Tool UI
    var drawToolUIInitialized = false

    lazy var drawToolbar: DrawToolbar = {
        let toolbar = DrawToolbar(currentColor: model.color)
        toolbar.preservesSuperviewLayoutMargins = true
        toolbar.colorPickerBar.addAction(
            UIAction { [weak self] action in
                guard let self, let colorPickerView = action.sender as? ColorPickerBar else { return }
                self.colorPickerBarValueChanged(color: colorPickerView.color)
            },
            for: .valueChanged,
        )
        toolbar.strokeTypeButton.addAction(
            UIAction { [weak self] _ in self?.didTapStrokeTypeButton() },
            for: .primaryActionTriggered,
        )
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

    lazy var blurToolHintView: UIView = {
        let hintLabel = UILabel()
        hintLabel.font = .dynamicTypeSubheadlineClamped
        hintLabel.textColor = .Signal.label
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.text = OWSLocalizedString(
            "IMAGE_EDITOR_BLUR_HINT",
            comment: "The image editor hint that you can draw blur",
        )
        hintLabel.setContentHuggingHigh()

        let visualEffectView: UIVisualEffectView
        if #available(iOS 26, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = true
            visualEffectView = UIVisualEffectView(effect: glassEffect)
            visualEffectView.clipsToBounds = true
            visualEffectView.cornerConfiguration = .capsule(maximumRadius: 26)
        } else {
            visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
            visualEffectView.clipsToBounds = true
            visualEffectView.layer.cornerRadius = 16
        }
        visualEffectView.directionalLayoutMargins = .init(hMargin: 12, vMargin: 12)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.contentView.addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: visualEffectView.layoutMarginsGuide.topAnchor),
            hintLabel.leadingAnchor.constraint(equalTo: visualEffectView.layoutMarginsGuide.leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: visualEffectView.layoutMarginsGuide.trailingAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: visualEffectView.layoutMarginsGuide.bottomAnchor),
        ])

        return visualEffectView
    }()

    lazy var blurToolPanel: UIView = {
        let autoBlurLabel = UILabel()
        autoBlurLabel.text = OWSLocalizedString(
            "IMAGE_EDITOR_BLUR_FACES",
            comment: "The image editor tool (on/off switch) that detects and blurs faces in the photo.",
        )
        autoBlurLabel.font = .dynamicTypeBodyClamped
        autoBlurLabel.textColor = .Signal.label
        autoBlurLabel.setContentHuggingHigh()

        let stackView = UIStackView(arrangedSubviews: [autoBlurLabel, faceBlurSwitch])
        stackView.spacing = 32
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let visualEffectView: UIVisualEffectView
        if #available(iOS 26, *) {
            visualEffectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            visualEffectView.cornerConfiguration = .capsule(maximumRadius: 26)
        } else {
            visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
            visualEffectView.layer.cornerRadius = 16
        }
        visualEffectView.clipsToBounds = true
        visualEffectView.directionalLayoutMargins = .init(hMargin: 12, vMargin: 8)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: visualEffectView.layoutMarginsGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: visualEffectView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: visualEffectView.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: visualEffectView.layoutMarginsGuide.bottomAnchor),
        ])

        return visualEffectView
    }()

    private lazy var faceBlurSwitch: UISwitch = {
        let faceBlurSwitch = UISwitch()
        faceBlurSwitch.addAction(
            UIAction { [weak self] action in
                guard let self, let uiSwitch = action.sender as? UISwitch else { return }
                self.didToggleAutoBlur(sender: uiSwitch)
            },
            for: .valueChanged,
        )
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
        slider.addAction(
            UIAction { [weak self] action in
                guard let self, let slider = action.sender as? UISlider else { return }
                self.handleSliderTouchEvents(slider)
            },
            for: .allTouchEvents,
        )
        slider.addAction(
            UIAction { [weak self] action in
                guard let self, let slider = action.sender as? UISlider else { return }
                self.handleSliderValueChanged(value: slider.value)
            },
            for: .valueChanged,
        )
        return slider
    }()

    lazy var strokeWidthSliderContainer = UIView()
    lazy var strokeWidthPreviewDot: UIView = {
        let view = CircleView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.borderColor = UIColor.white.cgColor
        view.layer.borderWidth = 2
        let widthConstraint = view.widthAnchor.constraint(equalToConstant: 20)
        NSLayoutConstraint.activate([
            widthConstraint,
            view.widthAnchor.constraint(equalTo: view.heightAnchor),
        ])
        strokeWidthPreviewDotSize = widthConstraint
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
        let unitStrokeWidth = ImageEditorStrokeItem.unitStrokeWidth(
            forStrokeType: currentStrokeType,
            widthAdjustmentFactor: CGFloat(strokeWidthSlider.value),
        )
        return unitStrokeWidth / model.currentTransform().scaling
    }

    // Text UI
    var textUIInitialized = false
    var startEditingTextOnViewAppear = false
    var discardTextEditsOnEditingEnd = false
    var currentTextItem: (textItem: ImageEditorTextItem, isNewItem: Bool)?
    var pinchFontSizeStart: CGFloat = ImageEditorTextItem.defaultFontSize
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
        toolbar.addAction(
            UIAction { [weak self] action in
                guard let self, let textStylingToolbar = action.sender as? TextStylingToolbar else { return }
                self.textColorDidChange(newColor: textStylingToolbar.currentColorPickerValue)
            },
            for: .valueChanged,
        )
        toolbar.textStyleButton.addAction(
            UIAction { [weak self] _ in self?.didTapTextStyleButton() },
            for: .primaryActionTriggered,
        )
        toolbar.decorationStyleButton.addAction(
            UIAction { [weak self] _ in self?.didTapDecorationStyleButton() },
            for: .primaryActionTriggered,
        )
        toolbar.doneButton.addAction(
            UIAction { [weak self] _ in self?.didTapTextEditingDoneButton() },
            for: .primaryActionTriggered,
        )
        return toolbar
    }()

    init(model: ImageEditorModel, stickerSheetDelegate: StickerPickerSheetDelegate?) {
        self.model = model
        self.stickerSheetDelegate = stickerSheetDelegate
        self.imageEditorView = ImageEditorView(model: model, delegate: nil)
        self.firstUndoOperationId = model.currentUndoOperationId

        super.init()

        if Theme.forceDarkThemeForMedia {
            overrideUserInterfaceStyle = .dark
        }

        model.add(observer: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.mediaBackground

        // Image editor.
        imageEditorView.configureSubviews()
        imageEditorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageEditorView)

        // Top toolbar
        updateTopBar()
        topBar.install(in: view)

        // Bottom toolbar
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Layout guides for `initial` and `final` UI layouts.
        initialStateContentLayoutGuide.identifier = "Content - Initial State"
        view.addLayoutGuide(initialStateContentLayoutGuide)
        NSLayoutConstraint.activate([
            initialStateContentLayoutGuide.topAnchor.constraint(
                equalTo: view.topAnchor,
                constant: initialContentInsets.top,
            ),
            initialStateContentLayoutGuide.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: initialContentInsets.leading,
            ),
            initialStateContentLayoutGuide.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -initialContentInsets.trailing,
            ),
            initialStateContentLayoutGuide.bottomAnchor.constraint(
                equalTo: view.bottomAnchor,
                constant: -initialContentInsets.bottom,
            ),
        ])

        finalStateContentLayoutGuide.identifier = "Content - Final State"
        view.addLayoutGuide(finalStateContentLayoutGuide)
        NSLayoutConstraint.activate([
            finalStateContentLayoutGuide.centerYAnchor.constraint(equalTo: initialStateContentLayoutGuide.centerYAnchor),
            finalStateContentLayoutGuide.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            finalStateContentLayoutGuide.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            finalStateContentLayoutGuide.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
        ])

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

        // Connect button actions.
        topBar.undoButton.addAction(
            UIAction { [weak self] _ in self?.didTapUndo() },
            for: .primaryActionTriggered,
        )
        topBar.clearButton.addAction(
            UIAction { [weak self] _ in self?.didTapClear() },
            for: .primaryActionTriggered,
        )
        bottomBar.cancelButton.addAction(
            UIAction { [weak self] _ in self?.didTapCancel() },
            for: .primaryActionTriggered,
        )
        bottomBar.doneButton.addAction(
            UIAction { [weak self] _ in self?.didTapDone() },
            for: .primaryActionTriggered,
        )
        bottomBar.addAction(
            UIAction { [weak self] _ in self?.didTapDraw() },
            for: .draw,
        )
        bottomBar.addAction(
            UIAction { [weak self] _ in self?.didTapAddText() },
            for: .text,
        )
        bottomBar.addAction(
            UIAction { [weak self] _ in self?.didTapAddSticker() },
            for: .sticker,
        )
        bottomBar.addAction(
            UIAction { [weak self] _ in self?.didTapBlur() },
            for: .blur,
        )

        updateUIForCurrentMode()
        transitionUI(toState: .initial, animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        transitionUI(toState: .final, animated: true) { finished in
            guard finished else { return }
            if self.startEditingTextOnViewAppear, self.canBeginTextEditingOnViewAppear {
                self.beginTextEditing()
            }
            self.startEditingTextOnViewAppear = false
        }
    }

    override var prefersStatusBarHidden: Bool {
        guard DependenciesBridge.shared.currentCallProvider.hasCurrentCall == false else {
            return super.prefersStatusBarHidden
        }
        guard
            let appWindow = CurrentAppContext().mainWindow,
            appWindow.shouldHideStatusBarForFullScreenPresentation
        else {
            return super.prefersStatusBarHidden
        }
        return true
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        Theme.forceDarkThemeForMedia ? .lightContent : .default
    }

    // MARK: -

    private func updateUIForCurrentMode() {
        switch mode {
        case .draw, .blur:
            strokeWidthSliderContainer.isHidden = false
            finishTextEditing()
            imageEditorView.textInteractionModes = .select
        case .text, .sticker:
            strokeWidthSliderContainer.isHidden = true
            imageEditorView.textInteractionModes = .all
        }

        bottomBar.selectedToolButton = switch mode {
        case .draw: .draw
        case .blur: .blur
        case .text: .text
        case .sticker: .sticker
        }

        updateDrawToolUIVisibility()
        updateBlurToolUIVisibility()
        updateTextUIVisibility()
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

        case .text, .sticker:
            return imageEditorView.shouldHideControls
        }
    }

    private var canUndo: Bool {
        model.canUndo && firstUndoOperationId != model.currentUndoOperationId
    }

    func updateControlsVisibility() {
        setControls(hidden: shouldHideControls, animated: true, slideButtonsInOut: false)
    }

    private func setControls(hidden: Bool, animated: Bool, slideButtonsInOut: Bool) {
        guard animated else {
            setControls(hidden: hidden, animator: nil, slideButtonsInOut: slideButtonsInOut)
            return
        }

        let animator = AttachmentApprovalToolbar.defaultAnimator()
        setControls(hidden: hidden, animator: animator, slideButtonsInOut: slideButtonsInOut)
        animator.startAnimation()
    }

    private func setControls(
        hidden: Bool,
        animator: UIViewPropertyAnimator?,
        slideButtonsInOut: Bool,
    ) {
        guard let animator else {
            setControls(hidden: hidden, slideButtonsInOut: slideButtonsInOut)
            return
        }

        animator.addAnimations {
            self.setControls(hidden: hidden, slideButtonsInOut: slideButtonsInOut)

            // Animate layout changes made within bottomBar.setControls(hidden:).
            if slideButtonsInOut {
                self.bottomBar.setNeedsDisplay()
                self.bottomBar.layoutIfNeeded()
            }
        }
    }

    private func setControls(hidden: Bool, slideButtonsInOut: Bool) {
        let alpha: CGFloat = hidden ? 0 : 1
        topBar.alpha = alpha
        bottomBar.alpha = alpha
        if slideButtonsInOut {
            bottomBar.setControlsHidden(hidden)
        }

        switch mode {
        case .draw:
            updateDrawToolControlsVisibility()

        case .blur:
            updateBlurToolControlsVisibility()

        case .text, .sticker:
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
        guard canUndo else {
            owsFailDebug("Can't undo.")
            return
        }
        model.undo()
    }

    private func clearAll() {
        if mode == .text {
            finishTextEditing(discardEdits: true)
        }

        while canUndo {
            model.undo()
        }
    }

    // MARK: - Presenting / Dismissing

    private func prepareToDismiss(completion: ((Bool) -> Void)?) {
        if mode == .text {
            finishTextEditing(discardEdits: true)
        }
        transitionUI(toState: .initial, animated: true, completion: completion)
    }

    private func prepareToFinish(completion: ((Bool) -> Void)?) {
        if mode == .text {
            finishTextEditing()
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
        let actionSheetTitle = OWSLocalizedString(
            "MEDIA_EDITOR_DISCARD_ALL_CONFIRMATION_TITLE",
            comment: "Media Editor: Title for the 'Discard Changes' confirmation prompt.",
        )
        let actionSheetMessage = OWSLocalizedString(
            "MEDIA_EDITOR_DISCARD_ALL_CONFIRMATION_MESSAGE",
            comment: "Media Editor: Message for the 'Discard Changes' confirmation prompt.",
        )
        let discardChangesButton = OWSLocalizedString(
            "MEDIA_EDITOR_DISCARD_ALL_BUTTON",
            comment: "Media Editor: Title for the button in 'Discard Changes' confirmation prompt.",
        )
        let actionSheet = ActionSheetController(title: actionSheetTitle, message: actionSheetMessage)
        if Theme.forceDarkThemeForMedia {
            actionSheet.overrideUserInterfaceStyle = .dark
        }
        actionSheet.addAction(ActionSheetAction(title: discardChangesButton, style: .destructive, handler: { _ in
            self.clearAll()
            if let completionHandler {
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
        let layoutGuide: UILayoutGuide = {
            switch state {
            case .initial: initialStateContentLayoutGuide
            case .final: finalStateContentLayoutGuide
            }
        }()

        guard animated else {
            constrainImageEditorView(to: layoutGuide)
            setControls(hidden: state == .initial, animator: nil, slideButtonsInOut: true)
            imageEditorView.setHasRoundedCorners(state == .initial, animationDuration: 0)
            completion?(true)
            return
        }

        let animator = AttachmentApprovalToolbar.defaultAnimator()
        setControls(hidden: state == .initial, animator: animator, slideButtonsInOut: true)
        animator.addAnimations {
            self.constrainImageEditorView(to: layoutGuide)
        }
        if let completion {
            animator.addCompletion { position in
                completion(position == .end)
            }
        }
        animator.startAnimation()

        imageEditorView.setHasRoundedCorners(state == .initial, animationDuration: animator.duration)
    }

    private func constrainImageEditorView(to layoutGuide: UILayoutGuide) {
        NSLayoutConstraint.deactivate(contentLayoutGuideConstraints)

        // ImageEditorView simply occupies all space because it has `scaleAspectFit` content mode in this VC.
        let constraints = [
            imageEditorView.topAnchor.constraint(equalTo: layoutGuide.topAnchor),
            imageEditorView.leadingAnchor.constraint(equalTo: layoutGuide.leadingAnchor),
            imageEditorView.trailingAnchor.constraint(equalTo: layoutGuide.trailingAnchor),
            imageEditorView.bottomAnchor.constraint(equalTo: layoutGuide.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)

        contentLayoutGuideConstraints = constraints
    }

    // MARK: - Actions

    private func didTapUndo() {
        undo()
    }

    private func didTapClear() {
        askToDiscardAllChanges(nil)
    }

    private func didTapCancel() {
        discardAndDismiss()
    }

    private func didTapDone() {
        completeAndDismiss()
    }

    private func didTapDraw() {
        // Second tap on Pen icon switches editor to "text" mode.
        mode = (mode == .draw) ? .text : .draw
    }

    private func didTapAddText() {
        let decorationStyle = textViewAccessoryToolbar.decorationStyle
        let textColor = textViewAccessoryToolbar.currentColorPickerValue
        let textItem = imageEditorView.createNewTextItem(withColor: textColor, decorationStyle: decorationStyle)
        selectTextItem(textItem, isNewItem: true, startEditing: true)
    }

    private func didTapAddSticker() {
        let stickerPicker = StickerPickerSheet(pickerDelegate: self)
        stickerPicker.sheetDelegate = stickerSheetDelegate
        present(stickerPicker, animated: true)
    }

    private func didTapBlur() {
        // Second tap on Blur icon switches editor to "text" mode.
        mode = (mode == .blur) ? .text : .blur
    }

    // MARK: - UIGestureRecognizerDelegate

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
            return !blurToolPanel.bounds.contains(touch.location(in: blurToolPanel))

        default:
            return true
        }
    }

    // MARK: - ImageEditorModelObserver

    func imageEditorModelDidChange(before: ImageEditorContents, after: ImageEditorContents) {
        modelDidChange()
    }

    func imageEditorModelDidChange(changedItemIds: [String]) {
        modelDidChange()
    }

    // MARK: - ColorPickerBarViewDelegate

    func colorPickerBarValueChanged(color: ColorPickerBarColor) {
        switch mode {
        case .draw:
            model.color = color
            updateStrokeWidthPreviewColor()

        default:
            owsAssertDebug(false, "Invalid mode [\(mode)]")
        }
    }
}
