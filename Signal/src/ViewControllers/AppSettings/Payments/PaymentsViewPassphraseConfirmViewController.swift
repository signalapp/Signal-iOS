//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalMessaging

public class PaymentsViewPassphraseConfirmViewController: OWSTableViewController2 {

    private let passphrase: PaymentsPassphrase

    private weak var viewPassphraseDelegate: PaymentsViewPassphraseDelegate?

    private let bottomStack = UIStackView()

    open override var bottomFooter: UIView? {
        get { bottomStack }
        set {}
    }

    private let wordIndices: [Int]
    private var wordIndex0: Int { wordIndices[0] }
    private var wordIndex1: Int { wordIndices[1] }
    private var word0: String { passphrase.words[wordIndex0] }
    private var word1: String { passphrase.words[wordIndex1] }

    private let wordTextfield0 = UITextField()
    private let wordTextfield1 = UITextField()

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
            if isViewLoaded,
               currentCorrectness != oldValue {
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

    public required init(passphrase: PaymentsPassphrase,
                         viewPassphraseDelegate: PaymentsViewPassphraseDelegate) {
        self.passphrase = passphrase
        self.viewPassphraseDelegate = viewPassphraseDelegate
        self.wordIndices = Self.buildWordIndices(forPassphrase: passphrase)

        super.init()

        self.shouldAvoidKeyboard = true
    }

    private static func buildWordIndices(forPassphrase passphrase: PaymentsPassphrase) -> [Int] {
        let allIndices = 0..<PaymentsConstants.passphraseWordCount
        let availableIndices = allIndices.shuffled()
        let wordIndices = Array(availableIndices.prefix(2)).sorted()
        return wordIndices
    }

    private func updateCorrectness() {
        currentCorrectness = [ isWordCorrect0, isWordCorrect1 ]
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_TITLE",
                                  comment: "Title for the 'view payments passphrase' view of the app settings.")

        createViews()
        buildBottomView()
        updateTableContents()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateFirstResponder()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        wordTextfield0.textColor = Theme.primaryTextColor
        wordTextfield1.textColor = Theme.primaryTextColor
        buildBottomView()

        updateTableContents()
    }

    private func updateFirstResponder() {
        if !isWordCorrect0 {
            wordTextfield0.becomeFirstResponder()
        } else if !isWordCorrect1 {
            wordTextfield1.becomeFirstResponder()
        }
    }

    private func createViews() {
        func configureTextfield(_ textfield: UITextField, wordIndex: Int) {
            textfield.delegate = self
            textfield.textColor = Theme.primaryTextColor
            textfield.font = .dynamicTypeBodyClamped
            textfield.keyboardAppearance = Theme.keyboardAppearance
            textfield.autocapitalizationType = .none
            textfield.autocorrectionType = .no
            textfield.spellCheckingType = .no
            textfield.smartQuotesType = .no
            textfield.smartDashesType = .no
            textfield.returnKeyType = .done
            textfield.accessibilityIdentifier = "payments.passphrase.confirm.\(wordIndex)"
            textfield.addTarget(self, action: #selector(textfieldDidChange), for: .editingChanged)

            let placeholderFormat = OWSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_PLACEHOLDER_FORMAT",
                                                      comment: "Format for the placeholder text in the 'confirm payments passphrase' view of the app settings. Embeds: {{ the index of the word }}.")
            textfield.placeholder = String(format: placeholderFormat, OWSFormat.formatInt(wordIndex + 1))
        }
        configureTextfield(wordTextfield0, wordIndex: wordIndex0)
        configureTextfield(wordTextfield1, wordIndex: wordIndex1)
    }

    private func buildBottomView() {
        let confirmButton = OWSFlatButton.insetButton(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM",
                comment: "Label for 'confirm' button in the 'view payments passphrase' view of the app settings."),
            font: UIFont.dynamicTypeBody.semibold(),
            titleColor: .white,
            backgroundColor: .ows_accentBlue,
            target: self,
            selector: #selector(didTapConfirmButton)
        )

        confirmButton.autoSetHeightUsingFont()
        confirmButton.cornerRadius = 14

        let backButton = OWSFlatButton.insetButton(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_VIEW_PASSPHRASE_SEE_PASSPHRASE_AGAIN",
                comment: "Label for 'see passphrase again' button in the 'view payments passphrase' view of the app settings."),
            font: UIFont.dynamicTypeBody.semibold(),
            titleColor: .ows_accentBlue,
            backgroundColor: self.tableBackgroundColor,
            target: self,
            selector: #selector(didTapSeePassphraseAgainButton)
        )

        backButton.autoSetHeightUsingFont()

        bottomStack.axis = .vertical
        bottomStack.alignment = .fill
        bottomStack.isLayoutMarginsRelativeArrangement = true
        bottomStack.layoutMargins = cellOuterInsetsWithMargin(top: 8, left: 20, right: 20)
        bottomStack.removeAllSubviews()
        bottomStack.addArrangedSubviews([
            confirmButton,
            UIView.spacer(withHeight: 8),
            backButton,
            UIView.spacer(withHeight: 8)
        ])
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        let contents = OWSTableContents()

        let section0 = OWSTableSection()
        let section1 = OWSTableSection()
        section0.customHeaderView = buildConfirmHeader()
        section0.shouldDisableCellSelection = true
        section1.shouldDisableCellSelection = true

        func buildWordRow(wordTextfield: UITextField,
                          correctnessIconView: UIView,
                          isCorrect: Bool) -> OWSTableItem {
            OWSTableItem(customCellBlock: {
                let cell = OWSTableItem.newCell()
                let stack = UIStackView(arrangedSubviews: [
                                            wordTextfield,
                                            correctnessIconView
                ])
                stack.axis = .horizontal
                stack.alignment = .center
                stack.spacing = 8
                cell.contentView.addSubview(stack)
                stack.autoPinEdgesToSuperviewMargins()
                wordTextfield.setContentHuggingHorizontalLow()
                correctnessIconView.setContentHuggingHigh()
                correctnessIconView.setCompressionResistanceHigh()

                return cell
            },
            actionBlock: nil)
        }

        section0.add(buildWordRow(wordTextfield: wordTextfield0,
                                  correctnessIconView: correctnessIconView0,
                                  isCorrect: isWordCorrect0))
        section1.add(buildWordRow(wordTextfield: wordTextfield1,
                                  correctnessIconView: correctnessIconView1,
                                  isCorrect: isWordCorrect1))
        contents.add(section0)
        contents.add(section1)

        self.contents = contents

        updateCorrectnessIndicators()
    }

    private func updateCorrectnessIndicators() {

        func updateCorrectnessIndicators(input: String,
                                         isWordCorrect: Bool,
                                         wordTextfield: UITextField,
                                         correctnessIconView: UIImageView) {
            let iconName = isWordCorrect ? "check-circle" : "x-circle"
            let tintColor: UIColor = isWordCorrect ? .ows_accentGreen : .ows_accentRed
            correctnessIconView.setTemplateImageName(iconName, tintColor: tintColor)
            // Always show the correct indicator.
            // Hide incorrect indicator if user is typing or hasn't entered any text yet.
            let shouldHideIndicator = !isWordCorrect && (wordTextfield.isFirstResponder || input.isEmpty)
            if shouldHideIndicator {
                correctnessIconView.tintColor = .clear
            }
        }
        updateCorrectnessIndicators(input: input0,
                                    isWordCorrect: isWordCorrect0,
                                    wordTextfield: wordTextfield0,
                                    correctnessIconView: correctnessIconView0)
        updateCorrectnessIndicators(input: input1,
                                    isWordCorrect: isWordCorrect1,
                                    wordTextfield: wordTextfield1,
                                    correctnessIconView: correctnessIconView1)
    }

    private func buildConfirmHeader() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_TITLE",
                                            comment: "Title for the 'confirm words' step of the 'view payments passphrase' views.")
        titleLabel.font = UIFont.dynamicTypeTitle2Clamped.semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center

        let explanationForm = OWSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_EXPLANATION_FORMAT",
                                                comment: "Format for the explanation of the 'confirm payments passphrase word' step in the 'view payments passphrase' settings, indicating that the user needs to enter two words from their payments passphrase. Embeds: {{ %1$@ the index of the first word, %2$@ the index of the second word }}.")
        let explanation = String(format: explanationForm,
                                 OWSFormat.formatInt(wordIndex0 + 1),
                                 OWSFormat.formatInt(wordIndex1 + 1))

        let explanationLabel = UILabel()
        explanationLabel.text = explanation
        explanationLabel.font = .dynamicTypeBody2Clamped
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.textAlignment = .center
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping

        let topStack = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 10),
            explanationLabel,
            UIView.spacer(withHeight: 40)
        ])
        topStack.axis = .vertical
        topStack.alignment = .center
        topStack.isLayoutMarginsRelativeArrangement = true
        topStack.layoutMargins = cellOuterInsetsWithMargin(top: 32, left: 20, right: 20)
        return topStack
    }

    // MARK: - Events

    @objc
    private func didTapConfirmButton() {
        guard areAllWordsCorrect else {
            wordTextfield0.resignFirstResponder()
            wordTextfield1.resignFirstResponder()
            updateCorrectnessIndicators()

            let errorMessage: String
            if areAnyWordsCorrect {
                errorMessage = OWSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_INVALID_WORD",
                                                 comment: "Error indicating that at least one word of the payments passphrase is not correct in the 'view payments passphrase' views.")
            } else {
                errorMessage = OWSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_INVALID_WORDS",
                                                 comment: "Error indicating that all words of the payments passphrase are not correct in the 'view payments passphrase' views.")
            }
            OWSActionSheets.showErrorAlert(message: errorMessage)

            return
        }

        let viewPassphraseDelegate = self.viewPassphraseDelegate
        dismiss(animated: true, completion: {
            viewPassphraseDelegate?.viewPassphraseDidComplete()
        })
    }

    @objc
    private func didTapSeePassphraseAgainButton() {
        navigationController?.popViewController(animated: true)
    }

    @objc
    private func textfieldDidChange() {
        updateCorrectness()
    }
}

// MARK: -

extension PaymentsViewPassphraseConfirmViewController: UITextFieldDelegate {
    public func textFieldDidBeginEditing(_ textField: UITextField) {
        updateCorrectnessIndicators()
    }

    public func textFieldDidEndEditing(_ textField: UITextField, reason: UITextField.DidEndEditingReason) {
        updateCorrectnessIndicators()
    }

    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return true
    }
}
