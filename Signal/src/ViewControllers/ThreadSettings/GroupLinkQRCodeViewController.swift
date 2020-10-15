//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class GroupLinkQRCodeViewController: OWSViewController {

    private var groupModelV2: TSGroupModelV2

    required init(groupModelV2: TSGroupModelV2) {
        self.groupModelV2 = groupModelV2

        super.init()
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("GROUP_LINK_QR_CODE_VIEW_TITLE",
                                  comment: "The title for the 'group link QR code' view.")
        view.backgroundColor = Theme.backgroundColor

        createContents()
    }

    // MARK: -

    private func createContents() {

        let qrCodeView = QRCodeView()

        do {
            let inviteLinkUrl = try GroupManager.groupInviteLink(forGroupModelV2: groupModelV2)
            try qrCodeView.setQR(url: inviteLinkUrl)
        } catch {
            owsFailDebug("error \(error)")
        }

        let descriptionLabel = UILabel()
        descriptionLabel.text = NSLocalizedString("GROUP_LINK_QR_CODE_VIEW_DESCRIPTION",
                                                  comment: "Description text in the 'group link QR code' view.")
        descriptionLabel.textColor = Theme.secondaryTextAndIconColor
        descriptionLabel.font = .ows_dynamicTypeFootnote
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping

        let shareCodeButton = OWSFlatButton.button(title: NSLocalizedString("GROUP_LINK_QR_CODE_VIEW_SHARE_CODE_BUTTON",
                                                                            comment: "Label for the 'share code' button in the 'group link QR code' view."),
                                                   font: UIFont.ows_dynamicTypeBody.ows_semibold,
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
    func didTapShareCode(_ sender: UIButton) {
        do {
            let inviteLinkUrl = try GroupManager.groupInviteLink(forGroupModelV2: groupModelV2)
            let qrCodeImage = try QRCodeView.buildQRImage(url: inviteLinkUrl, forExport: true)
            guard let imageData = qrCodeImage.pngData() else {
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
