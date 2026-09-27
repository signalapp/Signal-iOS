//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

class ImageEditorTopBar: MediaTopBar {

    let undoButton = UIButton(
        configuration: .roundMedia(image: UIImage(imageLiteralResourceName: "undo-26"), size: 44),
    )

    var isUndoButtonHidden: Bool {
        get { undoButton.alpha == 0 }
        set { undoButton.alpha = newValue ? 0 : 1 }
    }

    let clearButton = UIButton(configuration: .capsuleMedia(
        title: OWSLocalizedString(
            "MEDIA_EDITOR_BUTTON_CLEAR",
            comment: "Title for the button that discards all edits in media editor.",
        ),
        buttonHeight: 44,
    ))
    var isClearAllButtonHidden: Bool {
        get { clearButton.alpha == 0 }
        set { clearButton.alpha = newValue ? 0 : 1 }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stackView = UIStackView(arrangedSubviews: [undoButton, UIView.hStretchingSpacer(), clearButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .center
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: controlsLayoutGuide.leadingAnchor),
            stackView.topAnchor.constraint(equalTo: controlsLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: controlsLayoutGuide.bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: controlsLayoutGuide.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

enum ImageEditorToolButton {
    // Crop & Rotate tools
    case rotate
    case flip
    case aspectRatio

    // Draw Tools
    case draw
    case text
    case sticker
    case blur

    private var buttonImage: UIImage {
        switch self {
        case .rotate:
            UIImage(imageLiteralResourceName: "rotate")
        case .flip:
            UIImage(imageLiteralResourceName: "flip")
        case .aspectRatio:
            UIImage(imageLiteralResourceName: "aspectratio")
        case .draw:
            UIImage(imageLiteralResourceName: "scribble")
        case .text:
            UIImage(imageLiteralResourceName: "text")
        case .sticker:
            UIImage(imageLiteralResourceName: "sticker")
        case .blur:
            UIImage(imageLiteralResourceName: "blur")
        }
    }

    var buttonConfiguration: UIButton.Configuration {
        let buttonSize: CGFloat = 44
        let buttonImage = buttonImage

        var configuration = UIButton.Configuration.gray()
        configuration.image = buttonImage
        configuration.contentInsets = .init(
            hMargin: 0.5 * (buttonSize - buttonImage.size.width),
            vMargin: 0.5 * (buttonSize - buttonImage.size.height),
        )
        configuration.background.backgroundInsets = .init(margin: 4) // needed to show `selected` state for some tools
        configuration.baseForegroundColor = .Signal.label
        configuration.baseBackgroundColor = .clear
        configuration.cornerStyle = .capsule
        return configuration
    }
}

class ImageEditorToolbar: UIView {

    let cancelButton: UIButton = UIButton(
        configuration: .roundMedia(image: UIImage(imageLiteralResourceName: "x"), size: 44),
    )
    let doneButton: UIButton = UIButton(
        configuration: .tintedRoundMedia(
            image: UIImage(imageLiteralResourceName: "check"),
            size: 44,
        ),
    )
    private let toolButtons: [(tool: ImageEditorToolButton, button: UIButton)]

    var selectedToolButton: ImageEditorToolButton? {
        willSet {
            if
                let selectedToolButton,
                let selectedButton = toolButtons.first(where: { $0.tool == selectedToolButton })?.button
            {
                selectedButton.configuration?.baseBackgroundColor = .clear
            }
        }
        didSet {
            if
                let selectedToolButton,
                let selectedButton = toolButtons.first(where: { $0.tool == selectedToolButton })?.button
            {
                selectedButton.configuration?.baseBackgroundColor = .Signal.primaryFill
            }
        }
    }

    func addAction(_ action: UIAction, for toolButton: ImageEditorToolButton) {
        guard let button = toolButtons.first(where: { $0.tool == toolButton })?.button else {
            owsFailDebug("Invalid tool.")
            return
        }
        button.addAction(action, for: .primaryActionTriggered)
    }

    private let contentLayoutGuide = UILayoutGuide()
    private var contentLayoutGuideLeading: NSLayoutConstraint?
    private var contentLayoutGuideTrailing: NSLayoutConstraint?
    private var contentLayoutGuideBottom: NSLayoutConstraint?

    private let stackView = UIStackView()

    private var areControlsHidden = false
    private var stackViewPositionConstraint: NSLayoutConstraint?

    init(tools: [ImageEditorToolButton]) {
        toolButtons = tools.map { tool in
            (
                tool: tool,
                button: UIButton(configuration: tool.buttonConfiguration),
            )
        }

        super.init(frame: .zero)

        preservesSuperviewLayoutMargins = true

        addLayoutGuide(contentLayoutGuide)
        let leading = contentLayoutGuide.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor)
        let trailing = contentLayoutGuide.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor)
        let bottom = contentLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([
            contentLayoutGuide.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            leading,
            trailing,
            bottom,
        ])
        contentLayoutGuideLeading = leading
        contentLayoutGuideTrailing = trailing
        contentLayoutGuideBottom = bottom

        let toolButtonsStack = UIStackView(arrangedSubviews: toolButtons.map { $0.button })
        toolButtonsStack.spacing = 8
        if #available(iOS 26, *) {
            toolButtonsStack.translatesAutoresizingMaskIntoConstraints = false

            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = true
            let glassPanelView = UIVisualEffectView(effect: glassEffect)
            glassPanelView.clipsToBounds = true
            glassPanelView.cornerConfiguration = .capsule()
            glassPanelView.contentView.addSubview(toolButtonsStack)
            NSLayoutConstraint.activate([
                toolButtonsStack.topAnchor.constraint(equalTo: glassPanelView.contentView.topAnchor),
                toolButtonsStack.leadingAnchor.constraint(equalTo: glassPanelView.contentView.leadingAnchor),
                toolButtonsStack.trailingAnchor.constraint(equalTo: glassPanelView.contentView.trailingAnchor),
                toolButtonsStack.bottomAnchor.constraint(equalTo: glassPanelView.contentView.bottomAnchor),
            ])
            stackView.addArrangedSubviews([cancelButton, glassPanelView, doneButton])
        } else {
            stackView.addArrangedSubviews([cancelButton, toolButtonsStack, doneButton])
        }
        stackView.distribution = .equalSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Height of the stack view doesn't change. Calculate it now and use it to define
        // height of the ImageEditorToolbar via it's `layoutMarginsGuide`.
        let stackViewHeight = stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),

            stackView.heightAnchor.constraint(equalToConstant: stackViewHeight),
            contentLayoutGuide.heightAnchor.constraint(equalToConstant: stackViewHeight),
        ])

        updateContentLayoutGuideMargins()

        setControlsHidden(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()

        updateContentLayoutGuideMargins()
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()

        updateContentLayoutGuideMargins()
    }

    private func updateContentLayoutGuideMargins() {
        guard let contentLayoutGuideLeading, let contentLayoutGuideTrailing, let contentLayoutGuideBottom else {
            owsFailBeta("Invalid configuration")
            return
        }

        // Bottom margin:
        //  • 16 dp if there's no bottom safe area inset (home button iPhones)
        // or
        //  • amount of bottom safe area inset, capped at  28 dp (notch iPhones, iPads)
        // Horizontal margins:
        //  `0` if there's leading / trailing safe area inset (happens on modern iPhones in landscape layout)
        // or
        //  if there is a bottom safe area inset - make it same as bottom inset (concentric radius look)
        // or
        //  standard inset in all other cases.
        let bottomMargin: CGFloat
        var leadingMargin: CGFloat = 0
        var trailingMargin: CGFloat = 0

        if safeAreaInsets.bottom.isZero {
            bottomMargin = directionalLayoutMargins.bottom
            if safeAreaInsets.leading.isZero {
                leadingMargin = directionalLayoutMargins.leading
            }
            if safeAreaInsets.trailing.isZero {
                trailingMargin = directionalLayoutMargins.trailing
            }
        } else {
            bottomMargin = min(28, safeAreaInsets.bottom)
            if safeAreaInsets.leading.isZero {
                leadingMargin = bottomMargin
            }
            if safeAreaInsets.trailing.isZero {
                trailingMargin = bottomMargin
            }
        }

        contentLayoutGuideLeading.constant = leadingMargin
        contentLayoutGuideTrailing.constant = -trailingMargin
        contentLayoutGuideBottom.constant = -bottomMargin
    }

    func setControlsHidden(_ hidden: Bool) {
        guard hidden != areControlsHidden || stackViewPositionConstraint == nil else { return }

        if let stackViewPositionConstraint {
            NSLayoutConstraint.deactivate([stackViewPositionConstraint])
            self.stackViewPositionConstraint = nil
        }

        let stackViewPositionConstraint: NSLayoutConstraint
        if hidden {
            stackViewPositionConstraint = stackView.topAnchor.constraint(equalTo: bottomAnchor)
        } else {
            stackViewPositionConstraint = stackView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor)
        }
        NSLayoutConstraint.activate([stackViewPositionConstraint])
        self.stackViewPositionConstraint = stackViewPositionConstraint

        areControlsHidden = hidden
    }
}
