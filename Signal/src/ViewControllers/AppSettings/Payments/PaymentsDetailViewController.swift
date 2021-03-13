//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

class PaymentsDetailViewController: OWSTableViewController2 {

    private var paymentItem: PaymentsHistoryItem

    public init(paymentItem: PaymentsHistoryItem) {
        self.paymentItem = paymentItem

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        useThemeBackgroundColors = true

        title = NSLocalizedString("SETTINGS_PAYMENTS_DETAIL_VIEW_TITLE",
                                  comment: "Label for the 'payments details' view of the app settings.")

        if !paymentItem.isUnidentified,
           FeatureFlags.paymentsScrubDetails {
            let removeButton = OWSFlatButton.button(title: NSLocalizedString("SETTINGS_PAYMENTS_REMOVE_BUTTON",
                                                                             comment: "Label for the 'remove payments details' button in the app settings."),
                                                    font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                                    titleColor: Theme.secondaryTextAndIconColor,
                                                    backgroundColor: Theme.washColor,
                                                    target: self,
                                                    selector: #selector(didTapRemove))
            removeButton.autoSetHeightUsingFont()
            view.addSubview(removeButton)
            removeButton.autoPinWidthToSuperview(withMargin: Self.cellHOuterMargin)
            removeButton.autoPin(toBottomLayoutGuideOf: self, withInset: 8)
        }

        updateTableContents()

        Self.databaseStorage.appendUIDatabaseSnapshotDelegate(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        paymentsCurrencies.updateConversationRatesIfStale()

        if paymentItem.paymentModel.isUnread {
            PaymentsViewUtils.markPaymentAsReadWithSneakyTransaction(paymentItem.paymentModel)
        }
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        let contents = OWSTableContents()

        let headerSection = OWSTableSection()
        headerSection.add(OWSTableItem(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            self?.configureHeader(cell: cell)
            return cell
        },
        actionBlock: nil))
        contents.addSection(headerSection)

        contents.addSection(buildStatusSection())

        if DebugFlags.internalSettings {
            contents.addSection(buildInternalSection())
        }

        self.contents = contents
    }

    private func buildInternalSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = "Internal"

        let paymentModel = paymentItem.paymentModel

        section.add(OWSTableItem.actionItem(name: "paymentType",
                                            accessoryText: paymentModel.paymentType.formatted,
                                            accessibilityIdentifier: "paymentType",
                                            actionBlock: nil))
        section.add(OWSTableItem.actionItem(name: "paymentState",
                                            accessoryText: paymentModel.paymentState.formatted,
                                            accessibilityIdentifier: "paymentState",
                                            actionBlock: nil))
        section.add(OWSTableItem.actionItem(name: "paymentFailure",
                                            accessoryText: paymentModel.paymentFailure.formatted,
                                            accessibilityIdentifier: "paymentFailure",
                                            actionBlock: nil))

        if let paymentAmount = paymentModel.paymentAmount {
            section.add(OWSTableItem.actionItem(name: "paymentAmount",
                                                accessoryText: paymentAmount.formatted,
                                                accessibilityIdentifier: "paymentAmount",
                                                actionBlock: nil))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        section.add(OWSTableItem.actionItem(name: "createdDate",
                                            accessoryText: dateFormatter.string(from: paymentModel.createdDate),
                                            accessibilityIdentifier: "createdDate",
                                            actionBlock: nil))

        guard let mobileCoin = paymentModel.mobileCoin else {
            return section
        }

        func hexFormatData(_ data: Data) -> String {
            "0x" + data.hexadecimalString.substring(to: 8) + "…"
        }

        if let recipientPublicAddressData = mobileCoin.recipientPublicAddressData {
            section.add(OWSTableItem.actionItem(name: "recipientPublicAddressData",
                                                accessoryText: hexFormatData(recipientPublicAddressData),
                                                accessibilityIdentifier: "recipientPublicAddressData",
                                                actionBlock: {
                                                    UIPasteboard.general.string = recipientPublicAddressData.base64EncodedString()
                                                }))
        }

        if let transactionData = mobileCoin.transactionData {
            section.add(OWSTableItem.actionItem(name: "transactionData",
                                                accessoryText: hexFormatData(transactionData),
                                                accessibilityIdentifier: "transactionData",
                                                actionBlock: {
                                                    UIPasteboard.general.string = transactionData.base64EncodedString()
                                                }))
        }

        if let receiptData = mobileCoin.receiptData {
            section.add(OWSTableItem.actionItem(name: "receiptData",
                                                accessoryText: hexFormatData(receiptData),
                                                accessibilityIdentifier: "receiptData",
                                                actionBlock: {
                                                    UIPasteboard.general.string = receiptData.base64EncodedString()
                                                }))
        }

        for (index, publicKey) in (mobileCoin.incomingTransactionPublicKeys ?? []).enumerated() {
            section.add(OWSTableItem.actionItem(name: "incomingTxoPublicKey.\(index)",
                                                accessoryText: hexFormatData(publicKey),
                                                accessibilityIdentifier: "incomingTxoPublicKey.\(index)",
                                                actionBlock: {
                                                    UIPasteboard.general.string = publicKey.base64EncodedString()
                                                }))
        }

        for (index, keyImage) in (mobileCoin.spentKeyImages ?? []).enumerated() {
            section.add(OWSTableItem.actionItem(name: "spentKeyImage.\(index)",
                                                accessoryText: hexFormatData(keyImage),
                                                accessibilityIdentifier: "spentKeyImages.\(index)",
                                                actionBlock: {
                                                    UIPasteboard.general.string = keyImage.base64EncodedString()
                                                }))
        }

        for (index, publicKey) in (mobileCoin.outputPublicKeys ?? []).enumerated() {
            section.add(OWSTableItem.actionItem(name: "outputPublicKey.\(index)",
                                                accessoryText: hexFormatData(publicKey),
                                                accessibilityIdentifier: "outputPublicKey.\(index)",
                                                actionBlock: {
                                                    UIPasteboard.general.string = publicKey.base64EncodedString()
                                                }))
        }

        if let ledgerBlockDate = mobileCoin.ledgerBlockDate {
            section.add(OWSTableItem.actionItem(name: "ledgerBlockDate",
                                                accessoryText: dateFormatter.string(from: ledgerBlockDate),
                                                accessibilityIdentifier: "ledgerBlockDate",
                                                actionBlock: nil))
        }

        if mobileCoin.ledgerBlockIndex > 0 {
            section.add(OWSTableItem.actionItem(name: "ledgerBlockIndex",
                                                accessoryText: "\(mobileCoin.ledgerBlockIndex)",
                                                accessibilityIdentifier: "ledgerBlockIndex",
                                                actionBlock: nil))
        }

        if let feeAmount = mobileCoin.feeAmount {
            section.add(OWSTableItem.actionItem(name: "feeAmount",
                                                accessoryText: feeAmount.formatted,
                                                accessibilityIdentifier: "feeAmount",
                                                actionBlock: nil))
        }

        return section
    }

    private func buildStatusSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.customHeaderHeight = 16

        let paymentItem = self.paymentItem
        let paymentModel = paymentItem.paymentModel

        if paymentModel.isOutgoing,
           let feeAmount = paymentItem.paymentModel.mobileCoin?.feeAmount {
            let bottomText = PaymentsFormat.format(paymentAmount: feeAmount,
                                                   isShortForm: false,
                                                   withCurrencyCode: true,
                                                   withSpace: true)
            section.add(buildStatusItem(topText: NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_FEE",
                                                                   comment: "Label for the 'MobileCoin network fee' in the payment details view in the app settings."),
                                        bottomText: bottomText))
        }

        // TODO: We might not want to include dates if an incoming
        //       transaction has not yet been verified.

        section.add(buildStatusItem(topText: NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_STATUS",
                                                               comment: "Label for the transaction status in the payment details view in the app settings."),
                                    bottomText: paymentModel.statusDescription(isLongForm: true)))

        if let address = paymentModel.address {
            var sender: String
            if paymentItem.isIncoming {
                sender = Self.contactsManager.displayName(for: address)
            } else {
                sender = NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_SENDER_YOU",
                                           comment: "Indicates that you send the payment in the payment details view in the app settings.")
            }
            let senderFormat = NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_SENDER_FORMAT",
                                                 comment: "Format for the sender info in the payment details view in the app settings. Embeds {{ %1$@ the name of the sender of the payment, %2$@ the date the transaction was sent }}.")
            let bottomText = String(format: senderFormat,
                                    sender,
                                    TSPaymentModel.formateDate(paymentItem.sortDate,
                                                               isLongForm: true))

            section.add(buildStatusItem(topText: NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_SENDER",
                                                                   comment: "Label for the sender in the payment details view in the app settings."),
                                        bottomText: bottomText))
        }

        let footerAttributedTitle = NSMutableAttributedString()
        footerAttributedTitle.append(NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_STATUS_FOOTER",
                                                       comment: "Footer string for the status section of the payment details view in the app settings."),
                                     attributes: [
                                        .font: UIFont.ows_dynamicTypeCaption1Clamped,
                                        .foregroundColor: Theme.secondaryTextAndIconColor
                                     ])
        footerAttributedTitle.append(" ",
                                     attributes: [
                                        .font: UIFont.ows_dynamicTypeCaption1Clamped,
                                        .foregroundColor: Theme.secondaryTextAndIconColor
                                     ])
        footerAttributedTitle.append(CommonStrings.learnMore,
                                     attributes: [
                                        .font: UIFont.ows_dynamicTypeCaption1Clamped.ows_semibold,
                                        .foregroundColor: Theme.primaryTextColor
                                     ])
        let footerLabel = UILabel()
        footerLabel.attributedText = footerAttributedTitle
        footerLabel.numberOfLines = 0
        footerLabel.lineBreakMode = .byWordWrapping
        let footerStack = UIStackView(arrangedSubviews: [footerLabel])
        footerStack.axis = .vertical
        footerStack.alignment = .fill
        footerStack.layoutMargins = UIEdgeInsets(hMargin: (OWSTableViewController2.cellHOuterMargin +
                                                            OWSTableViewController2.cellHInnerMargin),
                                                 vMargin: 12)
        footerStack.isLayoutMarginsRelativeArrangement = true
        footerStack.isUserInteractionEnabled = true
        footerStack.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapStatusFooter)))
        section.customFooterView = footerStack

        return section
    }

    private func buildStatusItem(topText: String, bottomText: String) -> OWSTableItem {
        OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()

            let topLabel = UILabel()
            topLabel.text = topText
            topLabel.textColor = Theme.primaryTextColor
            topLabel.font = UIFont.ows_dynamicTypeBodyClamped

            let bottomLabel = UILabel()
            bottomLabel.text = bottomText
            bottomLabel.textColor = Theme.secondaryTextAndIconColor
            bottomLabel.font = UIFont.ows_dynamicTypeFootnoteClamped

            let stack = UIStackView(arrangedSubviews: [topLabel, bottomLabel])
            stack.axis = .vertical
            stack.alignment = .fill

            cell.contentView.addSubview(stack)
            stack.autoPinEdgesToSuperviewMargins()

            return cell
        },
        actionBlock: nil)
    }

    private func configureHeader(cell: UITableViewCell) {
        if let address = paymentItem.paymentModel.address {
            configureHeaderContact(cell: cell, address: address)
        } else {
            configureHeaderUnidentified(cell: cell)
        }
    }

    private func configureHeaderContact(cell: UITableViewCell,
                                        address: SignalServiceAddress) {

        var stackViews = [UIView]()

        let avatarSize: UInt = 52
        let avatarView = AvatarImageView()
        avatarView.autoSetDimensions(to: .square(CGFloat(avatarSize)))
        stackViews.append(avatarView)
        stackViews.append(UIView.spacer(withHeight: 12))

        let usernameLabel = UILabel()
        usernameLabel.textColor = Theme.primaryTextColor
        usernameLabel.font = UIFont.ows_dynamicTypeSubheadlineClamped
        usernameLabel.textAlignment = .center
        usernameLabel.numberOfLines = 0
        usernameLabel.lineBreakMode = .byWordWrapping
        stackViews.append(usernameLabel)
        stackViews.append(UIView.spacer(withHeight: 8))

        stackViews.append(buildAmountView())

        if let memoLabel = PaymentsViewUtils.buildMemoLabel(memoMessage: paymentItem.paymentModel.memoMessage) {
            stackViews.append(UIView.spacer(withHeight: 12))
            stackViews.append(memoLabel)
        }

        databaseStorage.read { transaction in
            let colorName = TSContactThread.conversationColorName(forContactAddress: address,
                                                                  transaction: transaction)
            avatarView.image = OWSContactAvatarBuilder(address: address,
                                                       colorName: colorName,
                                                       diameter: avatarSize).build(with: transaction)

            let username = Self.contactsManager.displayName(for: address, transaction: transaction)
            let usernameFormat = (self.paymentItem.isIncoming
                                    ? NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_USER_INCOMING_FORMAT",
                                                        comment: "Format string for the sender of an incoming payment. Embeds: {{ the name of the sender of the payment}}.")
                                    : NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_USER_OUTGOING_FORMAT",
                                                        comment: "Format string for the recipient of an outgoing payment. Embeds: {{ the name of the recipient of the payment}}."))
            usernameLabel.text = String(format: usernameFormat, username)
        }

        let headerStack = UIStackView(arrangedSubviews: stackViews)
        headerStack.axis = .vertical
        headerStack.alignment = .center
        headerStack.layoutMargins = UIEdgeInsets(top: 24, leading: 0, bottom: 36, trailing: 0)
        headerStack.isLayoutMarginsRelativeArrangement = true
        cell.contentView.addSubview(headerStack)
        headerStack.autoPinEdgesToSuperviewMargins()
    }

    private func configureHeaderUnidentified(cell: UITableViewCell) {

        var stackViews = [UIView]()

        let avatarSize: UInt = 52
        let avatarView = PaymentsViewUtils.buildUnidentifiedTransactionAvatar(avatarSize: avatarSize)
        avatarView.autoSetDimensions(to: .square(CGFloat(avatarSize)))
        stackViews.append(avatarView)
        stackViews.append(UIView.spacer(withHeight: 12))

        let usernameLabel = UILabel()
        usernameLabel.text = paymentItem.displayName
        usernameLabel.textColor = Theme.primaryTextColor
        usernameLabel.font = UIFont.ows_dynamicTypeBodyClamped
        usernameLabel.textAlignment = .center
        usernameLabel.numberOfLines = 0
        usernameLabel.lineBreakMode = .byWordWrapping
        stackViews.append(usernameLabel)
        stackViews.append(UIView.spacer(withHeight: 8))

        let amountLabel = UILabel()
        amountLabel.textColor = Theme.primaryTextColor
        amountLabel.font = UIFont.ows_dynamicTypeLargeTitle1Clamped.withSize(54)
        amountLabel.textAlignment = .center
        amountLabel.adjustsFontSizeToFitWidth = true

        stackViews.append(buildAmountView())

        let headerStack = UIStackView(arrangedSubviews: stackViews)
        headerStack.axis = .vertical
        headerStack.alignment = .center
        headerStack.layoutMargins = UIEdgeInsets(top: 24, leading: 0, bottom: 36, trailing: 0)
        headerStack.isLayoutMarginsRelativeArrangement = true
        cell.contentView.addSubview(headerStack)
        headerStack.autoPinEdgesToSuperviewMargins()
    }

    private func buildAmountView() -> UIView {

        let amountLabel = UILabel()
        amountLabel.textColor = Theme.primaryTextColor
        amountLabel.font = UIFont.ows_dynamicTypeLargeTitle1Clamped.withSize(54)
        amountLabel.textAlignment = .center
        amountLabel.adjustsFontSizeToFitWidth = true

        let amountWrapper = UIView.container()
        amountWrapper.addSubview(amountLabel)
        amountLabel.autoPinEdgesToSuperviewEdges()

        if let paymentAmount = paymentItem.paymentAmount {
            amountLabel.attributedText = PaymentsFormat.attributedFormat(paymentAmount: paymentAmount,
                                                                         isShortForm: false,
                                                                         paymentType: paymentItem.paymentType)
        } else {
            amountLabel.text = " "

            let activityIndicator = UIActivityIndicatorView(style: .gray)
            amountWrapper.addSubview(activityIndicator)
            activityIndicator.autoCenterInSuperview()
            activityIndicator.startAnimating()
        }

        return amountWrapper
    }

    // MARK: -

    private func updateItem() {
        func reloadPaymentModel() -> TSPaymentModel? {
            Self.databaseStorage.read { transaction in
                TSPaymentModel.anyFetch(uniqueId: self.paymentItem.paymentModel.uniqueId, transaction: transaction)
            }
        }
        guard let paymentModel = reloadPaymentModel() else {
            navigationController?.popViewController(animated: true)
            return
        }

        self.paymentItem = PaymentsHistoryItem(paymentModel: paymentModel,
                                               displayName: paymentItem.displayName,
                                               conversationColorName: paymentItem.conversationColorName)

        updateTableContents()
    }

    // MARK: - Events

    @objc
    private func didTapRemove() {
        databaseStorage.write { transaction in
            self.payments.replaceAsUnidentified(paymentModel: self.paymentItem.paymentModel,
                                                transaction: transaction)
        }
        navigationController?.popViewController(animated: true)
    }

    @objc
    private func didTapStatusFooter() {
        // TODO: Need support link.
    }
}

// MARK: -

extension PaymentsDetailViewController: UIDatabaseSnapshotDelegate {
    public func uiDatabaseSnapshotWillUpdate() {}

    public func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        AssertIsOnMainThread()

        guard databaseChanges.didUpdateModel(collection: TSPaymentModel.collection()) else {
            return
        }

        updateItem()
    }

    public func uiDatabaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()

        updateItem()
    }

    public func uiDatabaseSnapshotDidReset() {
        AssertIsOnMainThread()

        updateItem()
    }
}
