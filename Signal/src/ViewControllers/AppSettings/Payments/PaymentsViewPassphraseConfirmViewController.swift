//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class PaymentsViewPassphraseConfirmViewController: OWSTableViewController2 {

    private let passphrase: PaymentsPassphrase

    private weak var viewPassphraseDelegate: PaymentsViewPassphraseDelegate?

    private let bottomStack = UIStackView()

    open override var bottomFooter: UIView? { bottomStack }

    private let warningLabel = UILabel()

    private let wordIndices: [Int]
    private var wordIndex0: Int { wordIndices[0] }
    private var wordIndex1: Int { wordIndices[1] }
    private var word0: String { passphrase.words[wordIndex0] }
    private var word1: String { passphrase.words[wordIndex1] }

    private let wordTextfield0 = UITextField()
    private let wordTextfield1 = UITextField()

    private var input0: String {
        wordTextfield0.text?.stripped ?? ""
    }

    private var input1: String {
        wordTextfield1.text?.stripped ?? ""
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
                updateContents()

                let oldCorrectCount = Self.correctnessCount(oldValue)
                let newCorrectCount = Self.correctnessCount(currentCorrectness)
                let didJustAddCorrect = newCorrectCount > oldCorrectCount
                if didJustAddCorrect {
                    updateFirstResponder()
                }
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

        title = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_TITLE",
                                  comment: "Title for the 'view payments passphrase' view of the app settings.")

        createViews()
        buildBottomView()
        updateContents()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateContents()
    }

    public override func viewDidAppear(_ animated: Bool) {
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

    private func createViews() {
        func configureTextfield(_ textfield: UITextField, wordIndex: Int) {
            textfield.delegate = self
            textfield.textColor = Theme.primaryTextColor
            textfield.font = .ows_dynamicTypeBodyClamped
            textfield.keyboardAppearance = Theme.keyboardAppearance
            textfield.autocapitalizationType = .none
            textfield.autocorrectionType = .no
            textfield.spellCheckingType = .no
            textfield.smartQuotesType = .no
            textfield.smartDashesType = .no
            textfield.returnKeyType = .done
            textfield.accessibilityIdentifier = "payments.passphrase.confirm.\(wordIndex)"
            textfield.addTarget(self, action: #selector(textfieldDidChange), for: .editingChanged)

            let placeholderFormat = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_PLACEHOLDER_FORMAT",
                                                      comment: "Format for the placeholder text in the 'confirm payments passphrase' view of the app settings. Embeds: {{ the index of the word }}.")
            textfield.placeholder = String(format: placeholderFormat, OWSFormat.formatInt(wordIndex + 1))
        }
        configureTextfield(wordTextfield0, wordIndex: wordIndex0)
        configureTextfield(wordTextfield1, wordIndex: wordIndex1)
    }

    private func buildBottomView() {
        let confirmButton = OWSFlatButton.button(title: NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM",
                                                                          comment: "Label for 'confirm' button in the 'view payments passphrase' view of the app settings."),
                                                 font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                                 titleColor: .white,
                                                 backgroundColor: .ows_accentBlue,
                                                 target: self,
                                                 selector: #selector(didTapConfirmButton))
        confirmButton.autoSetHeightUsingFont()

        let backButton = OWSFlatButton.button(title: NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_SEE_PASSPHRASE_AGAIN",
                                                                       comment: "Label for 'see passphrase again' button in the 'view payments passphrase' view of the app settings."),
                                              font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                              titleColor: .ows_accentBlue,
                                              backgroundColor: self.tableBackgroundColor,
                                              target: self,
                                              selector: #selector(didTapSeePassphraseAgainButton))
        backButton.autoSetHeightUsingFont()

        bottomStack.axis = .vertical
        bottomStack.alignment = .fill
        bottomStack.isLayoutMarginsRelativeArrangement = true
        let hMargin = 20 + OWSTableViewController2.cellHOuterMargin
        bottomStack.layoutMargins = UIEdgeInsets(top: 8, leading: hMargin, bottom: 0, trailing: hMargin)
        bottomStack.addArrangedSubviews([
            confirmButton,
            UIView.spacer(withHeight: 8),
            backButton,
            UIView.spacer(withHeight: 8)
        ])
    }

    private func updateContents() {
        updateTableContents()
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        let contents = OWSTableContents()

        let section0 = OWSTableSection()
        let section1 = OWSTableSection()
        section0.customHeaderView = buildConfirmHeader()

        func buildWordRow(wordIndex: Int,
                          wordTextfield: UITextField,
                          isCorrect: Bool) -> OWSTableItem {
            OWSTableItem(customCellBlock: {
                let cell = OWSTableItem.newCell()

                let stack = UIStackView(arrangedSubviews: [ wordTextfield ])
                stack.axis = .horizontal
                stack.alignment = .center
                stack.spacing = 8
                cell.contentView.addSubview(stack)
                stack.autoPinEdgesToSuperviewMargins()

                let iconHeight: CGFloat = 24
                if isCorrect {
                    let correctView = UIImageView.withTemplateImageName("check-circle-outline-24",
                                                                        tintColor: .ows_accentGreen)
                    correctView.autoSetDimensions(to: .square(iconHeight))
                    stack.addArrangedSubview(correctView)
                } else {
                    // Avoid layout jitter using a placeholder view.
                    let spacerView = UIView.spacer(withHeight: iconHeight)
                    stack.addArrangedSubview(spacerView)
                }

                return cell
            },
            actionBlock: nil)
        }

        section0.add(buildWordRow(wordIndex: wordIndex0,
                                  wordTextfield: wordTextfield0,
                                  isCorrect: isWordCorrect0))
        section1.add(buildWordRow(wordIndex: wordIndex1,
                                  wordTextfield: wordTextfield1,
                                  isCorrect: isWordCorrect1))
        contents.addSection(section0)
        contents.addSection(section1)

        warningLabel.text = " "
        warningLabel.font = .ows_dynamicTypeCaption1
        warningLabel.textColor = .ows_accentRed

        let warningStack = UIStackView(arrangedSubviews: [ warningLabel ])
        warningStack.axis = .vertical
        warningStack.alignment = .fill
        warningStack.isLayoutMarginsRelativeArrangement = true
        warningStack.layoutMargins = UIEdgeInsets(hMargin: (OWSTableViewController2.cellHOuterMargin +
                                                                OWSTableViewController2.cellHInnerMargin),
                                              vMargin: 8)
        section1.customFooterView = warningStack

        self.contents = contents
    }

    private func buildConfirmHeader() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_TITLE",
                                            comment: "Title for the 'confirm words' step of the 'view payments passphrase' views.")
        titleLabel.font = UIFont.ows_dynamicTypeTitle2Clamped.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center

        let explanationLabel = UILabel()
        explanationLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_EXPLANATION",
                                                  comment: "Explanation of the 'confirm payments passphrase word' step in the 'view payments passphrase' settings.")
        explanationLabel.font = .ows_dynamicTypeBody2Clamped
        explanationLabel.textColor = Theme.secondaryTextAndIconColor
        explanationLabel.textAlignment = .center
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping

        let topStack = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 10),
            explanationLabel
        ])
        topStack.axis = .vertical
        topStack.alignment = .center
        topStack.isLayoutMarginsRelativeArrangement = true
        let hMargin = 20 + OWSTableViewController2.cellHOuterMargin
        topStack.layoutMargins = UIEdgeInsets(top: 32, leading: hMargin, bottom: 40, trailing: hMargin)
        return topStack
    }

    // MARK: - Events

    @objc
    func didTapConfirmButton() {
        guard areAllWordsCorrect else {
            if areAnyWordsCorrect {
                warningLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_INVALID_WORD",
                                                      comment: "Error indicating that at least one word of the payments passphrase is not correct in the 'view payments passphrase' views.")
            } else {
                warningLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_INVALID_WORDS",
                                                      comment: "Error indicating that all words of the payments passphrase are not correct in the 'view payments passphrase' views.")
            }
            return
        }

        let viewPassphraseDelegate = self.viewPassphraseDelegate
        dismiss(animated: true, completion: {
            viewPassphraseDelegate?.viewPassphraseDidComplete()
        })
    }

    @objc
    func didTapSeePassphraseAgainButton() {
        navigationController?.popViewController(animated: true)
    }

    @objc
    private func textfieldDidChange() {
        updateCorrectness()
        // Clear any warning.
        warningLabel.text = " "
    }
}

// MARK: -

// TODO:
extension PaymentsViewPassphraseConfirmViewController: UITextFieldDelegate {
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return true
    }
}
