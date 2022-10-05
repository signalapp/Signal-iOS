//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import UIKit

public class MediaTextView: UITextView {

    public enum DecorationStyle: Int {
        case none = 0
        case inverted
        case underline
        case outline
    }

    public enum TextStyle: Int {
        case regular = 0
        case bold
        case serif
        case script
        case condensed
    }

    class func font(forTextStyle textStyle: TextStyle, pointSize: CGFloat) -> UIFont {
        // TODO: this is a copy-paste code from TextAttachmentView that needs to be consolidated in one place.
        let attributes: [UIFontDescriptor.AttributeName: Any]

        switch textStyle {
        case .regular:
            attributes = [.name: "Inter-Regular_Medium"]
        case .bold:
            attributes = [.name: "Inter-Regular_Black"]
        case .serif:
            attributes = [.name: "EBGaramond-Regular"]
        case .script:
            attributes = [.name: "Parisienne-Regular"]
        case .condensed:
            // TODO: Ideally we could set an attribute to make this font
            // all caps, but iOS deprecated that ability and didn't add
            // a new equivalent function.
            attributes = [.name: "BarlowCondensed-Medium"]
        }

        // TODO: Eventually we'll want to provide a cascadeList here to fallback
        // to different fonts for different scripts rather than just relying on
        // the built in OS fallbacks that don't tend to match the desired style.
        let descriptor = UIFontDescriptor(fontAttributes: attributes)

        return UIFont(descriptor: descriptor, size: pointSize)
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
        let font = MediaTextView.font(forTextStyle: textStylingToolbar.textStyle, pointSize: fontPointSize)
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

    public let textStyleButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-text-font"), backgroundStyle: .blur)
    public var textStyle: MediaTextView.TextStyle = .regular

    public var textForegroundColor: UIColor {
        switch decorationStyle {
        case .none: return colorPickerView.color
        case .inverted, .outline, .underline: return .white
        }
    }
    public var textBackgroundColor: UIColor? {
        switch decorationStyle {
        case .none, .underline, .outline: return nil
        case .inverted: return colorPickerView.color
        }
    }
    public var textDecorationColor: UIColor? {
        switch decorationStyle {
        case .none, .inverted: return nil
        case .outline, .underline: return colorPickerView.color
        }
    }

    public let decorationStyleButton = RoundMediaButton(image: #imageLiteral(resourceName: "media-editor-text-style-1"), backgroundStyle: .blur)
    public var decorationStyle: MediaTextView.DecorationStyle = .none {
        didSet {
            decorationStyleButton.isSelected = (decorationStyle != .none)
            // Change default decoration style away from white to avoid white on white situation.
            if decorationStyle != .none && colorPickerView.selectedValue == .white {
                colorPickerView.selectedValue = .black
            }
            // Switch color picker color back to white because it now controls text color.
            // The idea is that cycling through decoration styles should keep text white.
            if decorationStyle == .none && colorPickerView.selectedValue == .black {
                colorPickerView.selectedValue = .white
            }
        }
    }

    public lazy var doneButton = RoundMediaButton(image: UIImage(imageLiteralResourceName: "check-24"), backgroundStyle: .blur)

    public init(layout: Layout, currentColor: ColorPickerBarColor? = nil) {
        self.layout = layout
        colorPickerView = ColorPickerBarView(currentColor: currentColor ?? TextStylingToolbar.defaultColor(forLayout: layout))

        super.init(frame: .zero)

        colorPickerView.delegate = self

        decorationStyleButton.setContentCompressionResistancePriority(.required, for: .vertical)
        decorationStyleButton.setImage(#imageLiteral(resourceName: "media-editor-text-style-2"), for: .selected)

        // A container with width capped at a predefined size,
        // centered in superview and constrained to layout margins.
        let stackViewLayoutGuide = UILayoutGuide()
        addLayoutGuide(stackViewLayoutGuide)
        addConstraints([
            stackViewLayoutGuide.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackViewLayoutGuide.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            stackViewLayoutGuide.topAnchor.constraint(equalTo: topAnchor),
            stackViewLayoutGuide.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2) ])
        addConstraint({
            let constraint = stackViewLayoutGuide.widthAnchor.constraint(equalToConstant: ImageEditorViewController.preferredToolbarContentWidth)
            constraint.priority = .defaultHigh
            return constraint
        }())

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
        let stackView = UIStackView(arrangedSubviews: stackViewSubviews)
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
            stackView.bottomAnchor.constraint(equalTo: stackViewLayoutGuide.bottomAnchor) ])
    }

    @available(iOS, unavailable, message: "Use init(currentColor:)")
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension TextStylingToolbar: ColorPickerBarViewDelegate {

    public func colorPickerBarView(_ pickerView: ColorPickerBarView, didSelectColor color: ColorPickerBarColor) {
        sendActions(for: .valueChanged)
    }
}
