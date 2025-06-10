//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class EnterAccountEntropyPoolViewController: OWSViewController, OWSNavigationChildController {
    enum AEPValidationPolicy {
        case acceptAnyWellFormed
        case acceptOnly(AccountEntropyPool)
    }

    struct ColorConfig {
        let background: UIColor
        let aepEntryBackground: UIColor
    }

    struct HeaderStrings {
        let title: String
        let subtitle: String
    }

    struct FooterButtonConfig {
        let title: String
        let action: () -> Void
    }

    private var aepValidationPolicy: AEPValidationPolicy!
    private var colorConfig: ColorConfig!
    private var footerButtonConfig: FooterButtonConfig!
    private var headerStrings: HeaderStrings!
    private var onEntryConfirmed: ((AccountEntropyPool) -> Void)!

    func configure(
        aepValidationPolicy: AEPValidationPolicy,
        colorConfig: ColorConfig,
        headerStrings: HeaderStrings,
        footerButtonConfig: FooterButtonConfig,
        onEntryConfirmed: @escaping (AccountEntropyPool) -> Void,
    ) {
        self.aepValidationPolicy = aepValidationPolicy
        self.colorConfig = colorConfig
        self.headerStrings = headerStrings
        self.footerButtonConfig = footerButtonConfig
        self.onEntryConfirmed = onEntryConfirmed
    }

    override func viewDidLoad() {
        view.backgroundColor = colorConfig.background
        navigationItem.rightBarButtonItem = nextBarButtonItem

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
            aepTextView,
            aepIssueLabel,
            footerButton,
        ])
        self.view.addSubview(stackView)
        stackView.axis = .vertical
        stackView.spacing = 24
        stackView.setCustomSpacing(16, after: aepTextView)
        stackView.setCustomSpacing(20, after: aepIssueLabel)
        stackView.setCustomSpacing(12, after: titleLabel)
        stackView.autoPinWidthToSuperview(withMargin: 20)
        stackView.autoPinEdge(toSuperviewMargin: .top)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)

        onTextViewUpdated()
    }

    // MARK: -

    private lazy var nextBarButtonItem = UIBarButtonItem(
        title: CommonStrings.nextButton,
        style: .done,
        target: self,
        action: #selector(didTapNext)
    )

    private lazy var aepTextView = {
        let textView = AccountEntropyPoolTextView(onTextViewUpdated: { [weak self] in
                self?.onTextViewUpdated()
        })
        textView.backgroundColor = colorConfig.aepEntryBackground
        return textView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = headerStrings.title
        label.textAlignment = .center
        label.font = .dynamicTypeTitle1.semibold()
        label.numberOfLines = 0
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = headerStrings.subtitle
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.font = .dynamicTypeBody
        label.numberOfLines = 0
        return label
    }()

    private lazy var aepIssueLabel: UILabel = {
        let label = UILabel()
        label.text = "This is never visible!" // Set in `onTextViewUpdated()`
        label.textColor = .ows_accentRed
        label.textAlignment = .center
        label.font = .dynamicTypeBody
        label.numberOfLines = 0
        return label
    }()

    private lazy var footerButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(footerButtonConfig.title, for: .normal)
        button.titleLabel?.font = .dynamicTypeBody.semibold()
        button.setTitleColor(UIColor.Signal.ultramarine, for: .normal)
        button.addTarget(self, action: #selector(didTapNoKeyButton), for: .touchUpInside)
        return button
    }()

    // MARK: -

    @objc
    private func didTapNoKeyButton() {
        footerButtonConfig.action()
    }

    @objc
    private func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: -

    private enum AEPValidationResult {
        case notFullyEntered
        case malformedAEP
        case wellFormedButMismatched
        case success(AccountEntropyPool)
    }

    private func validateAEPText() -> AEPValidationResult {
        let enteredAepText = aepTextView.text.filter {
            $0.isNumber || $0.isLetter
        }

        guard enteredAepText.count == AccountEntropyPool.Constants.byteLength else {
            return .notFullyEntered
        }

        guard let enteredAep = try? AccountEntropyPool(key: enteredAepText) else {
            return .malformedAEP
        }

        switch aepValidationPolicy! {
        case .acceptAnyWellFormed:
            return .success(enteredAep)
        case .acceptOnly(let expectedAep):
            if enteredAep.rawData == expectedAep.rawData {
                return .success(enteredAep)
            } else {
                return .wellFormedButMismatched
            }
        }
    }

    private func onTextViewUpdated() {
        switch validateAEPText() {
        case .notFullyEntered:
            nextBarButtonItem.isEnabled = false
            aepIssueLabel.alpha = 0
        case .malformedAEP:
            nextBarButtonItem.isEnabled = false
            aepIssueLabel.text = OWSLocalizedString(
                "ENTER_ACCOUNT_ENTROPY_POOL_VIEW_MALFORMED_AEP_LABEL",
                comment: "Label explaining that an entered 'Backup Key' is malformed."
            )
            aepIssueLabel.alpha = 1
        case .wellFormedButMismatched:
            nextBarButtonItem.isEnabled = false
            aepIssueLabel.text = OWSLocalizedString(
                "ENTER_ACCOUNT_ENTROPY_POOL_VIEW_INCORRECT_AEP_LABEL",
                comment: "Label explaining that an entered 'Backup Key' is incorrect."
            )
            aepIssueLabel.alpha = 1
        case .success:
            nextBarButtonItem.isEnabled = true
            aepIssueLabel.alpha = 0
        }
    }

    @objc
    private func didTapNext() {
        switch validateAEPText() {
        case .notFullyEntered, .malformedAEP, .wellFormedButMismatched:
            owsFailDebug("Next button should be disabled!")
        case .success(let aep):
            aepTextView.resignFirstResponder()
            onEntryConfirmed(aep)
        }
    }
}

// MARK: -

private class AccountEntropyPoolTextView: UIView {
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

    var text: String { textView.text ?? "" }

    let onTextViewUpdated: () -> Void

    init(onTextViewUpdated: @escaping () -> Void) {
        self.onTextViewUpdated = onTextViewUpdated

        super.init(frame: .zero)

        layer.cornerRadius = 10

        layoutMargins = .init(hMargin: 20, vMargin: 14)
        addSubview(textView)
        textView.delegate = self
        textView.spellCheckingType = .no
        textView.autocorrectionType = .no
        textView.textContainerInset = .zero
        textView.keyboardType = .asciiCapable
        textView.autoPinEdgesToSuperviewMargins()
        textView.placeholderText = OWSLocalizedString(
            "BACKUP_KEY_PLACEHOLDER",
            comment: "Text used as placeholder in backup key text view."
        )

        self.translatesAutoresizingMaskIntoConstraints = false
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
                weight: .regular
            )
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
            context: nil
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
            ]
        )
    }
}

// MARK: -

extension AccountEntropyPoolTextView: TextViewWithPlaceholderDelegate {

    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        onTextViewUpdated()
    }

    func textView(
        _ textView: TextViewWithPlaceholder,
        uiTextView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
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
                return unformatted.lowercased()
                    .enumerated()
                    .map { index, char -> String in
                        if index > 0, index % Constants.chunkSize == 0 {
                            return String(repeating: " ", count: Constants.spacesBetweenChunks) + String(char)
                        } else {
                            return String(char)
                        }
                    }
                    .joined()
            }
        )

        let selectedTextRange = uiTextView.selectedTextRange
        uiTextView.attributedText = self.attributedString(for: uiTextView.text)
        uiTextView.selectedTextRange = selectedTextRange

        return false
    }
}

// MARK: -

#if DEBUG

private extension EnterAccountEntropyPoolViewController {
    static func forPreview() -> EnterAccountEntropyPoolViewController {
        let viewController = EnterAccountEntropyPoolViewController()
        viewController.configure(
            aepValidationPolicy: .acceptAnyWellFormed,
            colorConfig: ColorConfig(
                background: UIColor.Signal.background,
                aepEntryBackground: UIColor.Signal.quaternaryFill,
            ),
            headerStrings: HeaderStrings(
                title: "This is a Title",
                subtitle: "And this, longer, less important string, is a subtitle!"
            ),
            footerButtonConfig: FooterButtonConfig(
                title: "Footer Button",
                action: { print("Footer button!") }
            ),
            onEntryConfirmed: { print("Confirmed: \($0.rawData)") }
        )
        return viewController
    }
}

@available(iOS 17, *)
#Preview {
    return EnterAccountEntropyPoolViewController.forPreview()
}

#endif
