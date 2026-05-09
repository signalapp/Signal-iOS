//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class GroupLinkQRCodeViewController: OWSViewController {

    private let groupModelV2: TSGroupModelV2

    private lazy var shareCodeButton = UIButton(
        configuration: .largePrimary(title: OWSLocalizedString(
            "GROUP_LINK_QR_CODE_VIEW_SHARE_CODE_BUTTON",
            comment: "Label for the 'share code' button in the 'group link QR code' view.",
        )),
        primaryAction: UIAction { [weak self] _ in
            self?.didTapShareCode()
        },
    )

    init(groupModelV2: TSGroupModelV2) {
        self.groupModelV2 = groupModelV2

        super.init()
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "GROUP_LINK_QR_CODE_VIEW_TITLE",
            comment: "The title for the 'group link QR code' view.",
        )
        view.backgroundColor = .Signal.groupedBackground

        let qrCodeView = QRCodeView()
        do {
            let inviteLinkUrl = try groupModelV2.groupInviteLinkUrl()
            qrCodeView.setQRCode(url: inviteLinkUrl)
        } catch {
            owsFailDebug("error \(error)")
        }
        let qrCodeViewContainer = UIView.container()
        qrCodeViewContainer.addSubview(qrCodeView)
        qrCodeView.translatesAutoresizingMaskIntoConstraints = false
        // Allow container to grow in width, keeping QRCode view square,
        // centered horizontally and pinned to top and bottom edges.
        NSLayoutConstraint.activate([
            qrCodeView.widthAnchor.constraint(equalTo: qrCodeView.heightAnchor),

            qrCodeView.topAnchor.constraint(equalTo: qrCodeViewContainer.topAnchor),
            qrCodeView.bottomAnchor.constraint(equalTo: qrCodeViewContainer.bottomAnchor),

            qrCodeView.leadingAnchor.constraint(greaterThanOrEqualTo: qrCodeViewContainer.leadingAnchor),
            qrCodeView.centerXAnchor.constraint(equalTo: qrCodeViewContainer.centerXAnchor),
        ])

        let descriptionLabel = UILabel()
        descriptionLabel.text = OWSLocalizedString(
            "GROUP_LINK_QR_CODE_VIEW_DESCRIPTION",
            comment: "Description text in the 'group link QR code' view.",
        )
        descriptionLabel.textColor = .Signal.secondaryLabel
        descriptionLabel.font = .dynamicTypeFootnote
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.setContentHuggingVerticalHigh()

        let spacer1 = UIView.transparentSpacer()
        let spacer2 = UIView.transparentSpacer()
        let stackView = addStaticContentStackView(arrangedSubviews: [
            spacer1,
            qrCodeViewContainer,
            descriptionLabel,
            spacer2,
            shareCodeButton.enclosedInVerticalStackView(isFullWidthButton: true),
        ])
        stackView.axis = .vertical
        stackView.setCustomSpacing(20, after: qrCodeViewContainer)

        NSLayoutConstraint.activate([
            spacer1.heightAnchor.constraint(equalTo: spacer2.heightAnchor),
        ])
    }

    private func didTapShareCode() {
        do {
            guard
                let qrCodeImage = QRCodeGenerator().generateQRCode(
                    url: try groupModelV2.groupInviteLinkUrl(),
                )
            else {
                owsFailDebug("Failed to generate QR code image!")
                return
            }

            let coloredQRCodeImage = qrCodeImage.tintedImage(
                color: QRCodeColor.blue.foreground,
            )

            guard let imageData = coloredQRCodeImage.pngData() else {
                owsFailDebug("Could not encode QR code.")
                return
            }

            let fileUrl = OWSFileSystem.temporaryFileUrl(
                fileExtension: "png",
                isAvailableWhileDeviceLocked: false,
            )
            try imageData.write(to: fileUrl)

            AttachmentSharing.showShareUI(for: fileUrl, sender: shareCodeButton)
        } catch {
            owsFailDebug("error \(error)")
        }
    }
}
