//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PaymentsRestoreWalletPasteboardViewController: OWSViewController, UITextFieldDelegate {

    private weak var restoreWalletDelegate: PaymentsRestoreWalletDelegate?

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
        textField.placeholder = OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_PASTE_PLACEHOLDER",
            comment: "Format for the placeholder text in the 'restore payments wallet from pasteboard' view of the app settings.",
        )
        return textField
    }()

    private var passphraseText: String? {
        textField.text?.strippedOrNil?.lowercased()
    }

    init(restoreWalletDelegate: PaymentsRestoreWalletDelegate) {
        self.restoreWalletDelegate = restoreWalletDelegate

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_PASTE_TITLE",
            comment: "Title for the 'restore payments wallet from pasteboard' view of the app settings.",
        )

        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.didTapDismiss()
        }

        view.backgroundColor = .Signal.groupedBackground

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
                self?.tryToRestoreFromPassphrase()
            },
        )

        addStaticContentStackView(
            arrangedSubviews: [
                .spacer(withHeight: 16),
                textFieldContainer,
                .vStretchingSpacer(),
                nextButton,
                .spacer(withHeight: 16),
            ],
            shouldAvoidKeyboard: true,
        )
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

    private func didTapDismiss() {
        navigationController?.popViewController(animated: true)
    }

    private func tryToRestoreFromPassphrase() {
        guard let restoreWalletDelegate else {
            owsFailDebug("Missing restoreWalletDelegate.")
            dismiss(animated: true, completion: nil)
            return
        }
        func tryToParsePassphrase() -> PaymentsPassphrase? {
            guard let passphraseText else {
                return nil
            }
            do {
                return try PaymentsPassphrase.parse(
                    passphrase: passphraseText,
                    validateWords: true,
                )
            } catch {
                Logger.warn("Error: \(error)")
                return nil
            }
        }
        guard let passphrase = tryToParsePassphrase() else {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_RESTORE_WALLET_WORD_INVALID_PASSPHRASE",
                comment: "Error indicating that the user has entered an invalid payments passphrase in the 'restore payments wallet' views.",
            ))
            return
        }
        let view = PaymentsRestoreWalletCompleteViewController(
            restoreWalletDelegate: restoreWalletDelegate,
            passphrase: passphrase,
        )
        navigationController?.pushViewController(view, animated: true)
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        tryToRestoreFromPassphrase()
        return false
    }
}
