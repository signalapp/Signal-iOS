//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class PaymentsTransferInViewController: OWSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_PAYMENTS_ADD_MONEY",
            comment: "Label for 'add money' view in the payment settings.",
        )

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: Theme.iconImage(.buttonShare),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapShare()
            },
        )
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            self?.didTapDone()
        }

        view.backgroundColor = .Signal.groupedBackground

        let contentView: UIView
        if let walletAddressView = buildWalletAddressView() {
            contentView = walletAddressView
        } else {
            let errorLabel = UILabel.explanationTextLabel(text: OWSLocalizedString(
                "SETTINGS_PAYMENTS_INVALID_WALLET_ADDRESS",
                comment: "Indicator that the payments wallet address is invalid.",
            ))
            errorLabel.textColor = .Signal.label
            errorLabel.font = .dynamicTypeSubheadlineClamped.semibold()
            errorLabel.adjustsFontSizeToFitWidth = true
            errorLabel.numberOfLines = 0
            errorLabel.lineBreakMode = .byWordWrapping
            contentView = errorLabel
        }

        let contentViewContainer = UIView()
        contentViewContainer.directionalLayoutMargins = .init(hMargin: 16, vMargin: 24)
        contentViewContainer.backgroundColor = .Signal.secondaryGroupedBackground
        if #available(iOS 26, *) {
            contentViewContainer.cornerConfiguration = .uniformCorners(radius: .fixed(26))
        } else {
            contentViewContainer.layer.cornerRadius = 14
        }
        contentViewContainer.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: contentViewContainer.layoutMarginsGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentViewContainer.layoutMarginsGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentViewContainer.layoutMarginsGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentViewContainer.layoutMarginsGuide.bottomAnchor),
        ])

        let infoLabel = PaymentsUI.buildTextWithLearnMoreLinkTextView(
            text: OWSLocalizedString(
                "SETTINGS_PAYMENTS_ADD_MONEY_DESCRIPTION",
                comment: "Explanation of the process for adding money in the 'add money' settings view.",
            ),
            font: .dynamicTypeSubheadlineClamped,
            learnMoreUrl: URL.Support.Payments.transferFromExchange,
        )

        addStaticContentStackView(
            arrangedSubviews: [
                .spacer(withHeight: 16),
                contentViewContainer,
                infoLabel,
                .vStretchingSpacer(),
            ],
            isScrollable: true,
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // We may have just transferred in; update the balance.
        SUIEnvironment.shared.paymentsSwiftRef.updateCurrentPaymentBalance()
    }

    private func buildWalletAddressView() -> UIView? {
        guard let walletAddressBase58 = SUIEnvironment.shared.paymentsRef.walletAddressBase58() else {
            return nil
        }
        let walletAddressBase58Data = Data(walletAddressBase58.utf8)

        guard
            let qrImage = QRCodeGenerator().generateUnstyledQRCode(
                data: walletAddressBase58Data,
            )
        else {
            owsFailDebug("Failed to generate QR code image!")
            return nil
        }

        let qrCodeView = UIImageView(image: qrImage)
        // Don't antialias QR Codes.
        qrCodeView.layer.magnificationFilter = .nearest
        qrCodeView.layer.minificationFilter = .nearest

        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString(
            "SETTINGS_PAYMENTS_WALLET_ADDRESS_LABEL",
            comment: "Label for the payments wallet address.",
        )
        titleLabel.textColor = .Signal.label
        titleLabel.font = .dynamicTypeSubheadlineClamped.semibold()
        titleLabel.textAlignment = .center

        let walletAddressLabel = UILabel()
        walletAddressLabel.text = walletAddressBase58
        walletAddressLabel.textColor = .Signal.secondaryLabel
        walletAddressLabel.font = .monospacedDigitFont(ofSize: UIFont.dynamicTypeSubheadlineClamped.pointSize)
        walletAddressLabel.lineBreakMode = .byTruncatingMiddle
        walletAddressLabel.textAlignment = .center

        let copyButton = UIButton(
            configuration: .smallSecondary(title: CommonStrings.copyButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapCopyAddress()
            },
        )

        let qrCodeContainer = UIView.container()
        qrCodeContainer.addSubview(qrCodeView)
        qrCodeView.translatesAutoresizingMaskIntoConstraints = false
        let qrCodeSize = view.bounds.size.smallerAxis * 0.5
        NSLayoutConstraint.activate([
            qrCodeView.topAnchor.constraint(equalTo: qrCodeContainer.topAnchor),
            qrCodeView.heightAnchor.constraint(equalTo: qrCodeView.widthAnchor),
            qrCodeView.leadingAnchor.constraint(greaterThanOrEqualTo: qrCodeContainer.leadingAnchor),
            qrCodeView.widthAnchor.constraint(equalToConstant: qrCodeSize),
            qrCodeView.centerXAnchor.constraint(equalTo: qrCodeContainer.centerXAnchor),
            qrCodeView.bottomAnchor.constraint(equalTo: qrCodeContainer.bottomAnchor),
        ])

        let stackView = UIStackView(arrangedSubviews: [qrCodeContainer, titleLabel, walletAddressLabel, copyButton])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 20
        stackView.setCustomSpacing(8, after: titleLabel)
        return stackView
    }

    // MARK: - Events

    private func didTapCopyAddress() {
        guard let walletAddressBase58 = SUIEnvironment.shared.paymentsRef.walletAddressBase58() else {
            owsFailDebug("Missing walletAddressBase58.")
            return
        }
        UIPasteboard.general.string = walletAddressBase58

        presentToast(
            text: OWSLocalizedString(
                "SETTINGS_PAYMENTS_ADD_MONEY_WALLET_ADDRESS_COPIED",
                comment: "Indicator that the payments wallet address has been copied to the pasteboard.",
            ),
            image: .copy,
        )
    }

    private func didTapDone() {
        dismiss(animated: true, completion: nil)
    }

    private func didTapShare() {
        guard let walletAddressBase58 = SUIEnvironment.shared.paymentsRef.walletAddressBase58() else {
            owsFailDebug("Missing walletAddressBase58.")
            return
        }
        AttachmentSharing.showShareUI(for: walletAddressBase58, sender: self)
    }
}
