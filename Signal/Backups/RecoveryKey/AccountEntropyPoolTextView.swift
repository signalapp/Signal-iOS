//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class AccountEntropyPoolTextView: UIView, TextViewWithPlaceholderDelegate {
    enum Mode {
        case entry(onTextViewChanged: () -> Void)
        case display(DisplayableAccountEntropyPool)
    }

    enum AEPContents {
        case partialEntry
        case malformed
        case valid(DisplayableAccountEntropyPool)
    }

    private enum Constants {
        static let layoutMargins = UIEdgeInsets(hMargin: 36, vMargin: 18)
        static let cornerRadius: CGFloat = 26

        static let aepLengthPrecondition: Void = {
            owsPrecondition(Utils.FormatConstants.characterCount == AccountEntropyPool.Constants.byteLength)
        }()
    }

    private let textView = TextViewWithPlaceholder()
    private lazy var textViewHeightConstraint = textView.autoSetDimension(.height, toSize: 400)

    private let mode: Mode

    var aepContents: AEPContents {
        switch mode {
        case .display(let displayableAEP):
            return .valid(displayableAEP)
        case .entry:
            break
        }

        let enteredText = textView.text?.filter { !$0.isWhitespace } ?? ""

        guard enteredText.count == AccountEntropyPool.Constants.byteLength else {
            return .partialEntry
        }

        guard let displayableAEP = try? DisplayableAccountEntropyPool(displayString: enteredText) else {
            return .malformed
        }

        return .valid(displayableAEP)
    }

    init(mode: Mode) {
        self.mode = mode

        _ = Constants.aepLengthPrecondition

        super.init(frame: .zero)

        layer.cornerRadius = Constants.cornerRadius
        layoutMargins = Constants.layoutMargins

        addSubview(textView)
        textView.delegate = self
        textView.spellCheckingType = .no
        textView.autocorrectionType = .no
        textView.textContainerInset = .zero
        textView.keyboardType = .asciiCapable
        textView.placeholderText = OWSLocalizedString(
            "BACKUP_KEY_PLACEHOLDER",
            comment: "Text used as placeholder in recovery key text view.",
        )
        textView.setSecureTextEntry(val: true)
        textView.setTextContentType(val: .password)

        textView.autoPinEdgesToSuperviewMargins()

        switch mode {
        case .display(let displayableAEP):
            textView.isEditable = false
            textView.text = displayableAEP.displayString
        case .entry:
            break
        }

        translatesAutoresizingMaskIntoConstraints = false
        ScreenshotBlocking.setBlocksScreenshots(true, of: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return textView.becomeFirstResponder()
    }

    // MARK: -

    /// The number of rows the text view displays when the entire contents is
    /// visible.
    var rowCount: Int {
        Utils.FormatConstants.rowCount
    }

    /// The number of rows the text view displays. Defaults to "all rows".
    ///
    /// In `display` mode, callers may set to have the text view display a
    /// truncated AEP. Setting this calls `setNeedsLayout`, so callers may
    /// animate sizing changes using `layoutIfNeeded`.
    var visibleRowCount: Int = Utils.FormatConstants.rowCount {
        didSet {
            owsPrecondition((1...Utils.FormatConstants.rowCount).contains(visibleRowCount))

            switch mode {
            case .display(let displayableAEP):
                textView.text = String(displayableAEP.displayString.prefix(
                    Self.Utils.charactersPerRow(includingSpaces: false) * visibleRowCount,
                ))
                setNeedsLayout()
            case .entry:
                owsFail("Visible rows may only be changed in display mode!")
            }
        }
    }

    // MARK: -

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = self.width - self.layoutMargins.totalWidth
        self.textView.editorFont = Self.Utils.fontSize(forWidth: width)
        textViewHeightConstraint.constant = textHeight(forRowCount: visibleRowCount, width: width)
    }

    private func textHeight(forRowCount rowCount: Int, width: CGFloat) -> CGFloat {
        let sizingString = Array(repeating: "0", count: rowCount).joined(separator: "\n")
        return Self.Utils.attributedString(for: sizingString, font: textView.editorFont).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil,
        ).size.ceil.height
    }

    // MARK: - TextViewWithPlaceholderDelegate

    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        Self.Utils.textViewDidUpdateText(textView)

        switch mode {
        case .entry(let onTextViewChanged):
            onTextViewChanged()
        case .display:
            break
        }
    }

    func textView(
        _ textView: TextViewWithPlaceholder,
        uiTextView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String,
    ) -> Bool {
        defer {
            // This isn't called when this function returns false, but
            // we need it to to show and hide the placeholder text
            textView.textViewDidChange(uiTextView)
        }

        Self.Utils.textViewShouldChangeTextIn(
            uiTextView: uiTextView,
            shouldChangeTextIn: range,
            replacementText: text,
            font: textView.editorFont,
        )

        return false
    }

    enum Utils {
        enum FormatConstants {
            static let referenceFontSizePts: CGFloat = 17
            static let lineSpacing: CGFloat = 18

            static let chunkSize = 4
            static let chunksPerRow = 4
            static let rowCount = 4
            static let spacesBetweenChunks = 2

            static let characterCount = chunkSize * chunksPerRow * rowCount
        }

        static func charactersPerRow(includingSpaces: Bool) -> Int {
            let chunkChars = FormatConstants.chunkSize * FormatConstants.chunksPerRow

            if includingSpaces {
                let spaceChars = FormatConstants.spacesBetweenChunks * (FormatConstants.chunksPerRow - 1)
                return chunkChars + spaceChars
            } else {
                return chunkChars
            }
        }

        static func formatAepForTextDisplay(inputText: String) -> String {
            return inputText
                .uppercased()
                .enumerated()
                .map { index, char -> String in
                    if index > 0, index % FormatConstants.chunkSize == 0 {
                        return String(repeating: " ", count: FormatConstants.spacesBetweenChunks) + String(char)
                    } else {
                        return String(char)
                    }
                }
                .joined()
        }

        static func attributedString(for string: String, font: UIFont?) -> NSAttributedString {
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.Signal.label,
                .paragraphStyle: {
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.lineSpacing = FormatConstants.lineSpacing
                    return paragraphStyle
                }(),
            ]

            if let font {
                attributes[.font] = font
            }

            return NSAttributedString(
                string: string,
                attributes: attributes,
            )
        }

        static func fontSize(forWidth width: CGFloat) -> UIFont {
            // Any character will do because font is monospaced.
            let referenceFontSize = "0".size(withAttributes: [
                .font: UIFont.monospacedSystemFont(
                    ofSize: FormatConstants.referenceFontSizePts,
                    weight: .regular,
                ),
            ])

            let characterWidth = width / CGFloat(charactersPerRow(includingSpaces: true))
            let fontSize = (characterWidth / referenceFontSize.width) * FormatConstants.referenceFontSizePts

            return UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }

        static func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
            // For autofill, the text is set without first passing through the formatting code.
            // Detect if the text is not formatted by looking for spaced chunks, and call the
            // formatting function if not.

            let formattedSpace = String(repeating: " ", count: FormatConstants.spacesBetweenChunks)
            if
                let t = textView.text,
                !t.isEmpty,
                t.count > FormatConstants.chunkSize,
                !t.contains(formattedSpace)
            {
                textView.reformatText(replacementText: t)
            }
        }

        static func textViewShouldChangeTextIn(
            uiTextView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String,
            font: UIFont?,
        ) {
            _ = FormattedNumberField.textField(
                uiTextView,
                shouldChangeCharactersIn: range,
                replacementString: text,
                allowedCharacters: DisplayableAccountEntropyPool.allowedCharacters,
                maxCharacters: AccountEntropyPool.Constants.byteLength,
                format: { unformatted in
                    return formatAepForTextDisplay(inputText: unformatted)
                },
            )

            let selectedTextRange = uiTextView.selectedTextRange
            uiTextView.attributedText = attributedString(for: uiTextView.text, font: font)
            uiTextView.selectedTextRange = selectedTextRange
        }
    }
}

// MARK: -

#if DEBUG

private class AEPPreviewViewController: UIViewController {
    let mode: AccountEntropyPoolTextView.Mode

    init(mode: AccountEntropyPoolTextView.Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { owsFail("") }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.groupedBackground

        let textView = AccountEntropyPoolTextView(mode: mode)
        textView.backgroundColor = .Signal.background
        view.addSubview(textView)
        textView.autoPinEdge(toSuperviewMargin: .leading)
        textView.autoPinEdge(toSuperviewMargin: .trailing)
        textView.autoCenterInSuperviewMargins()
    }
}

@available(iOS 17, *)
#Preview("Display") {
    AEPPreviewViewController(mode: .display(AccountEntropyPool().forDisplay))
}

@available(iOS 17, *)
#Preview("Entry") {
    AEPPreviewViewController(mode: .entry(onTextViewChanged: {}))
}

#endif
