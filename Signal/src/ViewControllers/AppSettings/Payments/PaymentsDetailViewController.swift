//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class PaymentsDetailViewController: OWSTableViewController2 {

    private var paymentItem: PaymentsHistoryItem

    public init(paymentItem: PaymentsHistoryItem) {
        self.paymentItem = paymentItem

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_PAYMENTS_DETAIL_VIEW_TITLE",
                                  comment: "Label for the 'payments details' view of the app settings.")

        updateTableContents()

        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTableContents()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        SSKEnvironment.shared.paymentsCurrenciesRef.updateConversionRates()

        if paymentItem.isUnread {
            SSKEnvironment.shared.databaseStorageRef.asyncWrite { [weak self] tx in
                self?.paymentItem.markAsRead(tx: tx)
            }
        }
    }

    public override func themeDidChange() {
        super.themeDidChange()

        updateTableContents()
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        let contents = OWSTableContents()

        let headerSection = OWSTableSection()
        headerSection.shouldDisableCellSelection = true
        headerSection.add(OWSTableItem(customCellBlock: { [weak self] in
            let cell = OWSTableItem.newCell()
            self?.configureHeader(cell: cell)
            return cell
        },
        actionBlock: nil))
        contents.add(headerSection)

        contents.add(buildStatusSection())

        if
            DebugFlags.internalSettings,
            let payment = paymentItem as? PaymentsHistoryModelItem
        {
            contents.add(buildInternalSection(paymentModel: payment.paymentModel))
        }

        self.contents = contents
    }

    private func buildInternalSection(paymentModel: TSPaymentModel) -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = "Internal"

        section.add(OWSTableItem.item(name: "paymentType",
                                      accessoryText: paymentModel.paymentType.formatted,
                                      accessibilityIdentifier: "paymentType",
                                      actionBlock: nil))
        section.add(OWSTableItem.item(name: "paymentState",
                                      accessoryText: paymentModel.paymentState.formatted,
                                      accessibilityIdentifier: "paymentState",
                                      actionBlock: nil))
        section.add(OWSTableItem.item(name: "paymentFailure",
                                      accessoryText: paymentModel.paymentFailure.formatted,
                                      accessibilityIdentifier: "paymentFailure",
                                      actionBlock: nil))

        if let paymentAmount = paymentModel.paymentAmount {
            section.add(OWSTableItem.item(name: "paymentAmount",
                                          accessoryText: paymentAmount.formatted,
                                          accessibilityIdentifier: "paymentAmount",
                                          actionBlock: nil))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        section.add(OWSTableItem.item(name: "createdDate",
                                      accessoryText: dateFormatter.string(from: paymentModel.createdDate),
                                      accessibilityIdentifier: "createdDate",
                                      actionBlock: nil))

        guard let mobileCoin = paymentModel.mobileCoin else {
            return section
        }

        func hexFormatData(_ data: Data) -> String {
            return "0x\(data.hexadecimalString.prefix(8))…"
        }

        if let recipientPublicAddressData = mobileCoin.recipientPublicAddressData {
            section.add(.copyableItem(label: "recipientPublicAddressData",
                                      value: hexFormatData(recipientPublicAddressData),
                                      pasteboardValue: recipientPublicAddressData.base64EncodedString()))
        }

        if let transactionData = mobileCoin.transactionData {
            section.add(.copyableItem(label: "transactionData",
                                      value: hexFormatData(transactionData),
                                      pasteboardValue: transactionData.base64EncodedString()))
        }

        if let receiptData = mobileCoin.receiptData {
            section.add(.copyableItem(label: "receiptData",
                                      value: hexFormatData(receiptData),
                                      pasteboardValue: receiptData.base64EncodedString()))
        }

        for (index, publicKey) in (mobileCoin.incomingTransactionPublicKeys ?? []).enumerated() {
            section.add(.copyableItem(label: "incomingTxoPublicKey.\(index)",
                                      value: hexFormatData(publicKey),
                                      pasteboardValue: publicKey.base64EncodedString()))
        }

        for (index, keyImage) in (mobileCoin.spentKeyImages ?? []).enumerated() {
            section.add(.copyableItem(label: "spentKeyImage.\(index)",
                                      value: hexFormatData(keyImage),
                                      pasteboardValue: keyImage.base64EncodedString()))
        }

        for (index, publicKey) in (mobileCoin.outputPublicKeys ?? []).enumerated() {
            section.add(.copyableItem(label: "outputPublicKey.\(index)",
                                      value: hexFormatData(publicKey),
                                      pasteboardValue: publicKey.base64EncodedString()))
        }

        if let ledgerBlockDate = mobileCoin.ledgerBlockDate {
            section.add(OWSTableItem.item(name: "ledgerBlockDate",
                                          accessoryText: dateFormatter.string(from: ledgerBlockDate),
                                          accessibilityIdentifier: "ledgerBlockDate",
                                          actionBlock: nil))
        }

        if mobileCoin.ledgerBlockIndex > 0 {
            section.add(OWSTableItem.item(name: "ledgerBlockIndex",
                                          accessoryText: "\(mobileCoin.ledgerBlockIndex)",
                                          accessibilityIdentifier: "ledgerBlockIndex",
                                          actionBlock: nil))
        }

        if let feeAmount = mobileCoin.feeAmount {
            section.add(OWSTableItem.item(name: "feeAmount",
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

        // Block
        if
            paymentItem.isUnidentified,
            let index = paymentItem.ledgerBlockIndex,
            index > 0
        {
            section.add(buildStatusItem(topText: OWSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_BLOCK_INDEX",
                                                                   comment: "Label for the 'MobileCoin block index' in the payment details view in the app settings."),
                                        bottomText: OWSFormat.formatUInt64(index)))
        }

        // Type/Amount
        if
            let value = paymentItem.formattedPaymentAmount,
           !paymentItem.isFailed
        {
            let title: String
            if let senderOrRecipientAddress = paymentItem.address {
                let username = SSKEnvironment.shared.databaseStorageRef.read { tx in
                    return SSKEnvironment.shared.contactManagerRef.displayName(for: senderOrRecipientAddress, tx: tx).resolvedValue()
                }
                let titleFormat: String = {
                    switch paymentItem {
                    case let item where item.isIncoming:
                        return OWSLocalizedString(
                            "SETTINGS_PAYMENTS_PAYMENT_DETAILS_RECEIVED_FORMAT",
                            comment: "Format for indicator that you received a payment in the payment details view in the app settings. Embeds: {{ the user who sent you the payment }}."
                        )
                    case let item where item.paymentState.messageReceiptStatus == .sending:
                        return OWSLocalizedString(
                            "SETTINGS_PAYMENTS_PAYMENT_DETAILS_SENDING_FORMAT",
                            comment: "Format for indicator that you sent a payment in the payment details view in the app settings. Embeds: {{ the user who you sent the payment to }}."
                        )
                    default:
                        return OWSLocalizedString(
                            "SETTINGS_PAYMENTS_PAYMENT_DETAILS_SENT_FORMAT",
                            comment: "Format for indicator that you sent a payment in the payment details view in the app settings. Embeds: {{ the user who you sent the payment to }}."
                        )
                    }
                }()
                title = String(format: titleFormat, username)
            } else {
                if paymentItem.isIncoming {
                    title = OWSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_RECEIVED",
                                              comment: "Indicates that you received a payment in the payment details view in the app settings.")
                } else {
                    title = OWSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_SENT",
                                              comment: "Indicates that you sent a payment in the payment details view in the app settings.")
                }
            }

            section.add(buildStatusItem(topText: title, bottomText: value))
        }

        // Fee
        if paymentItem.isOutgoing,
           let feeAmount = paymentItem.formattedFeeAmount, !paymentItem.isFailed {
            section.add(buildStatusItem(topText: OWSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_FEE",
                                                                   comment: "Label for the 'MobileCoin network fee' in the payment details view in the app settings."),
                                        bottomText: feeAmount))
        }

        // TODO: We might not want to include dates if an incoming
        //       transaction has not yet been verified.
        if let statusMessage = paymentItem.statusDescription(isLongForm: true) {
            section.add(buildStatusItem(
                topText: OWSLocalizedString(
                    "SETTINGS_PAYMENTS_PAYMENT_DETAILS_STATUS",
                    comment: "Label for the transaction status in the payment details view in the app settings."
                ),
                bottomText: statusMessage,
                useFailedColor: paymentItem.isFailed
            ))
        }

        // Sender
        do {
            let sender = { () -> String in
                if paymentItem.isOutgoing {
                    return CommonStrings.you
                }
                let displayName: DisplayName
                if let senderAci = paymentItem.address {
                    displayName = SSKEnvironment.shared.databaseStorageRef.read { tx in
                        return SSKEnvironment.shared.contactManagerRef.displayName(for: senderAci, tx: tx)
                    }
                } else {
                    displayName = .unknown
                }
                return displayName.resolvedValue()
            }()
            let value: String
            if let mcLedgerBlockDate = paymentItem.ledgerBlockDate {
                let senderFormat = OWSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_SENDER_FORMAT",
                                                     comment: "Format for the sender info in the payment details view in the app settings. Embeds {{ %1$@ the name of the sender of the payment, %2$@ the date the transaction was sent }}.")
                value = String(format: senderFormat,
                               sender,
                               TSPaymentModel.formatDate(mcLedgerBlockDate, isLongForm: true))
            } else {
                value = sender
            }
            let topTextLocalization: String = {
                switch paymentItem {
                case let item where item.isFailed:
                    return OWSLocalizedString(
                        "SETTINGS_PAYMENTS_PAYMENT_DETAILS_SENDER_ATTEMPTED",
                        comment: "Label for the sender in the payment details view in the app settings when the status is 'Failed'. Followed by sender name."
                    )
                default:
                    return OWSLocalizedString(
                        "SETTINGS_PAYMENTS_PAYMENT_DETAILS_SENDER",
                        comment: "Label for the sender in the payment details view in the app settings."
                    )
                }
            }()
            section.add(
                buildStatusItem(
                    topText: topTextLocalization,
                    bottomText: value
                )
            )
        }

        let footerText = (paymentItem.isDefragmentation
                            ? OWSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_STATUS_FOOTER_DEFRAGMENTATION",
                                                comment: "Footer string for the status section of the payment details view in the app settings for defragmentation transactions.")
                            : OWSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_STATUS_FOOTER",
                                                comment: "Footer string for the status section of the payment details view in the app settings."))
        let footerLabel = PaymentsViewUtils.buildTextWithLearnMoreLinkTextView(
            text: footerText,
            font: .dynamicTypeCaption1Clamped,
            learnMoreUrl: URL.Support.Payments.details)
        let footerStack = UIStackView(arrangedSubviews: [footerLabel])
        footerStack.axis = .vertical
        footerStack.alignment = .fill
        footerStack.layoutMargins = .init(hMargin: Self.cellHInnerMargin, vMargin: 12)
        footerStack.isLayoutMarginsRelativeArrangement = true
        section.customFooterView = footerStack

        return section
    }

    private func buildStatusItem(
        topText: String,
        bottomText: String,
        useFailedColor: Bool = false
    ) -> OWSTableItem {
        OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()

            let topLabel = UILabel()
            topLabel.text = topText
            topLabel.textColor = useFailedColor ? .ows_accentRed : Theme.primaryTextColor
            topLabel.font = UIFont.dynamicTypeBodyClamped

            let bottomLabel = UILabel()
            bottomLabel.text = bottomText
            bottomLabel.textColor = Theme.secondaryTextAndIconColor
            bottomLabel.font = UIFont.dynamicTypeFootnoteClamped
            bottomLabel.numberOfLines = 0
            bottomLabel.lineBreakMode = .byWordWrapping

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
        if let senderOrRecipientAddress = paymentItem.address {
            configureHeaderContact(cell: cell, address: senderOrRecipientAddress)
        } else {
            configureHeaderUnidentified(cell: cell)
        }
    }

    private func configureHeaderContact(cell: UITableViewCell,
                                        address: SignalServiceAddress) {

        var stackViews = [UIView]()

        let avatarView = ConversationAvatarView(sizeClass: .customDiameter(52), localUserDisplayMode: .asUser)
        stackViews.append(avatarView)
        stackViews.append(UIView.spacer(withHeight: 12))

        let usernameLabel = UILabel()
        usernameLabel.textColor = Theme.primaryTextColor
        usernameLabel.font = UIFont.dynamicTypeSubheadlineClamped
        usernameLabel.textAlignment = .center
        usernameLabel.numberOfLines = 0
        usernameLabel.lineBreakMode = .byWordWrapping
        stackViews.append(usernameLabel)
        stackViews.append(UIView.spacer(withHeight: 8))

        stackViews.append(buildAmountView())

        if let memoLabel = PaymentsViewUtils.buildMemoLabel(memoMessage: paymentItem.memoMessage) {
            stackViews.append(UIView.spacer(withHeight: 12))
            stackViews.append(memoLabel)
        }

        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            avatarView.update(transaction) { config in
                config.dataSource = .address(address)
            }

            let displayName = SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: transaction).resolvedValue()
            let displayNameFormat = (
                self.paymentItem.isIncoming
                ? OWSLocalizedString(
                    "SETTINGS_PAYMENTS_PAYMENT_USER_INCOMING_FORMAT",
                    comment: "Format string for the sender of an incoming payment. Embeds: {{ the name of the sender of the payment}}."
                )
                : OWSLocalizedString(
                    "SETTINGS_PAYMENTS_PAYMENT_USER_OUTGOING_FORMAT",
                    comment: "Format string for the recipient of an outgoing payment. Embeds: {{ the name of the recipient of the payment}}."
                )
            )
            usernameLabel.text = String(format: displayNameFormat, displayName)
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
        usernameLabel.font = UIFont.dynamicTypeBodyClamped
        usernameLabel.textAlignment = .center
        usernameLabel.numberOfLines = 0
        usernameLabel.lineBreakMode = .byWordWrapping
        stackViews.append(usernameLabel)
        stackViews.append(UIView.spacer(withHeight: 8))

        let amountLabel = UILabel()
        amountLabel.textColor = Theme.primaryTextColor
        amountLabel.font = UIFont.regularFont(ofSize: 54)
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
        amountLabel.font = UIFont.regularFont(ofSize: 54)
        amountLabel.textAlignment = .center
        amountLabel.adjustsFontSizeToFitWidth = true

        let amountWrapper = UIView.container()
        amountWrapper.addSubview(amountLabel)
        amountLabel.autoPinEdgesToSuperviewEdges()

        if paymentItem.isFailed {
            amountLabel.alpha = 0.3
        } else if !paymentItem.paymentState.isVerified {
            amountLabel.alpha = 0.5
        }

        if let amount = paymentItem.attributedPaymentAmount {
            amountLabel.attributedText = amount
        } else {
            amountLabel.text = " "

            let activityIndicator = UIActivityIndicatorView(style: .medium)
            amountWrapper.addSubview(activityIndicator)
            activityIndicator.autoCenterInSuperview()
            activityIndicator.startAnimating()
        }

        return amountWrapper
    }

    // MARK: -

    private func updateItem() {
        guard let _ = SSKEnvironment.shared.databaseStorageRef.read(block: { [weak self] tx in
            self?.paymentItem.reload(tx: tx)
        }) else {
            navigationController?.popViewController(animated: true)
            return
        }

        updateTableContents()
    }

}

// MARK: -

extension PaymentsDetailViewController: DatabaseChangeDelegate {

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard databaseChanges.didUpdate(tableName: TSPaymentModel.table.tableName) else {
            return
        }

        updateItem()
    }

    public func databaseChangesDidUpdateExternally() {
        updateItem()
    }

    public func databaseChangesDidReset() {
        updateItem()
    }
}
