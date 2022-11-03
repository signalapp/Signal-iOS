//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

@objc
public class PaymentsRestoreWalletPasteboardViewController: OWSViewController {

    private weak var restoreWalletDelegate: PaymentsRestoreWalletDelegate?

    private let textField = UITextField()

    private var passphraseText: String? {
        textField.text?.strippedOrNil?.lowercased()
    }

    public required init(restoreWalletDelegate: PaymentsRestoreWalletDelegate) {
        self.restoreWalletDelegate = restoreWalletDelegate

        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_PASTE_TITLE",
                                  comment: "Title for the 'restore payments wallet from pasteboard' view of the app settings.")

        OWSTableViewController2.removeBackButtonText(viewController: self)

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                           target: self,
                                                           action: #selector(didTapDismiss),
                                                           accessibilityIdentifier: "dismiss")
        createContents()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        textField.becomeFirstResponder()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        textField.becomeFirstResponder()
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
        rootView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        rootView.autoPinWidthToSuperviewMargins()

        updateContents()
    }

    private func updateContents() {

        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)

        textField.textColor = Theme.primaryTextColor
        textField.font = .ows_dynamicTypeBodyClamped
        textField.keyboardAppearance = Theme.keyboardAppearance
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.returnKeyType = .done
        textField.accessibilityIdentifier = "payments.passphrase.restore-paste"
        textField.delegate = self

        textField.placeholder = NSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_PASTE_PLACEHOLDER",
                                                  comment: "Format for the placeholder text in the 'restore payments wallet from pasteboard' view of the app settings.")

        let textfieldStack = UIStackView(arrangedSubviews: [ textField ])
        textfieldStack.axis = .vertical
        textfieldStack.alignment = .fill
        textfieldStack.isLayoutMarginsRelativeArrangement = true
        textfieldStack.layoutMargins = UIEdgeInsets(hMargin: OWSTableViewController2.cellHInnerMargin,
                                                    vMargin: OWSTableViewController2.cellVInnerMargin)
        textfieldStack.addBackgroundView(withBackgroundColor: Theme.backgroundColor, cornerRadius: 10)

        let nextButton = OWSFlatButton.button(title: CommonStrings.nextButton,
                                              font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                              titleColor: .white,
                                              backgroundColor: .ows_accentBlue,
                                              target: self,
                                              selector: #selector(didTapNextButton))
        nextButton.autoSetHeightUsingFont()

        rootView.removeAllSubviews()
        rootView.addArrangedSubviews([
            UIView.spacer(withHeight: 16),
            textfieldStack,
            UIView.vStretchingSpacer(),
            nextButton,
            UIView.spacer(withHeight: 8)
        ])
    }

    // MARK: - Events

    @objc
    func didTapDismiss() {
        navigationController?.popViewController(animated: true)
    }

    @objc
    func didTapNextButton() {
        tryToRestoreFromPassphrase()
    }

    @objc
    func tryToRestoreFromPassphrase() {
        guard let restoreWalletDelegate = restoreWalletDelegate else {
            owsFailDebug("Missing restoreWalletDelegate.")
            dismiss(animated: true, completion: nil)
            return
        }
        func tryToParsePassphrase() -> PaymentsPassphrase? {
            guard let passphraseText = self.passphraseText else {
                return nil
            }
            do {
                return try PaymentsPassphrase.parse(passphrase: passphraseText,
                                                    validateWords: true)
            } catch {
                Logger.warn("Error: \(error)")
                return nil
            }
        }
        guard let passphrase = tryToParsePassphrase() else {
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_INVALID_PASSPHRASE",
                                                                      comment: "Error indicating that the user has entered an invalid payments passphrase in the 'restore payments wallet' views."))
            return
        }
        let view = PaymentsRestoreWalletCompleteViewController(restoreWalletDelegate: restoreWalletDelegate,
                                                               passphrase: passphrase)
        navigationController?.pushViewController(view, animated: true)
    }
}

// MARK: -

extension PaymentsRestoreWalletPasteboardViewController: UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        tryToRestoreFromPassphrase()
        return false
    }
}
