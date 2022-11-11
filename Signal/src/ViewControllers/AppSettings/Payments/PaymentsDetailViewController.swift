//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

class PaymentsDetailViewController: OWSTableViewController2 {

    private var paymentItem: PaymentsHistoryItem

    public init(paymentItem: PaymentsHistoryItem) {
        self.paymentItem = paymentItem

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

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
            removeButton.autoPinEdge(toSuperviewEdge: .left, withInset: cellHOuterLeftMargin)
            removeButton.autoPinEdge(toSuperviewEdge: .right, withInset: cellHOuterRightMargin)
            removeButton.autoPin(toBottomLayoutGuideOf: self, withInset: 8)
        }

        updateTableContents()

        Self.databaseStorage.appendDatabaseChangeDelegate(self)
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

        // Block
        if paymentModel.isUnidentified,
           paymentModel.mcLedgerBlockIndex > 0 {
            section.add(buildStatusItem(topText: NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_BLOCK_INDEX",
                                                                   comment: "Label for the 'MobileCoin block index' in the payment details view in the app settings."),
                                        bottomText: OWSFormat.formatUInt64(paymentModel.mcLedgerBlockIndex)))
        }

        // Type/Amount
        if let paymentAmount = paymentItem.paymentAmount,
           !paymentAmount.isZero {
            let title: String
            if let address = paymentModel.address {
                let username = Self.contactsManager.displayName(for: address)
                let titleFormat: String
                if paymentItem.isIncoming {
                    titleFormat = NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_RECEIVED_FORMAT",
                                                    comment: "Format for indicator that you received a payment in the payment details view in the app settings. Embeds: {{ the user who sent you the payment }}.")
                } else {
                    titleFormat = NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_SENT_FORMAT",
                                                    comment: "Format for indicator that you sent a payment in the payment details view in the app settings. Embeds: {{ the user who you sent the payment to }}.")
                }
                title = String(format: titleFormat, username)
            } else {
                if paymentItem.isIncoming {
                    title = NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_RECEIVED",
                                              comment: "Indicates that you received a payment in the payment details view in the app settings.")
                } else {
                    title = NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_SENT",
                                              comment: "Indicates that you sent a payment in the payment details view in the app settings.")
                }
            }

            let value = PaymentsFormat.format(paymentAmount: paymentAmount,
                                              isShortForm: false,
                                              withCurrencyCode: true,
                                              withSpace: true)

            section.add(buildStatusItem(topText: title,
                                        bottomText: value))
        }

        // Fee
        if paymentModel.isOutgoing,
           let feeAmount = paymentItem.paymentModel.mobileCoin?.feeAmount {
            let value = PaymentsFormat.format(paymentAmount: feeAmount,
                                                   isShortForm: false,
                                                   withCurrencyCode: true,
                                                   withSpace: true)
            section.add(buildStatusItem(topText: NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_FEE",
                                                                   comment: "Label for the 'MobileCoin network fee' in the payment details view in the app settings."),
                                        bottomText: value))
        }

        // TODO: We might not want to include dates if an incoming
        //       transaction has not yet been verified.

        section.add(buildStatusItem(topText: NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_STATUS",
                                                               comment: "Label for the transaction status in the payment details view in the app settings."),
                                    bottomText: paymentModel.statusDescription(isLongForm: true)))

        // Sender
        do {
            let sender = { () -> String in
                if paymentItem.isOutgoing {
                    return CommonStrings.you
                }
                if let address = paymentModel.address {
                    return Self.contactsManager.displayName(for: address)
                }
                return Self.contactsManager.unknownUserLabel
            }()
            let value: String
            if let mcLedgerBlockDate = paymentItem.paymentModel.mcLedgerBlockDate {
                let senderFormat = NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_SENDER_FORMAT",
                                                     comment: "Format for the sender info in the payment details view in the app settings. Embeds {{ %1$@ the name of the sender of the payment, %2$@ the date the transaction was sent }}.")
                value = String(format: senderFormat,
                               sender,
                               TSPaymentModel.formatDate(mcLedgerBlockDate, isLongForm: true))
            } else {
                value = sender
            }
            section.add(buildStatusItem(topText: NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_SENDER",
                                                                   comment: "Label for the sender in the payment details view in the app settings."),
                                        bottomText: value))
        }

        let footerText = (paymentModel.isDefragmentation
                            ? NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_STATUS_FOOTER_DEFRAGMENTATION",
                                                comment: "Footer string for the status section of the payment details view in the app settings for defragmentation transactions.")
                            : NSLocalizedString("SETTINGS_PAYMENTS_PAYMENT_DETAILS_STATUS_FOOTER",
                                                comment: "Footer string for the status section of the payment details view in the app settings."))
        let footerLabel = PaymentsViewUtils.buildTextWithLearnMoreLinkTextView(
            text: footerText,
            font: .ows_dynamicTypeCaption1Clamped,
            learnMoreUrl: "https://support.signal.org/hc/en-us/articles/360057625692#payments_details")
        let footerStack = UIStackView(arrangedSubviews: [footerLabel])
        footerStack.axis = .vertical
        footerStack.alignment = .fill
        footerStack.layoutMargins = cellOuterInsetsWithMargin(hMargin: Self.cellHInnerMargin, vMargin: 12)
        footerStack.isLayoutMarginsRelativeArrangement = true
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
        if let address = paymentItem.paymentModel.address {
            configureHeaderContact(cell: cell, address: address)
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
            avatarView.update(transaction) { config in
                config.dataSource = .address(address)
            }

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

        if paymentItem.isFailed {
            amountLabel.text = nil
        } else if let paymentAmount = paymentItem.paymentAmount {
            amountLabel.attributedText = PaymentsFormat.attributedFormat(paymentAmount: paymentAmount,
                                                                         isShortForm: false,
                                                                         paymentType: paymentItem.paymentType)
        } else {
            amountLabel.text = " "

            let activityIndicator = UIActivityIndicatorView(style: Theme.isDarkThemeEnabled
                                                                ? .white
                                                                : .gray)
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
                                               displayName: paymentItem.displayName)

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
}

// MARK: -

extension PaymentsDetailViewController: DatabaseChangeDelegate {

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()

        guard databaseChanges.didUpdateModel(collection: TSPaymentModel.collection()) else {
            return
        }

        updateItem()
    }

    public func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()

        updateItem()
    }

    public func databaseChangesDidReset() {
        AssertIsOnMainThread()

        updateItem()
    }
}
