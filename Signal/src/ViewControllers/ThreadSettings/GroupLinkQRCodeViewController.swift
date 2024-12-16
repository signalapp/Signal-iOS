//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import SignalServiceKit
public import SignalUI

public class GroupLinkQRCodeViewController: OWSViewController {

    private var groupModelV2: TSGroupModelV2

    init(groupModelV2: TSGroupModelV2) {
        self.groupModelV2 = groupModelV2

        super.init()
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("GROUP_LINK_QR_CODE_VIEW_TITLE",
                                  comment: "The title for the 'group link QR code' view.")
        view.backgroundColor = Theme.backgroundColor

        createContents()
    }

    // MARK: -

    private func createContents() {

        let qrCodeView = QRCodeView()
        qrCodeView.autoPinToSquareAspectRatio()

        do {
            let inviteLinkUrl = try groupModelV2.groupInviteLinkUrl()

            qrCodeView.setQRCode(url: inviteLinkUrl)
        } catch {
            owsFailDebug("error \(error)")
        }

        let descriptionLabel = UILabel()
        descriptionLabel.text = OWSLocalizedString("GROUP_LINK_QR_CODE_VIEW_DESCRIPTION",
                                                  comment: "Description text in the 'group link QR code' view.")
        descriptionLabel.textColor = Theme.secondaryTextAndIconColor
        descriptionLabel.font = .dynamicTypeFootnote
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping

        let shareCodeButton = OWSFlatButton.button(title: OWSLocalizedString("GROUP_LINK_QR_CODE_VIEW_SHARE_CODE_BUTTON",
                                                                            comment: "Label for the 'share code' button in the 'group link QR code' view."),
                                                   font: UIFont.dynamicTypeBody.semibold(),
                                                   titleColor: .white,
                                                   backgroundColor: .ows_accentBlue,
                                                   target: self,
                                                   selector: #selector(didTapShareCode))
        shareCodeButton.autoSetHeightUsingFont()

        let vSpacer1 = UIView.vStretchingSpacer()
        let vSpacer2 = UIView.vStretchingSpacer()
        let stackView = UIStackView(arrangedSubviews: [
            vSpacer1,
            qrCodeView,
            UIView.spacer(withHeight: 24),
            descriptionLabel,
            vSpacer2,
            shareCodeButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperviewMargins()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        stackView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        vSpacer1.autoPinHeight(toHeightOf: vSpacer2)
    }

    @objc
    private func didTapShareCode(_ sender: UIButton) {
        do {
            guard let qrCodeImage = QRCodeGenerator().generateQRCode(
                url: try groupModelV2.groupInviteLinkUrl()
            ) else {
                owsFailDebug("Failed to generate QR code image!")
                return
            }

            let coloredQRCodeImage = qrCodeImage.tintedImage(
                color: QRCodeColor.blue.foreground
            )

            guard let imageData = coloredQRCodeImage.pngData() else {
                owsFailDebug("Could not encode QR code.")
                return
            }

            let fileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: "png")
            try imageData.write(to: fileUrl)

            AttachmentSharing.showShareUI(for: fileUrl, sender: sender)
        } catch {
            owsFailDebug("error \(error)")
        }
    }
}
