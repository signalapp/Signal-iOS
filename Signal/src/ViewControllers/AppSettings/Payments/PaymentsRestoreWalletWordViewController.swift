//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PaymentsRestoreWalletWordViewController: OWSViewController, UITextFieldDelegate {

    private weak var restoreWalletDelegate: PaymentsRestoreWalletDelegate?

    private let partialPassphrase: PartialPaymentsPassphrase

    private let wordIndex: Int

    private lazy var textField: UITextField = {
        let textField = UITextField()
        textField.textColor = .Signal.label
        textField.tintColor = .Signal.label // caret color
        textField.font = .dynamicTypeBodyClamped
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.returnKeyType = .done
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        return textField
    }()

    private lazy var warningLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .dynamicTypeCaption1
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .Signal.red
        label.text = OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_INVALID_WORD",
            comment: "Error indicating that the user has entered an invalid word in the 'enter word' step of the 'restore payments wallet' views.",
        )
        label.alpha = 0
        return label
    }()

    private var wordText: String? {
        textField.text?.strippedOrNil?.lowercased()
    }

    private var hasValidWord: Bool {
        isValidWord(wordText)
    }

    private func isValidWord(_ wordText: String?) -> Bool {
        guard let wordText, !wordText.isEmpty else { return false }
        return SUIEnvironment.shared.paymentsSwiftRef.isValidPassphraseWord(wordText)
    }

    func clearInput() {
        partialPassphrase.reset()
        textField.text = ""
    }

    init(
        restoreWalletDelegate: PaymentsRestoreWalletDelegate,
        partialPassphrase: PartialPaymentsPassphrase,
        wordIndex: Int,
    ) {
        self.restoreWalletDelegate = restoreWalletDelegate
        self.partialPassphrase = partialPassphrase
        self.wordIndex = wordIndex

        super.init()

        textField.text = partialPassphrase.getWord(atIndex: wordIndex)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_TITLE",
            comment: "Title for the 'enter word' step of the 'restore payments wallet' views.",
        )

        view.backgroundColor = .Signal.groupedBackground

        let instructionsFormat = OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_INSTRUCTIONS_FORMAT",
            comment: "Format for the instructions for the 'enter word' step of the 'restore payments wallet' views. Embeds {{ the index of the current word }}.",
        )
        let instructions = String.nonPluralLocalizedStringWithFormat(instructionsFormat, OWSFormat.formatInt(wordIndex + 1))
        let instructionsLabel = UILabel.explanationTextLabel(text: instructions)

        let placeholderFormat = OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_PLACEHOLDER_FORMAT",
            comment: "Format for the placeholder text in the 'confirm payments passphrase' view of the app settings. Embeds: {{ the index of the word }}.",
        )
        textField.placeholder = String.nonPluralLocalizedStringWithFormat(
            placeholderFormat,
            OWSFormat.formatInt(wordIndex + 1),
        )

        let textFieldContainer = UIView()
        textFieldContainer.backgroundColor = .Signal.secondaryGroupedBackground
        textFieldContainer.directionalLayoutMargins = .init(
            hMargin: OWSTableViewController2.cellHInnerMargin,
            vMargin: OWSTableViewController2.cellVInnerMargin,
        )
        if #available(iOS 26, *) {
            textFieldContainer.cornerConfiguration = .capsule(maximumRadius: 26)
        } else {
            textFieldContainer.layer.cornerRadius = 10
        }
        textFieldContainer.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: textFieldContainer.layoutMarginsGuide.topAnchor),
            textField.leadingAnchor.constraint(equalTo: textFieldContainer.layoutMarginsGuide.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: textFieldContainer.layoutMarginsGuide.trailingAnchor),
            textField.bottomAnchor.constraint(equalTo: textFieldContainer.layoutMarginsGuide.bottomAnchor),
        ])

        let nextButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.nextButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapNextButton()
            },
        )

        let stackView = addStaticContentStackView(
            arrangedSubviews: [
                .spacer(withHeight: 16),
                instructionsLabel,
                textFieldContainer,
                warningLabel,
                .vStretchingSpacer(),
                nextButton,
                .spacer(withHeight: 16),
            ],
            shouldAvoidKeyboard: true,
        )
        stackView.setCustomSpacing(24, after: instructionsLabel)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        textField.becomeFirstResponder()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        textField.becomeFirstResponder()
    }

    // MARK: - Events

    private func didTapNextButton() {
        guard let restoreWalletDelegate else {
            owsFailDebug("Missing restoreWalletDelegate.")
            dismiss(animated: true, completion: nil)
            return
        }
        guard let wordText, isValidWord(wordText) else {
            warningLabel.alpha = 1
            return
        }
        partialPassphrase.set(word: wordText, index: wordIndex)
        if partialPassphrase.isComplete {
            guard let paymentsPassphrase = partialPassphrase.asPaymentsPassphrase() else {
                OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                    "SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_INVALID_PASSPHRASE",
                    comment: "Error indicating that the user has entered an invalid payments passphrase in the 'restore payments wallet' views.",
                ))
                return
            }
            let view = PaymentsRestoreWalletCompleteViewController(
                restoreWalletDelegate: restoreWalletDelegate,
                passphrase: paymentsPassphrase,
            )
            navigationController?.pushViewController(view, animated: true)
        } else {
            let view = PaymentsRestoreWalletWordViewController(
                restoreWalletDelegate: restoreWalletDelegate,
                partialPassphrase: partialPassphrase,
                wordIndex: wordIndex + 1,
            )
            navigationController?.pushViewController(view, animated: true)
        }
    }

    @objc
    private func textFieldDidChange() {
        // Clear any warning.
        warningLabel.alpha = 0
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        didTapNextButton()
        return false
    }
}

// MARK: -

class PartialPaymentsPassphrase {

    private var wordMap = [Int: String]()

    var isComplete: Bool {
        wordMap.count == PaymentsConstants.passphraseWordCount
    }

    init() {}

    static var empty: PartialPaymentsPassphrase { PartialPaymentsPassphrase() }

    func set(word: String, index: Int) {
        let word = word.stripped
        guard !word.isEmpty else {
            owsFailDebug("Invalid word.")
            return
        }
        wordMap[index] = word
    }

    func getWord(atIndex index: Int) -> String? {
        wordMap[index]
    }

    func asPaymentsPassphrase() -> PaymentsPassphrase? {
        var words = [String]()

        for index in 0..<PaymentsConstants.passphraseWordCount {
            guard let word = wordMap[index] else {
                owsFailDebug("Missing word: \(index)")
                return nil
            }
            words.append(word)
        }

        do {
            return try PaymentsPassphrase(words: words)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    func reset() {
        wordMap.removeAll()
    }
}
