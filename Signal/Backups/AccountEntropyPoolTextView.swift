//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class AccountEntropyPoolTextView: UIView {
    enum Mode {
        case entry(onTextViewChanged: () -> Void)
        case display(aep: AccountEntropyPool)
    }

    private enum Constants {
        static let chunkSize = 4
        static let chunksPerRow = 4
        static let rowCount = 4
        static let spacesBetweenChunks = 4

        static var charactersPerRow: Int {
            let chunkChars = Constants.chunkSize * Constants.chunksPerRow
            let spaceChars = Constants.spacesBetweenChunks * (Constants.chunksPerRow - 1)

            return chunkChars + spaceChars
        }

        private static let aepLengthPrecondition: Void = {
            let characterCount = chunkSize * chunksPerRow * rowCount
            owsPrecondition(characterCount == AccountEntropyPool.Constants.byteLength)
        }()
    }

    private let textView = TextViewWithPlaceholder()
    private lazy var heightConstraint = textView.autoSetDimension(.height, toSize: 400)

    private let mode: Mode

    var text: String { textView.text ?? "" }

    init(mode: Mode) {
        self.mode = mode

        super.init(frame: .zero)

        layer.cornerRadius = 10
        layoutMargins = .init(hMargin: 24, vMargin: 14)

        addSubview(textView)
        textView.delegate = self
        textView.spellCheckingType = .no
        textView.autocorrectionType = .no
        textView.textContainerInset = .zero
        textView.keyboardType = .asciiCapable
        textView.autoPinEdgesToSuperviewMargins()
        textView.placeholderText = OWSLocalizedString(
            "BACKUP_KEY_PLACEHOLDER",
            comment: "Text used as placeholder in recovery key text view.",
        )
        textView.setSecureTextEntry(val: true)
        textView.setTextContentType(val: .password)

        switch mode {
        case .display(let aep):
            textView.isEditable = false
            textView.text = aep.displayString
        case .entry:
            break
        }

        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = self.width - self.layoutMargins.totalWidth

        let referenceFontSizePts: CGFloat = 17
        // Any character will do because font is monospaced.
        let referenceFontSize = "0".size(withAttributes: [
            .font: UIFont.monospacedSystemFont(
                ofSize: referenceFontSizePts,
                weight: .regular,
            ),
        ])

        let characterWidth = width / CGFloat(Constants.charactersPerRow)
        let fontSize = (characterWidth / referenceFontSize.width) * referenceFontSizePts

        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        self.textView.editorFont = font

        let sizingString = Array(repeating: "0", count: Constants.rowCount).joined(separator: "\n")
        let sizingAttributedString = self.attributedString(for: sizingString)
        self.heightConstraint.constant = sizingAttributedString.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil,
        ).size.ceil.height
    }

    private func attributedString(for string: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 14
        return NSAttributedString(
            string: string,
            attributes: [
                .font: textView.editorFont ?? UIFont.monospacedDigitFont(ofSize: 17),
                .foregroundColor: UIColor.Signal.label,
                .paragraphStyle: paragraphStyle,
            ],
        )
    }
}

// MARK: -

extension AccountEntropyPoolTextView: TextViewWithPlaceholderDelegate {

    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        // For autofill, the text is set without first passing through the formatting code.
        // Detect if the text is not formatted by looking for spaced chunks, and call the
        // formatting function if not.
        let formattedSpace = String(repeating: " ", count: Constants.spacesBetweenChunks)
        if
            let t = textView.text,
            !t.isEmpty,
            t.count > Constants.spacesBetweenChunks,
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
            allowedCharacters: .alphanumeric,
            maxCharacters: AccountEntropyPool.Constants.byteLength,
            format: { unformatted in
                return unformatted.uppercased()
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

        let textView = AccountEntropyPoolTextView(mode: mode)
        textView.backgroundColor = .Signal.secondaryBackground
        view.addSubview(textView)
        textView.autoPinEdge(toSuperviewMargin: .leading)
        textView.autoPinEdge(toSuperviewMargin: .trailing)
        textView.autoCenterInSuperviewMargins()
    }
}

@available(iOS 17, *)
#Preview("Display") {
    AEPPreviewViewController(mode: .display(aep: AccountEntropyPool()))
}

@available(iOS 17, *)
#Preview("Entry") {
    AEPPreviewViewController(mode: .entry(onTextViewChanged: {}))
}

#endif
