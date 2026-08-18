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

        static let referenceFontSizePts: CGFloat = 17
        static let lineSpacing: CGFloat = 18

        static let chunkSize = 4
        static let chunksPerRow = 4
        static let rowCount = 4
        static let spacesBetweenChunks = 2

        static func charactersPerRow(includingSpaces: Bool) -> Int {
            let chunkChars = Constants.chunkSize * Constants.chunksPerRow

            if includingSpaces {
                let spaceChars = Constants.spacesBetweenChunks * (Constants.chunksPerRow - 1)
                return chunkChars + spaceChars
            } else {
                return chunkChars
            }
        }

        static let aepLengthPrecondition: Void = {
            let characterCount = chunkSize * chunksPerRow * rowCount
            owsPrecondition(characterCount == AccountEntropyPool.Constants.byteLength)
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
        ScreenshotBlocking.blockScreenshots(of: self)
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
        Constants.rowCount
    }

    /// The number of rows the text view displays. Defaults to "all rows".
    ///
    /// In `display` mode, callers may set to have the text view display a
    /// truncated AEP. Setting this calls `setNeedsLayout`, so callers may
    /// animate sizing changes using `layoutIfNeeded`.
    var visibleRowCount: Int = Constants.rowCount {
        didSet {
            owsPrecondition((1...Constants.rowCount).contains(visibleRowCount))

            switch mode {
            case .display(let displayableAEP):
                textView.text = String(displayableAEP.displayString.prefix(
                    Constants.charactersPerRow(includingSpaces: false) * visibleRowCount,
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

        // Any character will do because font is monospaced.
        let referenceFontSize = "0".size(withAttributes: [
            .font: UIFont.monospacedSystemFont(
                ofSize: Constants.referenceFontSizePts,
                weight: .regular,
            ),
        ])

        let characterWidth = width / CGFloat(Constants.charactersPerRow(includingSpaces: true))
        let fontSize = (characterWidth / referenceFontSize.width) * Constants.referenceFontSizePts

        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        self.textView.editorFont = font

        textViewHeightConstraint.constant = textHeight(forRowCount: visibleRowCount, width: width)
    }

    private func textHeight(forRowCount rowCount: Int, width: CGFloat) -> CGFloat {
        let sizingString = Array(repeating: "0", count: rowCount).joined(separator: "\n")
        return attributedString(for: sizingString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil,
        ).size.ceil.height
    }

    private func attributedString(for string: String) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.Signal.label,
            .paragraphStyle: {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = Constants.lineSpacing
                return paragraphStyle
            }(),
        ]

        if let editorFont = textView.editorFont {
            attributes[.font] = editorFont
        }

        return NSAttributedString(
            string: string,
            attributes: attributes,
        )
    }

    // MARK: - TextViewWithPlaceholderDelegate

    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        // For autofill, the text is set without first passing through the formatting code.
        // Detect if the text is not formatted by looking for spaced chunks, and call the
        // formatting function if not.
        let formattedSpace = String(repeating: " ", count: Constants.spacesBetweenChunks)
        if
            let t = textView.text,
            !t.isEmpty,
            t.count > Constants.chunkSize,
            !t.contains(formattedSpace)
        {
            textView.reformatText(replacementText: t)
        }

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

        _ = FormattedNumberField.textField(
            uiTextView,
            shouldChangeCharactersIn: range,
            replacementString: text,
            allowedCharacters: DisplayableAccountEntropyPool.allowedCharacters,
            maxCharacters: AccountEntropyPool.Constants.byteLength,
            format: { unformatted in
                return unformatted
                    .uppercased()
                    .enumerated()
                    .map { index, char -> String in
                        if index > 0, index % Constants.chunkSize == 0 {
                            return String(repeating: " ", count: Constants.spacesBetweenChunks) + String(char)
                        } else {
                            return String(char)
                        }
                    }
                    .joined()
            },
        )

        let selectedTextRange = uiTextView.selectedTextRange
        uiTextView.attributedText = self.attributedString(for: uiTextView.text)
        uiTextView.selectedTextRange = selectedTextRange

        return false
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
