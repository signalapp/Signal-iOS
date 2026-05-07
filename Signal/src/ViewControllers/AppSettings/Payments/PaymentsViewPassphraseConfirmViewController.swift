//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PaymentsViewPassphraseConfirmViewController: OWSViewController, UITextFieldDelegate {

    private let passphrase: PaymentsPassphrase

    private weak var viewPassphraseDelegate: PaymentsViewPassphraseDelegate?

    private let wordIndices: [Int]
    private var wordIndex0: Int { wordIndices[0] }
    private var wordIndex1: Int { wordIndices[1] }
    private var word0: String { passphrase.words[wordIndex0] }
    private var word1: String { passphrase.words[wordIndex1] }

    private lazy var wordTextfield0 = createTextfield(wordIndex: wordIndex0)
    private lazy var wordTextfield1 = createTextfield(wordIndex: wordIndex1)

    private let correctnessIconView0 = UIImageView()
    private let correctnessIconView1 = UIImageView()

    private var input0: String {
        wordTextfield0.text?.strippedOrNil ?? ""
    }

    private var input1: String {
        wordTextfield1.text?.strippedOrNil ?? ""
    }

    private var isWordCorrect0: Bool {
        input0.lowercased() == word0.lowercased()
    }

    private var isWordCorrect1: Bool {
        input1.lowercased() == word1.lowercased()
    }

    private var currentCorrectness: [Bool] = [false, false] {
        didSet {
            if
                isViewLoaded,
                currentCorrectness != oldValue
            {
                updateCorrectnessIndicators()
            }
        }
    }

    private var areAllWordsCorrect: Bool {
        Self.correctnessCount(currentCorrectness) == currentCorrectness.count
    }

    private var areAnyWordsCorrect: Bool {
        Self.correctnessCount(currentCorrectness) > 0
    }

    private static func correctnessCount(_ correctness: [Bool]) -> Int {
        correctness.filter { $0 }.count
    }

    init(
        passphrase: PaymentsPassphrase,
        viewPassphraseDelegate: PaymentsViewPassphraseDelegate,
    ) {
        self.passphrase = passphrase
        self.viewPassphraseDelegate = viewPassphraseDelegate
        self.wordIndices = Self.buildWordIndices(forPassphrase: passphrase)

        super.init()
    }

    private static func buildWordIndices(forPassphrase passphrase: PaymentsPassphrase) -> [Int] {
        let allIndices = 0..<PaymentsConstants.passphraseWordCount
        let availableIndices = allIndices.shuffled()
        let wordIndices = Array(availableIndices.prefix(2)).sorted()
        return wordIndices
    }

    private func updateCorrectness() {
        currentCorrectness = [isWordCorrect0, isWordCorrect1]
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_TITLE",
            comment: "Title for the 'confirm words' step of the 'view payments passphrase' views.",
        )

        view.backgroundColor = .Signal.groupedBackground

        let instructionsFormat = OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_EXPLANATION_FORMAT",
            comment: "Format for the explanation of the 'confirm payments passphrase word' step in the 'view payments passphrase' settings, indicating that the user needs to enter two words from their payments passphrase. Embeds: {{ %1$@ the index of the first word, %2$@ the index of the second word }}.",
        )
        let instructions = String.nonPluralLocalizedStringWithFormat(
            instructionsFormat,
            OWSFormat.formatInt(wordIndex0 + 1),
            OWSFormat.formatInt(wordIndex1 + 1),
        )
        let instructionsLabel = UILabel.explanationTextLabel(text: instructions)

        let textFieldContainer0 = buildTextFieldContainer(textField: wordTextfield0)
        let textFieldContainer1 = buildTextFieldContainer(textField: wordTextfield1)

        let confirmButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM",
                comment: "Label for 'confirm' button in the 'view payments passphrase' view of the app settings.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapConfirmButton()
            },
        )

        let seeCodeAgainButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_SEE_PASSPHRASE_AGAIN",
                comment: "Label for 'see passphrase again' button in the 'view payments passphrase' view of the app settings.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapSeePassphraseAgainButton()
            },
        )

        let stackView = addStaticContentStackView(
            arrangedSubviews: [
                .spacer(withHeight: 16),
                instructionsLabel,
                textFieldContainer0,
                textFieldContainer1,
                .vStretchingSpacer(),
                [confirmButton, seeCodeAgainButton].enclosedInVerticalStackView(isFullWidthButtons: true),
            ],
            isScrollable: true,
            shouldAvoidKeyboard: true,
        )
        stackView.setCustomSpacing(24, after: instructionsLabel)
        stackView.setCustomSpacing(16, after: textFieldContainer0)

        updateCorrectnessIndicators()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateFirstResponder()
    }

    private func updateFirstResponder() {
        if !isWordCorrect0 {
            wordTextfield0.becomeFirstResponder()
        } else if !isWordCorrect1 {
            wordTextfield1.becomeFirstResponder()
        }
    }

    private func buildTextFieldContainer(textField: UITextField) -> UIView {
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
        return textFieldContainer
    }

    private func createTextfield(wordIndex: Int) -> UITextField {
        let textField = UITextField()
        textField.delegate = self
        textField.rightViewMode = .always
        textField.textColor = .Signal.label
        textField.tintColor = .Signal.label // caret color
        textField.font = .dynamicTypeBodyClamped
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.returnKeyType = .done
        textField.accessibilityIdentifier = "payments.passphrase.confirm.\(wordIndex)"
        textField.addTarget(self, action: #selector(textfieldDidChange), for: .editingChanged)

        let placeholderFormat = OWSLocalizedString(
            "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_PLACEHOLDER_FORMAT",
            comment: "Format for the placeholder text in the 'confirm payments passphrase' view of the app settings. Embeds: {{ the index of the word }}.",
        )
        textField.placeholder = String.nonPluralLocalizedStringWithFormat(placeholderFormat, OWSFormat.formatInt(wordIndex + 1))
        return textField
    }

    private func updateCorrectnessIndicators() {
        func updateCorrectnessIndicators(
            input: String,
            isWordCorrect: Bool,
            wordTextfield: UITextField,
            correctnessIconView: UIImageView,
        ) {
            // Always show the correct indicator.
            // Hide incorrect indicator if user is typing or hasn't entered any text yet.
            let shouldHideIndicator = !isWordCorrect && (wordTextfield.isFirstResponder || input.isEmpty)
            if shouldHideIndicator {
                wordTextfield.rightView = nil
            } else {
                let iconName = isWordCorrect ? "check-circle" : "x-circle"
                let tintColor: UIColor = isWordCorrect ? .Signal.green : .Signal.red
                correctnessIconView.setTemplateImageName(iconName, tintColor: tintColor)
                correctnessIconView.sizeToFit()
                wordTextfield.rightView = correctnessIconView
            }
        }
        updateCorrectnessIndicators(
            input: input0,
            isWordCorrect: isWordCorrect0,
            wordTextfield: wordTextfield0,
            correctnessIconView: correctnessIconView0,
        )
        updateCorrectnessIndicators(
            input: input1,
            isWordCorrect: isWordCorrect1,
            wordTextfield: wordTextfield1,
            correctnessIconView: correctnessIconView1,
        )
    }

    // MARK: - Events

    private func didTapConfirmButton() {
        guard areAllWordsCorrect else {
            wordTextfield0.resignFirstResponder()
            wordTextfield1.resignFirstResponder()
            updateCorrectnessIndicators()

            let errorMessage: String
            if areAnyWordsCorrect {
                errorMessage = OWSLocalizedString(
                    "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_INVALID_WORD",
                    comment: "Error indicating that at least one word of the payments passphrase is not correct in the 'view payments passphrase' views.",
                )
            } else {
                errorMessage = OWSLocalizedString(
                    "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_INVALID_WORDS",
                    comment: "Error indicating that all words of the payments passphrase are not correct in the 'view payments passphrase' views.",
                )
            }
            OWSActionSheets.showErrorAlert(message: errorMessage)

            return
        }

        let viewPassphraseDelegate = self.viewPassphraseDelegate
        dismiss(animated: true, completion: {
            viewPassphraseDelegate?.viewPassphraseDidComplete()
        })
    }

    private func didTapSeePassphraseAgainButton() {
        navigationController?.popViewController(animated: true)
    }

    @objc
    private func textfieldDidChange() {
        updateCorrectness()
    }

    // MARK: - UITextFieldDelegate

    func textFieldDidBeginEditing(_ textField: UITextField) {
        updateCorrectnessIndicators()
    }

    func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
        updateCorrectnessIndicators()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return true
    }
}
