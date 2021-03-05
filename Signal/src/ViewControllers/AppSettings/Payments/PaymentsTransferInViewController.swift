//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class PaymentsTransferInViewController: OWSTableViewController2 {

    @objc
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PAYMENTS_ADD_MONEY",
                                  comment: "Label for 'add money' view in the payment settings.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))

        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "share-ios-24"),
                                                            landscapeImagePhone: nil,
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(didTapShare))

        updateTableContents()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let addressSection = OWSTableSection()
        addressSection.hasBackground = false
        addressSection.add(OWSTableItem(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            self?.configureAddressCell(cell: cell)
            return cell
        },
        actionBlock: { [weak self] in
            self?.didTapCopyAddress()
        }))
        contents.addSection(addressSection)

        let infoSection = OWSTableSection()
        infoSection.hasBackground = false
        infoSection.add(OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()

            let label1 = UILabel()
            label1.text = NSLocalizedString("SETTINGS_PAYMENTS_ADD_MONEY_DESCRIPTION",
                                            comment: "Explanation of the process for adding money in the 'add money' settings view.")
            label1.textColor = Theme.secondaryTextAndIconColor
            label1.font = .ows_dynamicTypeBody2Clamped
            label1.numberOfLines = 0
            label1.lineBreakMode = .byWordWrapping
            label1.textAlignment = .center

            let label2 = UILabel()
            label2.text = CommonStrings.learnMore
            label2.textColor = Theme.primaryTextColor
            label2.font = UIFont.ows_dynamicTypeBody2Clamped.ows_semibold
            label2.textAlignment = .center

            let stack = UIStackView(arrangedSubviews: [label1, label2])
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = 8
            cell.contentView.addSubview(stack)
            stack.autoPinEdgesToSuperviewMargins()

            return cell
        },
        actionBlock: { [weak self] in
            self?.didTapLearnMore()
        }))
        contents.addSection(infoSection)

        self.contents = contents
    }

    private func configureAddressCell(cell: UITableViewCell) {
        func configureWithSubviews(subviews: [UIView]) {
            let innerStack = UIStackView(arrangedSubviews: subviews)
            innerStack.axis = .vertical
            innerStack.alignment = .center
            innerStack.layoutMargins = UIEdgeInsets(top: 44, leading: 44, bottom: 32, trailing: 44)
            innerStack.isLayoutMarginsRelativeArrangement = true

            let backgroundView = innerStack.addBackgroundView(withBackgroundColor: Theme.tableCell2BackgroundColor)
            backgroundView.layer.cornerRadius = 10

            let outerStack = UIStackView(arrangedSubviews: [innerStack])
            outerStack.axis = .vertical
            outerStack.alignment = .center
            outerStack.layoutMargins = UIEdgeInsets(top: 40, leading: 40, bottom: 0, trailing: 40)
            outerStack.isLayoutMarginsRelativeArrangement = true
            cell.contentView.addSubview(outerStack)
            outerStack.autoPinEdgesToSuperviewMargins()
        }

        func configureForError() {
            let label = UILabel()
            label.text = NSLocalizedString("SETTINGS_PAYMENTS_INVALID_WALLET_ADDRESS",
                                           comment: "Indicator that the payments wallet address is invalid.")
            label.textColor = Theme.primaryTextColor
            label.font = UIFont.ows_dynamicTypeBody2Clamped.ows_semibold

            configureWithSubviews(subviews: [label])
        }

        guard let walletAddressQRUrl = payments.walletAddressQRUrl(),
              let walletAddressBase58 = payments.walletAddressBase58() else {
            configureForError()
            return
        }
        let qrImage: UIImage
        do {
            qrImage = try QRCodeView.buildQRImage(url: walletAddressQRUrl)
        } catch {
            owsFailDebug("Error: \(error)")
            configureForError()
            return
        }

        let qrCodeView = UIImageView(image: qrImage)
        // Don't antialias QR Codes.
        qrCodeView.layer.magnificationFilter = .nearest
        qrCodeView.layer.minificationFilter = .nearest
        let viewSize = view.bounds.size
        let qrCodeSize = min(viewSize.width, viewSize.height) * 0.5
        qrCodeView.autoSetDimensions(to: .square(qrCodeSize))

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_WALLET_ADDRESS_LABEL",
                                            comment: "Label for the payments wallet address.")
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = UIFont.ows_dynamicTypeBody2Clamped.ows_semibold
        titleLabel.textAlignment = .center

        let walletAddressLabel = UILabel()
        walletAddressLabel.text = walletAddressBase58
        walletAddressLabel.textColor = Theme.secondaryTextAndIconColor
        walletAddressLabel.font = UIFont.ows_monospacedDigitFont(withSize: UIFont.ows_dynamicTypeBody2Clamped.pointSize)
        walletAddressLabel.lineBreakMode = .byTruncatingMiddle
        walletAddressLabel.textAlignment = .center

        let copyLabel = UILabel()
        copyLabel.text = CommonStrings.copyButton
        copyLabel.textColor = Theme.accentBlueColor
        copyLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped.ows_semibold

        let copyStack = UIStackView(arrangedSubviews: [copyLabel])
        copyStack.axis = .vertical
        copyStack.layoutMargins = UIEdgeInsets(hMargin: 30, vMargin: 4)
        copyStack.isLayoutMarginsRelativeArrangement = true
        copyStack.addPillBackgroundView(backgroundColor: Theme.secondaryBackgroundColor)

        configureWithSubviews(subviews: [
            qrCodeView,
            UIView.spacer(withHeight: 20),
            titleLabel,
            UIView.spacer(withHeight: 8),
            walletAddressLabel,
            UIView.spacer(withHeight: 20),
            copyStack
        ])
    }

    // MARK: - Events

    private func didTapCopyAddress() {
        AssertIsOnMainThread()

        // TODO: Should this be the address b58 or the address url?
        guard let walletAddressBase58 = payments.walletAddressBase58() else {
            owsFailDebug("Missing walletAddressBase58.")
            return
        }
        UIPasteboard.general.string = walletAddressBase58

        presentToast(text: NSLocalizedString("SETTINGS_PAYMENTS_ADD_MONEY_WALLET_ADDRESS_COPIED",
                                             comment: "Indicator that the payments wallet address has been copied to the pasteboard."))
    }

    @objc
    func didTapDone() {
        navigationController?.popViewController(animated: true)
    }

    @objc
    func didTapShare() {
        // TODO: Should this be walletAddressBase58 or walletAddressQRUrl?
        guard let walletAddressQRUrl = payments.walletAddressQRUrl() else {
            owsFailDebug("Missing walletAddressBase58.")
            return
        }
        AttachmentSharing.showShareUI(forText: walletAddressQRUrl.absoluteString, sender: self)
    }

    @objc
    func didTapLearnMore() {
        // TODO:
    }
}
