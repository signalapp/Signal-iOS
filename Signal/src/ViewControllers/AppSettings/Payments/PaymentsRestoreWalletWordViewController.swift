//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

@objc
public class PaymentsRestoreWalletWordViewController: OWSViewController {

    private weak var restoreWalletDelegate: PaymentsRestoreWalletDelegate?

    private let partialPassphrase: PartialPaymentsPassphrase

    private let wordIndex: Int

    private let textfield = UITextField()

    private var wordText: String? {
        textfield.text?.strippedOrNil?.lowercased()
    }
    private var hasValidWord: Bool {
        isValidWord(wordText)
    }
    private func isValidWord(_ wordText: String?) -> Bool {
        guard let wordText = wordText,
              !wordText.isEmpty else {
            return false
        }
        return Self.paymentsSwift.isValidPassphraseWord(wordText)
    }

    private let warningLabel = UILabel()

    public required init(restoreWalletDelegate: PaymentsRestoreWalletDelegate,
                         partialPassphrase: PartialPaymentsPassphrase,
                         wordIndex: Int) {
        self.restoreWalletDelegate = restoreWalletDelegate
        self.partialPassphrase = partialPassphrase
        self.wordIndex = wordIndex

        super.init()

        textfield.text = partialPassphrase.getWord(atIndex: wordIndex)
    }

    public func clearInput() {
        partialPassphrase.reset()
        textfield.text = nil
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_TITLE",
                                  comment: "Title for the 'restore payments wallet' view of the app settings.")

        OWSTableViewController2.removeBackButtonText(viewController: self)

        createContents()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        textfield.becomeFirstResponder()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        textfield.becomeFirstResponder()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        updateContents()
    }

    private let rootView = UIStackView()

    private func createContents() {
        rootView.axis = .vertical
        rootView.alignment = .fill
        view.addSubview(rootView)
        rootView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        rootView.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideViewSafeArea)
        rootView.autoPinWidthToSuperviewMargins()

        updateContents()
    }

    private func updateContents() {

        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)

        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_TITLE",
                                            comment: "Title for the 'enter word' step of the 'restore payments wallet' views.")
        titleLabel.font = UIFont.dynamicTypeTitle2Clamped.semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center

        let instructionsFormat = OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_INSTRUCTIONS_FORMAT",
                                                   comment: "Format for the instructions for the 'enter word' step of the 'restore payments wallet' views. Embeds {{ the index of the current word }}.")
        let instructions = String(format: instructionsFormat, OWSFormat.formatInt(wordIndex + 1))

        let instructionsLabel = UILabel()
        instructionsLabel.text = instructions
        instructionsLabel.textAlignment = .center
        instructionsLabel.numberOfLines = 0
        instructionsLabel.lineBreakMode = .byWordWrapping

        let topStack = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 10),
            instructionsLabel
        ])
        topStack.axis = .vertical
        topStack.alignment = .center
        topStack.isLayoutMarginsRelativeArrangement = true
        topStack.layoutMargins = UIEdgeInsets(hMargin: 20, vMargin: 0)

        textfield.textColor = Theme.primaryTextColor
        textfield.font = .dynamicTypeBodyClamped
        textfield.keyboardAppearance = Theme.keyboardAppearance
        textfield.autocapitalizationType = .none
        textfield.autocorrectionType = .no
        textfield.spellCheckingType = .no
        textfield.smartQuotesType = .no
        textfield.smartDashesType = .no
        textfield.returnKeyType = .done
        textfield.accessibilityIdentifier = "payments.passphrase.restore.\(wordIndex)"
        textfield.addTarget(self, action: #selector(textfieldDidChange), for: .editingChanged)
        textfield.delegate = self

        let placeholderFormat = OWSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_CONFIRM_PLACEHOLDER_FORMAT",
                                                  comment: "Format for the placeholder text in the 'confirm payments passphrase' view of the app settings. Embeds: {{ the index of the word }}.")
        let placeholder = NSAttributedString(string: String(format: placeholderFormat,
                                                            OWSFormat.formatInt(wordIndex + 1)),
                                             attributes: [
                                                .foregroundColor: Theme.secondaryTextAndIconColor
                                             ])
        textfield.attributedPlaceholder = placeholder

        let textfieldStack = UIStackView(arrangedSubviews: [ textfield ])
        textfieldStack.axis = .vertical
        textfieldStack.alignment = .fill
        textfieldStack.isLayoutMarginsRelativeArrangement = true
        textfieldStack.layoutMargins = UIEdgeInsets(hMargin: OWSTableViewController2.cellHInnerMargin,
                                                    vMargin: OWSTableViewController2.cellVInnerMargin)
        let backgroundColor = OWSTableViewController2.cellBackgroundColor(isUsingPresentedStyle: true)
        textfieldStack.addBackgroundView(withBackgroundColor: backgroundColor,
                                         cornerRadius: 10)

        warningLabel.text = " "
        warningLabel.font = .dynamicTypeCaption1
        warningLabel.textColor = .ows_accentRed

        let warningStack = UIStackView(arrangedSubviews: [ warningLabel ])
        warningStack.axis = .vertical
        warningStack.alignment = .fill
        warningStack.isLayoutMarginsRelativeArrangement = true
        warningStack.layoutMargins = UIEdgeInsets(hMargin: OWSTableViewController2.cellHInnerMargin,
                                                  vMargin: 0)

        let nextButton = OWSFlatButton.button(title: CommonStrings.nextButton,
                                              font: UIFont.dynamicTypeBody.semibold(),
                                              titleColor: .white,
                                              backgroundColor: .ows_accentBlue,
                                              target: self,
                                              selector: #selector(didTapNextButton))
        nextButton.autoSetHeightUsingFont()

        rootView.removeAllSubviews()
        rootView.addArrangedSubviews([
            UIView.spacer(withHeight: 20),
            topStack,
            UIView.spacer(withHeight: 60),
            textfieldStack,
            UIView.spacer(withHeight: 8),
            warningStack,
            UIView.vStretchingSpacer(),
            nextButton,
            UIView.spacer(withHeight: 8)
        ])
   }

    // MARK: - Events

    @objc
    func didTapNextButton() {
        guard let restoreWalletDelegate = restoreWalletDelegate else {
            owsFailDebug("Missing restoreWalletDelegate.")
            dismiss(animated: true, completion: nil)
            return
        }
        guard let wordText = self.wordText,
              isValidWord(wordText) else {
            warningLabel.text = OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_INVALID_WORD",
                                                  comment: "Error indicating that the user has entered an invalid word in the 'enter word' step of the 'restore payments wallet' views.")
            return
        }
        partialPassphrase.set(word: wordText, index: wordIndex)
        if partialPassphrase.isComplete {
            guard let paymentsPassphrase = partialPassphrase.asPaymentsPassphrase() else {
                OWSActionSheets.showErrorAlert(message: OWSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_INVALID_PASSPHRASE",
                                                                          comment: "Error indicating that the user has entered an invalid payments passphrase in the 'restore payments wallet' views."))
                return
            }
            let view = PaymentsRestoreWalletCompleteViewController(restoreWalletDelegate: restoreWalletDelegate,
                                                                   passphrase: paymentsPassphrase)
            navigationController?.pushViewController(view, animated: true)
        } else {
            let view = PaymentsRestoreWalletWordViewController(restoreWalletDelegate: restoreWalletDelegate,
                                                               partialPassphrase: partialPassphrase,
                                                               wordIndex: wordIndex + 1)
            navigationController?.pushViewController(view, animated: true)
        }
    }

    @objc
    private func textfieldDidChange() {
        // Clear any warning.
        warningLabel.text = " "
    }
}

// MARK: -

public class PartialPaymentsPassphrase {

    private var wordMap = [Int: String]()

    public var isComplete: Bool {
        wordMap.count == PaymentsConstants.passphraseWordCount
    }

    public init() {}

    public static var empty: PartialPaymentsPassphrase { PartialPaymentsPassphrase() }

    public func set(word: String, index: Int) {
        let word = word.stripped
        guard !word.isEmpty else {
            owsFailDebug("Invalid word.")
            return
        }
        wordMap[index] = word
    }

    public func getWord(atIndex index: Int) -> String? {
        wordMap[index]
    }

    public func asPaymentsPassphrase() -> PaymentsPassphrase? {
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

    public func reset() {
        wordMap.removeAll()
    }
}

// MARK: -

extension PaymentsRestoreWalletWordViewController: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        didTapNextButton()
        return false
    }
}
