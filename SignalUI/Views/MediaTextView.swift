//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

public class MediaTextView: UITextView {

    public enum DecorationStyle: String, CaseIterable {
        case none                   // colored text, no background
        case whiteBackground        // colored text, white background
        case coloredBackground      // white text, colored background
        case underline              // white text, colored underline
        case outline                // white text, colored outline
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

        backgroundColor = .clear
        isOpaque = false
        isScrollEnabled = false
        keyboardAppearance = .dark
        scrollsToTop = false
        textAlignment = .center
        tintColor = .white
        self.textContainer.lineFragmentPadding = 0

        kvoObservation = observe(\.contentSize, options: [.new]) { [weak self] _, _ in
            guard let self = self else { return }
            self.adjustFontSizeIfNecessary()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func adjustFontSizeIfNecessary() {
        // TODO: Figure out correct way to handle long text and implement it.
    }

    public func update(using textStylingToolbar: TextStylingToolbar,
                       fontPointSize: CGFloat,
                       textAlignment: NSTextAlignment = .center) {
        let font = MediaTextView.font(for: textStylingToolbar.textStyle, withPointSize: fontPointSize)
        updateWith(textForegroundColor: textStylingToolbar.textForegroundColor,
                   font: font,
                   textAlignment: textAlignment,
                   textDecorationColor: textStylingToolbar.textDecorationColor,
                   decorationStyle: textStylingToolbar.decorationStyle)
    }

    public func updateWith(textForegroundColor: UIColor,
                           font: UIFont,
                           textAlignment: NSTextAlignment,
                           textDecorationColor: UIColor?,
                           decorationStyle: MediaTextView.DecorationStyle) {
        var attributes: [NSAttributedString.Key: Any] = [ .font: font]

        attributes[.foregroundColor] = textForegroundColor

        if let paragraphStyle = NSParagraphStyle.default.mutableCopy() as? NSMutableParagraphStyle {
            paragraphStyle.alignment = textAlignment
            attributes[.paragraphStyle] = paragraphStyle
        }

        if let textDecorationColor = textDecorationColor {
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

    public override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(modifiedReturnPressed(sender:)), discoverabilityTitle: "Add Text"),
            UIKeyCommand(input: "\r", modifierFlags: .alternate, action: #selector(modifiedReturnPressed(sender:)), discoverabilityTitle: "Add Text")
        ]
    }

    @objc
    private func modifiedReturnPressed(sender: UIKeyCommand) {
        Logger.verbose("")

        acceptAutocorrectSuggestion()
        resignFirstResponder()
    }
}

public class TextStylingToolbar: UIControl {

    public enum Layout {
        case photoOverlay
        case textStory
    }
    let layout: Layout

    private let colorPickerView: ColorPickerBarView

    // Photo Editor operates with ColorPickerBarColor hence the need to expose this value.
    public var currentColorPickerValue: ColorPickerBarColor {
        get { colorPickerView.selectedValue }
        set { colorPickerView.selectedValue = newValue }
    }

    public static func defaultColor(forLayout layout: Layout) -> ColorPickerBarColor {
        switch layout {
        case .photoOverlay:
            return ColorPickerBarColor.defaultColor()
        case .textStory:
            return ColorPickerBarColor.white
        }
    }

    public let textStyleButton = RoundMediaButton(image: TextStylingToolbar.buttonImage(forTextStyle: .regular),
                                                  backgroundStyle: .blur)
    public var textStyle: MediaTextView.TextStyle = .regular {
        didSet {
            textStyleButton.setImage(TextStylingToolbar.buttonImage(forTextStyle: textStyle), for: .normal)
        }
    }

    private static func buttonImage(forTextStyle textStyle: MediaTextView.TextStyle) -> UIImage? {
        return UIImage(imageLiteralResourceName: "media-editor-font-" + textStyle.rawValue)
    }

    public var textForegroundColor: UIColor {
        switch decorationStyle {
        case .none, .whiteBackground: return colorPickerView.color

        case .coloredBackground:
            // Switch text color to black if background is almost white.
            let backgroundColor = colorPickerView.color
            return backgroundColor.isCloseToColor(.white) ? .black : .white

        case .outline, .underline: return .white
        }
    }
    public var textBackgroundColor: UIColor? {
        switch decorationStyle {
        case .none, .underline, .outline: return nil

        case .whiteBackground:
            // Switch background color to black if text color is almost white.
            let textColor = colorPickerView.color
            return textColor.isCloseToColor(.white) ? .black : .white

        case .coloredBackground: return colorPickerView.color
        }
    }
    public var textDecorationColor: UIColor? {
        switch decorationStyle {
        case .none, .whiteBackground, .coloredBackground: return nil
        case .outline, .underline: return colorPickerView.color
        }
    }

    public let decorationStyleButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-text-style-1"), backgroundStyle: .blur)
    public var decorationStyle: MediaTextView.DecorationStyle = .none {
        didSet {
            decorationStyleButton.isSelected = (decorationStyle != .none)
        }
    }

    public lazy var doneButton = RoundMediaButton(image: UIImage(imageLiteralResourceName: "check-24"), backgroundStyle: .blur)

    public private(set) var contentWidthConstraint: NSLayoutConstraint?
    private var stackView = UIStackView()

    public init(layout: Layout, currentColor: ColorPickerBarColor? = nil) {
        self.layout = layout
        colorPickerView = ColorPickerBarView(currentColor: currentColor ?? TextStylingToolbar.defaultColor(forLayout: layout))

        super.init(frame: .zero)

        autoresizingMask = [ .flexibleHeight ]

        colorPickerView.delegate = self

        decorationStyleButton.setContentCompressionResistancePriority(.required, for: .vertical)
        decorationStyleButton.setImage(#imageLiteral(resourceName: "media-editor-text-style-2"), for: .selected)

        // A container with width capped at a predefined size,
        // centered in superview and constrained to layout margins.
        let stackViewLayoutGuide = UILayoutGuide()

        let contentWidthConstraint = stackViewLayoutGuide.widthAnchor.constraint(equalToConstant: ImageEditorViewController.preferredToolbarContentWidth)
        contentWidthConstraint.priority = .defaultHigh
        self.contentWidthConstraint = contentWidthConstraint

        addLayoutGuide(stackViewLayoutGuide)
        addConstraints([
            stackViewLayoutGuide.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackViewLayoutGuide.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            stackViewLayoutGuide.topAnchor.constraint(equalTo: topAnchor),
            stackViewLayoutGuide.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -2),
            contentWidthConstraint
        ])

        // I had to use a custom layout guide because stack view isn't centered
        // but instead has slight offset towards the trailing edge.
        let stackViewSubviews: [UIView] = {
            switch layout {
            case .photoOverlay:
                return [ colorPickerView, textStyleButton, decorationStyleButton ]
            case .textStory:
                return [ textStyleButton, decorationStyleButton, colorPickerView, doneButton ]
            }
        }()
        stackView.addArrangedSubviews(stackViewSubviews)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.setCustomSpacing(0, after: textStyleButton)
        addSubview(stackView)

        // Round buttons have no-zero layout margins. Use values of those margins
        // to offset button positions so that they appear properly aligned.
        var leadingMargin: CGFloat = 0
        var trailingMargin: CGFloat = 0
        if let button = stackViewSubviews.first as? RoundMediaButton {
            leadingMargin = button.layoutMargins.leading
        }
        if let button = stackViewSubviews.last as? RoundMediaButton {
            trailingMargin = button.layoutMargins.trailing
        }
        addConstraints([
            stackView.leadingAnchor.constraint(equalTo: stackViewLayoutGuide.leadingAnchor, constant: -leadingMargin),
            stackView.trailingAnchor.constraint(equalTo: stackViewLayoutGuide.trailingAnchor, constant: trailingMargin),
            stackView.topAnchor.constraint(equalTo: stackViewLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: stackViewLayoutGuide.bottomAnchor)
        ])
    }

    @available(iOS, unavailable, message: "Use init(currentColor:)")
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        // NOTE: Update size calculation if changing margins around UIStackView in init(layout:currentColor:).
        CGSize(
            width: UIScreen.main.bounds.width,
            height: stackView.frame.height + 2 + safeAreaInsets.bottom
        )
    }
}

extension TextStylingToolbar: ColorPickerBarViewDelegate {

    public func colorPickerBarView(_ pickerView: ColorPickerBarView, didSelectColor color: ColorPickerBarColor) {
        sendActions(for: .valueChanged)
    }
}
