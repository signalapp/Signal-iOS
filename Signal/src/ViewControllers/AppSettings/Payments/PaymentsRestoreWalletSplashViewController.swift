//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

@MainActor
protocol PaymentsRestoreWalletDelegate: AnyObject {
    func restoreWalletDidComplete()
}

class PaymentsRestoreWalletSplashViewController: OWSViewController {

    private weak var restoreWalletDelegate: PaymentsRestoreWalletDelegate?

    init(restoreWalletDelegate: PaymentsRestoreWalletDelegate) {
        self.restoreWalletDelegate = restoreWalletDelegate

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_TITLE",
            comment: "Title for the 'restore payments wallet' view of the app settings.",
        )

        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            self?.didTapDismiss()
        }

        view.backgroundColor = .Signal.groupedBackground

        let heroImage = UIImageView(image: UIImage(named: "recovery-phrase"))
        let heroImageContainer = UIView.container()
        heroImageContainer.addSubview(heroImage)
        heroImage.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heroImage.topAnchor.constraint(equalTo: heroImageContainer.topAnchor, constant: 24),
            heroImage.centerYAnchor.constraint(equalTo: heroImageContainer.centerYAnchor),

            heroImage.leadingAnchor.constraint(greaterThanOrEqualTo: heroImageContainer.leadingAnchor),
            heroImage.centerXAnchor.constraint(equalTo: heroImageContainer.centerXAnchor),
        ])

        let titleLabel = UILabel.title1Label(text: OWSLocalizedString(
            "SETTINGS_PAYMENTS_RESTORE_WALLET_SPLASH_TITLE",
            comment: "Title for the first step of the 'restore payments wallet' views.",
        ))

        let explanationLabel = PaymentsUI.buildTextWithLearnMoreLinkTextView(
            text: OWSLocalizedString(
                "SETTINGS_PAYMENTS_RESTORE_WALLET_SPLASH_EXPLANATION",
                comment: "Explanation of the 'restore payments wallet' process payments settings.",
            ),
            font: .dynamicTypeSubheadlineClamped,
            learnMoreUrl: URL.Support.Payments.walletRestorePassphrase,
        )

        let pasteFromPasteboardButton = UIButton(
            configuration: .largeSecondary(title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_RESTORE_WALLET_PASTE_FROM_PASTEBOARD",
                comment: "Label for the 'restore passphrase from pasteboard' button in the 'restore payments wallet from passphrase' view.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapPasteFromPasteboardButton()
            },
        )

        let enterManuallyButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "SETTINGS_PAYMENTS_RESTORE_WALLET_ENTER_MANUALLY",
                comment: "Label for the 'enter passphrase manually' button in the 'restore payments wallet from passphrase' view.",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapEnterManuallyButton()
            },
        )

        addStaticContentStackView(arrangedSubviews: [
            heroImageContainer,
            titleLabel,
            explanationLabel,
            .vStretchingSpacer(),
            [pasteFromPasteboardButton, enterManuallyButton].enclosedInVerticalStackView(isFullWidthButtons: true),
        ])
    }

    // MARK: - Events

    private func didTapDismiss() {
        dismiss(animated: true, completion: nil)
    }

    private func didTapPasteFromPasteboardButton() {
        guard let restoreWalletDelegate else {
            owsFailDebug("Missing restoreWalletDelegate.")
            dismiss(animated: true, completion: nil)
            return
        }
        let view = PaymentsRestoreWalletPasteboardViewController(restoreWalletDelegate: restoreWalletDelegate)
        navigationController?.pushViewController(view, animated: true)
    }

    private func didTapEnterManuallyButton() {
        guard let restoreWalletDelegate else {
            owsFailDebug("Missing restoreWalletDelegate.")
            dismiss(animated: true, completion: nil)
            return
        }
        // Start by entering the first word of the partial passphrase.
        let view = PaymentsRestoreWalletWordViewController(
            restoreWalletDelegate: restoreWalletDelegate,
            partialPassphrase: PartialPaymentsPassphrase.empty,
            wordIndex: 0,
        )
        navigationController?.pushViewController(view, animated: true)
    }
}
