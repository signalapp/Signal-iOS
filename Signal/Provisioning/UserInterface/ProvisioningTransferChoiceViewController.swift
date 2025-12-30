//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class ProvisioningTransferChoiceViewController: ProvisioningBaseViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.hidesBackButton = true

        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "DEVICE_TRANSFER_CHOICE_TITLE",
            comment: "The title for the device transfer 'choice' view",
        ))

        let explanationLabel = UILabel.explanationLabelForRegistration(text: OWSLocalizedString(
            "DEVICE_TRANSFER_CHOICE_LINKED_EXPLANATION",
            comment: "The explanation for the device transfer 'choice' view when linking a device",
        ))

        let transferButton = UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "DEVICE_TRANSFER_CHOICE_TRANSFER_LINKED_TITLE",
                comment: "The title for the device transfer 'choice' view 'transfer' option when linking a device",
            ),
            subtitle: OWSLocalizedString(
                "DEVICE_TRANSFER_CHOICE_TRANSFER_LINKED_BODY",
                comment: "The body for the device transfer 'choice' view 'transfer' option when linking a device",
            ),
            iconName: Theme.iconName(.transfer),
            primaryAction: UIAction { [weak self] _ in
                self?.didSelectTransfer()
            },
        )

        let registerButton = UIButton.registrationChoiceButton(
            title: OWSLocalizedString(
                "DEVICE_TRANSFER_CHOICE_REGISTER_LINKED_TITLE",
                comment: "The title for the device transfer 'choice' view 'register' option when linking a device",
            ),
            subtitle: OWSLocalizedString(
                "DEVICE_TRANSFER_CHOICE_REGISTER_LINKED_BODY_LINK_AND_SYNC",
                value: "You’ll have the option to transfer messages and recent media from your phone",
                comment: "The body for the device transfer 'choice' view 'register' option when linking a device when message syncing is available",
            ),
            iconName: Theme.iconName(.register),
            primaryAction: UIAction { [weak self] _ in
                self?.didSelectRegister()
            },
        )

        let footerTextView = LinkingTextView()
        footerTextView.attributedText = NSAttributedString.composed(of: [
            SignalSymbol.lock.attributedString(for: .title3),
            "\n",
            "\n".styled(with: .maximumLineHeight(6)),
            OWSLocalizedString(
                "LINKING_SYNCING_FOOTER",
                comment: "Footer text when loading messages during linking process.",
            ),
            " ",
            CommonStrings.learnMore.styled(with: .link(URL.Support.linkedDevices)),
        ])
        .styled(
            with: .font(.dynamicTypeFootnote),
            .color(.Signal.secondaryLabel),
            .alignment(.center),
        )

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let stackView = addStaticContentStackView(arrangedSubviews: [
            topSpacer,
            titleLabel,
            explanationLabel,
            registerButton,
            transferButton,
            bottomSpacer,
            footerTextView,
            .spacer(withHeight: 32),
        ])
        stackView.setCustomSpacing(24, after: explanationLabel)

        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor, multiplier: 0.5).isActive = true
    }

    // MARK: - Events

    private func didSelectTransfer() {
        Logger.info("")

        let prepViewController = ProvisioningPrepViewController(provisioningController: provisioningController, isTransferring: true)
        navigationController?.pushViewController(prepViewController, animated: true)
    }

    private func didSelectRegister() {
        Logger.info("")

        let prepViewController = ProvisioningPrepViewController(provisioningController: provisioningController, isTransferring: false)
        navigationController?.pushViewController(prepViewController, animated: true)
    }
}

#if DEBUG
@available(iOS 17, *)
#Preview {
    ProvisioningTransferChoiceViewController(provisioningController: .preview())
}
#endif
