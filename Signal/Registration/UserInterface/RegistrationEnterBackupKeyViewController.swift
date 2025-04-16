//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

protocol RegistrationEnterBackupKeyPresenter: AnyObject {
    func next(accountEntropyPool: AccountEntropyPool)
}

class RegistrationEnterBackupKeyViewController: OWSViewController, OWSNavigationChildController {
    private weak var presenter: RegistrationEnterBackupKeyPresenter?

    init(presenter: RegistrationEnterBackupKeyPresenter) {
        self.presenter = presenter
        super.init()

        // TODO: [Backups] Disable this next button until the input is valid
        navigationItem.rightBarButtonItem = nextBarButton

        self.view.backgroundColor = UIColor.Signal.background

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            descriptionLabel,
            codeEntry,
            noKeyButton,
        ])
        self.view.addSubview(stackView)
        stackView.axis = .vertical
        stackView.spacing = 24
        stackView.setCustomSpacing(12, after: titleLabel)
        stackView.autoPinWidthToSuperview(withMargin: 20)
        stackView.autoPinEdge(toSuperviewMargin: .top)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
    }

    // MARK: OWSNavigationChildController

    public var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }

    public var navbarBackgroundColorOverride: UIColor? { .clear }

    // MARK: UI

    private lazy var codeEntry = BackupCodeEntry(frame: .zero)

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "REGISTRATION_ENTER_BACKUP_KEY_TITLE",
            comment: "Title for the screen that allows users to enter their backup key."
        )
        label.textAlignment = .center
        label.font = .dynamicTypeTitle1.semibold()
        label.numberOfLines = 0
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "REGISTRATION_ENTER_BACKUP_KEY_DESCRIPTION",
            comment: "Description for the screen that allows users to enter their backup key."
        )
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var noKeyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(
            OWSLocalizedString(
                "REGISTRATION_NO_BACKUP_KEY_BUTTON_TITLE",
                comment: "Title of button to tap if you do not have a backup key during registration."
            ),
            for: .normal
        )
        button.titleLabel?.font = .dynamicTypeBody.semibold()
        button.setTitleColor(UIColor.Signal.ultramarine, for: .normal)
        button.addTarget(self, action: #selector(didTapNoKeyButton), for: .touchUpInside)
        return button
    }()

    @objc
    private func didTapNoKeyButton() {
        let sheet = HeroSheetViewController(
            hero: .circleIcon(
                icon: UIImage(named: "key")!,
                iconSize: 35,
                tintColor: UIColor.Signal.label,
                backgroundColor: UIColor.Signal.background
            ),
            title: OWSLocalizedString(
                "REGISTRATION_NO_BACKUP_KEY_SHEET_TITLE",
                comment: "Title for sheet with info for what to do if you don't have a backup key"
            ),
            body: OWSLocalizedString(
                "REGISTRATION_NO_BACKUP_KEY_SHEET_BODY",
                comment: "Body text on a sheet with info for what to do if you don't have a backup key"
            ),
            primaryButton: .init(title: OWSLocalizedString(
                "REGISTRATION_NO_BACKUP_KEY_SKIP_RESTORE_BUTTON_TITLE",
                comment: "Title for button on sheet for when you don't have a backup key"
            )) { [weak self] in
                // [Backups] TODO: Implement
                self?.dismiss(animated: true)
            },
            secondaryButton: .init(title: CommonStrings.learnMore) { [weak self] in
                // [Backups] TODO: Implement
                self?.dismiss(animated: true)
            }
        )
        self.present(sheet, animated: true)
    }

    @objc
    private func dismissKeyboard() {
        view.endEditing(true)
    }

    private lazy var nextBarButton = UIBarButtonItem(
        title: CommonStrings.nextButton,
        style: .done,
        target: self,
        action: #selector(didTapNext)
    )

    @objc
    private func didTapNext() {
        guard canSubmit else { return }
        codeEntry.resignFirstResponder()
        guard let aep = try? AccountEntropyPool(key: codeEntry.text.filter({!$0.isWhitespace})) else {
            // TODO: [Backups] Present an error about invalid AEP entry here
            return
        }
        self.presenter?.next(accountEntropyPool: aep)
    }

    private var canSubmit: Bool {
        let codeCharCount = codeEntry.text.filter {
            $0.isNumber || $0.isLetter
        }.count

        let expectedCodeCharCount = BackupCodeEntry.Constants.maxCharacterCount

        return codeCharCount == expectedCodeCharCount
    }
}

private class BackupCodeEntry: UIView {
    fileprivate enum Constants {
        static let chunkSize = 4
        static let chunksPerRow = 4
        static let spacesBetweenChunks = 4
        static let totalChunks = 16

        static var maxCharacterCount: Int {
            Constants.totalChunks * Constants.chunkSize
        }
    }

    private let textView = TextViewWithPlaceholder()
    private lazy var heightConstraint = textView.autoSetDimension(.height, toSize: 400)

    var text: String { textView.text ?? "" }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor.Signal.quaternaryFill
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

    override func layoutSubviews() {
        super.layoutSubviews()
        self.updateSizing()
    }

    private func updateSizing() {
        let width = self.width - self.layoutMargins.totalWidth

        let referenceFontSizePts: CGFloat = 17
        // Any character will do because font is monospaced.
        let referenceFontSize = "0".size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: referenceFontSizePts, weight: .regular)])

        let charactersPerLine: Int = Constants.chunkSize * Constants.chunksPerRow + Constants.spacesBetweenChunks * (Constants.chunksPerRow - 1)

        let characterWidth = width / CGFloat(charactersPerLine)
        let fontSize = (characterWidth / referenceFontSize.width) * referenceFontSizePts

        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        self.textView.editorFont = font

        let maxLineCount = Constants.totalChunks / Constants.chunksPerRow
        let sizingString = Array(repeating: "0", count: maxLineCount).joined(separator: "\n")
        let sizingAttributedString = self.attributedString(for: sizingString)
        self.heightConstraint.constant = sizingAttributedString.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).size.ceil.height
    }
}

extension BackupCodeEntry: TextViewWithPlaceholderDelegate {
    private nonisolated static func formatBackupKey(unformatted: String) -> String {
        unformatted.lowercased().formattedWithSpaces(
            every: Constants.chunkSize,
            separator: String(repeating: " ", count: Constants.spacesBetweenChunks)
        )
    }

    func textView(_ textView: TextViewWithPlaceholder, uiTextView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
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
            maxCharacters: Constants.maxCharacterCount,
            format: Self.formatBackupKey(unformatted:)
        )

        let selectedTextRange = uiTextView.selectedTextRange
        uiTextView.attributedText = self.attributedString(for: uiTextView.text)
        uiTextView.selectedTextRange = selectedTextRange

        return false
    }

    func attributedString(for string: String) -> NSAttributedString {
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

private extension String {
    func formattedWithSpaces(every n: Int, separator: String) -> String {
        guard n > 0 else { return self }
        return self.enumerated().map { $0.offset % n == 0 && $0.offset != 0 ? "\(separator)\($0.element)" : "\($0.element)" }.joined()
    }
}

#if DEBUG
private class PreviewRegistrationEnterBackupKeyPresenter: RegistrationEnterBackupKeyPresenter {
    func next(accountEntropyPool: AccountEntropyPool) {
        print("next")
    }
}

@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationEnterBackupKeyPresenter()
    return RegistrationEnterBackupKeyViewController(presenter: presenter)
}
#endif
