//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PaymentsRestoreWalletCompleteViewController: OWSViewController {

    private let passphrase: PaymentsPassphrase

    private weak var restoreWalletDelegate: PaymentsRestoreWalletDelegate?

    init(
        restoreWalletDelegate: PaymentsRestoreWalletDelegate,
        passphrase: PaymentsPassphrase,
    ) {
        self.passphrase = passphrase
        self.restoreWalletDelegate = restoreWalletDelegate

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_COMPLETE_TITLE",
            comment: "Title for the 'review payments passphrase' step of the 'restore payments wallet' views.",
        )

        view.backgroundColor = .Signal.groupedBackground

        let explanationLabel = UILabel.explanationTextLabel(text: OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_COMPLETE_EXPLANATION",
            comment: "Explanation of the 'review payments passphrase' step of the 'restore payments wallet' views.",
        ))

        let passphraseGrid = PaymentsUI.buildPassphraseGrid(passphrase: passphrase)
        let passphraseGridContainer = UIView()
        passphraseGridContainer.directionalLayoutMargins = .init(margin: 24)
        passphraseGridContainer.backgroundColor = .Signal.secondaryGroupedBackground
        if #available(iOS 26, *) {
            passphraseGridContainer.cornerConfiguration = .uniformCorners(radius: 26)
        } else {
            passphraseGridContainer.layer.cornerRadius = 10
        }
        passphraseGridContainer.addSubview(passphraseGrid)
        passphraseGrid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            passphraseGrid.topAnchor.constraint(equalTo: passphraseGridContainer.layoutMarginsGuide.topAnchor),
            passphraseGrid.leadingAnchor.constraint(equalTo: passphraseGridContainer.layoutMarginsGuide.leadingAnchor),
            passphraseGrid.trailingAnchor.constraint(equalTo: passphraseGridContainer.layoutMarginsGuide.trailingAnchor),
            passphraseGrid.bottomAnchor.constraint(equalTo: passphraseGridContainer.layoutMarginsGuide.bottomAnchor),
        ])

        let doneButton = UIButton(
            configuration: .largePrimary(title: CommonStrings.doneButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapDoneButton()
            },
        )
        let editButton = UIButton(
            configuration: .largeSecondary(title: CommonStrings.editButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapEditButton()
            },
        )

        let stackView = addStaticContentStackView(
            arrangedSubviews: [
                .spacer(withHeight: 16),
                explanationLabel,
                passphraseGridContainer,
                .vStretchingSpacer(),
                [doneButton, editButton].enclosedInVerticalStackView(isFullWidthButtons: true),
            ],
            isScrollable: true,
        )
        stackView.setCustomSpacing(24, after: explanationLabel)
    }

    private func showInvalidPassphraseAlert() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_RESTORE_WALLET_INVALID_PASSPHRASE_TITLE",
                comment: "Title for the 'invalid payments wallet passphrase' error alert in the app payments settings.",
            ),
            message: OWSLocalizedString(
                "SETTINGS_PAYMENTS_RESTORE_WALLET_INVALID_PASSPHRASE_MESSAGE",
                comment: "Message for the 'invalid payments wallet passphrase' error alert in the app payments settings.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.okayButton,
            style: .default,
        ) { [weak self] _ in
            self?.returnToFirstWordView(shouldClearInput: true)
        })

        presentActionSheet(actionSheet)
    }

    private func showRestoreFailureAlert() {
        OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_FAILED",
            comment: "Error indicating that 'restore payments wallet failed' in the app payments settings.",
        ))
    }

    // MARK: - Events

    private func didTapDoneButton() {
        guard SUIEnvironment.shared.paymentsRef.paymentsEntropy == nil else {
            owsFailDebug("paymentsEntropy already set.")
            dismiss(animated: true, completion: nil)
            showRestoreFailureAlert()
            return
        }
        guard let paymentsEntropy = SUIEnvironment.shared.paymentsSwiftRef.paymentsEntropy(forPassphrase: passphrase) else {
            showInvalidPassphraseAlert()
            return
        }
        let didSucceed = SSKEnvironment.shared.databaseStorageRef.write { transaction in
            SSKEnvironment.shared.paymentsHelperRef.enablePayments(
                withPaymentsEntropy: paymentsEntropy,
                transaction: transaction,
            )
        }
        guard didSucceed else {
            owsFailDebug("Could not restore payments entropy.")
            dismiss(animated: true, completion: nil)
            showRestoreFailureAlert()
            return
        }

        let restoreWalletDelegate = self.restoreWalletDelegate
        dismiss(animated: true, completion: {
            restoreWalletDelegate?.restoreWalletDidComplete()
        })
    }

    private func didTapEditButton() {
        returnToFirstWordView(shouldClearInput: false)
    }

    private func returnToFirstWordView(shouldClearInput: Bool) {
        guard let navigationController else {
            return
        }

        // We want to pop back to the _first_ of the "enter wallet passphrase" views.
        for viewController in navigationController.viewControllers {
            if let viewController = viewController as? PaymentsRestoreWalletPasteboardViewController {
                navigationController.popToViewController(viewController, animated: true)
                return
            }

            guard let viewController = viewController as? PaymentsRestoreWalletWordViewController else {
                continue
            }
            if shouldClearInput {
                viewController.clearInput()
            }
            navigationController.popToViewController(viewController, animated: true)
            return
        }
        owsFailDebug("Could not return to start of passphrase.")
    }
}
