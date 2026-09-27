//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public class MediaTextView: UITextView {

    public enum DecorationStyle: String, CaseIterable {
        case none // colored text, no background
        case whiteBackground // colored text, white background
        case coloredBackground // white text, colored background
        case underline // white text, colored underline
        case outline // white text, colored outline
    }

    // Resource names are derived from these values. Do not change without consideration.
    public enum TextStyle: String, CaseIterable {
        case regular
        case bold
        case serif
        case script
        case condensed
    }

    class func font(for textStyle: TextStyle, withPointSize pointSize: CGFloat) -> UIFont {
        let style: TextAttachment.TextStyle = {
            switch textStyle {
            case .regular: return .regular
            case .bold: return .bold
            case .serif: return .serif
            case .script: return .script
            case .condensed: return .condensed
            }
        }()
        return UIFont.font(for: style, withPointSize: pointSize)
    }

    private var kvoObservation: NSKeyValueObservation?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)

        disableAiWritingTools()

        backgroundColor = .clear
        isOpaque = false
        isScrollEnabled = false
        scrollsToTop = false
        textAlignment = .center
        tintColor = .Signal.label
        self.textContainer.lineFragmentPadding = 0

        kvoObservation = observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            guard let self else { return }
            self.adjustFontSizeIfNecessary()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func adjustFontSizeIfNecessary() {
        // TODO: Figure out correct way to handle long text and implement it.
    }

    public func update(
        using textStylingToolbar: TextStylingToolbar,
        fontPointSize: CGFloat,
        textAlignment: NSTextAlignment = .center,
    ) {
        let font = MediaTextView.font(for: textStylingToolbar.textStyle, withPointSize: fontPointSize)
        updateWith(
            textForegroundColor: textStylingToolbar.textForegroundColor,
            font: font,
            textAlignment: textAlignment,
            textDecorationColor: textStylingToolbar.textDecorationColor,
            decorationStyle: textStylingToolbar.decorationStyle,
        )
    }

    public func updateWith(
        textForegroundColor: UIColor,
        font: UIFont,
        textAlignment: NSTextAlignment,
        textDecorationColor: UIColor?,
        decorationStyle: MediaTextView.DecorationStyle,
    ) {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]

        attributes[.foregroundColor] = textForegroundColor

        if let paragraphStyle = NSParagraphStyle.default.mutableCopy() as? NSMutableParagraphStyle {
            paragraphStyle.alignment = textAlignment
            attributes[.paragraphStyle] = paragraphStyle
        }

        if let textDecorationColor {
            switch decorationStyle {
            case .underline:
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.underlineColor] = textDecorationColor

            case .outline:
                attributes[.strokeWidth] = -3
                attributes[.strokeColor] = textDecorationColor

            default:
                break
            }
        }

        attributedText = NSAttributedString(string: text, attributes: attributes)
        // This makes UITextView apply text styling to the text that user enters.
        typingAttributes = attributes
        tintColor = textForegroundColor

        invalidateIntrinsicContentSize()
    }

    // MARK: - Key Commands

    override public var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(action: #selector(modifiedReturnPressed(sender:)), input: "\r", modifierFlags: .command, discoverabilityTitle: "Add Text"),
            UIKeyCommand(action: #selector(modifiedReturnPressed(sender:)), input: "\r", modifierFlags: .alternate, discoverabilityTitle: "Add Text"),
        ]
    }

    @objc
    private func modifiedReturnPressed(sender: UIKeyCommand) {
        acceptAutocorrectSuggestion()
        resignFirstResponder()
    }
}

public class TextStylingToolbar: UIControl {

    private let colorPickerBar: ColorPickerBar

    // Photo Editor operates with ColorPickerBarColor hence the need to expose this value.
    public var currentColorPickerValue: ColorPickerBarColor {
        get { colorPickerBar.color }
        set { colorPickerBar.color = newValue }
    }

    public let textStyleButton: UIButton

    public var textStyle: MediaTextView.TextStyle = .regular {
        didSet {
            textStyleButton.configuration?.image = TextStylingToolbar.buttonImage(forTextStyle: textStyle)
        }
    }

    private static func buttonImage(forTextStyle textStyle: MediaTextView.TextStyle) -> UIImage {
        return UIImage(imageLiteralResourceName: "font-" + textStyle.rawValue)
    }

    public var textForegroundColor: UIColor {
        switch decorationStyle {
        case .none, .whiteBackground: return colorPickerBar.uiColor

        case .coloredBackground:
            // Switch text color to black if background is almost white.
            let backgroundColor = colorPickerBar.uiColor
            return backgroundColor.isCloseToColor(.white) ? .black : .white

        case .outline, .underline: return .white
        }
    }

    public var textBackgroundColor: UIColor? {
        switch decorationStyle {
        case .none, .underline, .outline: return nil

        case .whiteBackground:
            // Switch background color to black if text color is almost white.
            let textColor = colorPickerBar.uiColor
            return textColor.isCloseToColor(.white) ? .black : .white

        case .coloredBackground: return colorPickerBar.uiColor
        }
    }

    public var textDecorationColor: UIColor? {
        switch decorationStyle {
        case .none, .whiteBackground, .coloredBackground: return nil
        case .outline, .underline: return colorPickerBar.uiColor
        }
    }

    public let decorationStyleButton: UIButton

    public var decorationStyle: MediaTextView.DecorationStyle = .none {
        didSet {
            let buttonImageName = decorationStyle == .none ? "text_effects" : "text_effects-fill"
            decorationStyleButton.configuration?.image = UIImage(named: buttonImageName)
        }
    }

    public let doneButton: UIButton = UIButton(
        configuration: .roundMedia(
            image: UIImage(imageLiteralResourceName: "check"),
            size: 44,
        ),
    )

    public private(set) var contentWidthConstraint: NSLayoutConstraint?

    private lazy var stackView: UIStackView = {
        let stackView: UIStackView
        if #available(iOS 26, *) {
            let buttonStack = UIStackView(arrangedSubviews: [textStyleButton, decorationStyleButton])
            buttonStack.spacing = 8
            buttonStack.directionalLayoutMargins = .init(hMargin: 2, vMargin: 0)
            buttonStack.isLayoutMarginsRelativeArrangement = true
            buttonStack.translatesAutoresizingMaskIntoConstraints = false
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = true
            let glassPanel = UIVisualEffectView(effect: glassEffect)
            glassPanel.clipsToBounds = true
            glassPanel.cornerConfiguration = .capsule()
            glassPanel.contentView.addSubview(buttonStack)
            NSLayoutConstraint.activate([
                buttonStack.topAnchor.constraint(equalTo: glassPanel.topAnchor),
                buttonStack.leadingAnchor.constraint(equalTo: glassPanel.leadingAnchor),
                buttonStack.trailingAnchor.constraint(equalTo: glassPanel.trailingAnchor),
                buttonStack.bottomAnchor.constraint(equalTo: glassPanel.bottomAnchor),
            ])
            stackView = UIStackView(arrangedSubviews: [glassPanel, colorPickerBar, doneButton])
        } else {
            stackView = UIStackView(arrangedSubviews: [textStyleButton, decorationStyleButton, colorPickerBar, doneButton])
            stackView.setCustomSpacing(8, after: textStyleButton)
        }
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .center
        stackView.spacing = 20
        return stackView
    }()

    public init(currentColor: ColorPickerBarColor? = nil) {
        colorPickerBar = ColorPickerBar(color: currentColor ?? ColorPickerBarColor.white)

        // No background for leading buttons on iOS 26 because they are placed onto a glass panel together.
        let useBackgroundForLeadingEdgeButtons = if #available(iOS 26, *) { false } else { true }
        textStyleButton = UIButton(configuration: .roundMedia(
            image: TextStylingToolbar.buttonImage(forTextStyle: .regular),
            size: 44,
            withBackground: useBackgroundForLeadingEdgeButtons,
        ))
        decorationStyleButton = UIButton(configuration: .roundMedia(
            image: UIImage(imageLiteralResourceName: "text_effects"),
            size: 44,
            withBackground: useBackgroundForLeadingEdgeButtons,
        ))

        super.init(frame: .zero)

        preservesSuperviewLayoutMargins = true
        autoresizingMask = [.flexibleHeight]

        colorPickerBar.addAction(
            UIAction { [weak self] action in
                guard let self, action.sender is ColorPickerBar else { return }
                self.colorPickerBarValueChanged()
            },
            for: .valueChanged,
        )

        textStyleButton.setCompressionResistanceHigh()
        decorationStyleButton.setCompressionResistanceHigh()
        doneButton.setCompressionResistanceHigh()

        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        let contentWidthConstraint = stackView.widthAnchor.constraint(
            equalToConstant: ImageEditorViewController.preferredToolbarContentWidth,
        )
        contentWidthConstraint.priority = .defaultHigh
        self.contentWidthConstraint = contentWidthConstraint
        addConstraints([
            stackView.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
            contentWidthConstraint,
        ])
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func colorPickerBarValueChanged() {
        sendActions(for: .valueChanged)
    }
}
