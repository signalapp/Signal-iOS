//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import PassKit
import SignalUI
import LibSignalClient

class BadgeGiftingConfirmationViewController: OWSTableViewController2 {
    // MARK: - View state

    private let badge: ProfileBadge
    private let price: UInt
    private let currencyCode: Currency.Code
    private let thread: TSContactThread

    public init(badge: ProfileBadge,
                price: UInt,
                currencyCode: Currency.Code,
                thread: TSContactThread) {
        self.badge = badge
        self.price = price
        self.currencyCode = currencyCode
        self.thread = thread
    }

    // MARK: - Callbacks

    public override func viewDidLoad() {
        self.shouldAvoidKeyboard = true

        super.viewDidLoad()

        databaseStorage.appendDatabaseChangeDelegate(self)

        title = NSLocalizedString("BADGE_GIFTING_CONFIRMATION_TITLE",
                                  comment: "Title on the screen where you confirm sending of a gift badge, and can write a message")

        setUpTableContents()
        setUpBottomFooter()

        tableView.keyboardDismissMode = .onDrag
    }

    public override func themeDidChange() {
        super.themeDidChange()
        setUpBottomFooter()
    }

    @objc
    private func requestApplePayDonation() {
        let request = DonationUtilities.newPaymentRequest(for: NSDecimalNumber(value: price), currencyCode: currencyCode)

        let paymentController = PKPaymentAuthorizationController(paymentRequest: request)
        paymentController.delegate = self
        paymentController.present { presented in
            if !presented {
                // This can happen under normal conditions if the user double-taps the button,
                // but may also indicate a problem.
                Logger.warn("Failed to present payment controller")
            }
        }
    }

    // MARK: - Table contents

    private lazy var avatarViewDataSource: ConversationAvatarDataSource = .thread(self.thread)

    private lazy var contactCellView: UIStackView = {
        let view = UIStackView()
        view.distribution = .equalSpacing
        return view
    }()

    private lazy var disappearingMessagesTimerLabelView: UILabel = {
        let labelView = UILabel()
        labelView.font = .ows_dynamicTypeBody2
        labelView.textAlignment = .center
        labelView.minimumScaleFactor = 0.8
        return labelView
    }()

    private lazy var disappearingMessagesTimerView: UIView = {
        let iconView = UIImageView(image: Theme.iconImage(.settingsTimer))
        iconView.contentMode = .scaleAspectFit

        let view = UIStackView(arrangedSubviews: [iconView, disappearingMessagesTimerLabelView])
        view.spacing = 4
        return view
    }()

    private lazy var messageTextView: TextViewWithPlaceholder = {
        let view = TextViewWithPlaceholder()
        view.placeholderText = NSLocalizedString("BADGE_GIFTING_ADDITIONAL_MESSAGE_PLACEHOLDER",
                                                 comment: "Placeholder in the text field where you can add text for a message along with your gift")
        view.delegate = self
        return view
    }()

    private var messageText: String {
        (messageTextView.text ?? "").ows_stripped()
    }

    private func setUpTableContents() {
        let badge = badge
        let price = price
        let currencyCode = currencyCode
        let avatarViewDataSource = avatarViewDataSource
        let thread = thread
        let messageTextView = messageTextView

        let badgeSection = OWSTableSection()
        badgeSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let cell = AppSettingsViewsUtil.newCell(cellOuterInsets: self.cellOuterInsets)

            let badgeCellView = GiftBadgeCellView(badge: badge, price: price, currencyCode: currencyCode)
            cell.contentView.addSubview(badgeCellView)
            badgeCellView.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        let recipientSection = OWSTableSection()
        recipientSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let cell = AppSettingsViewsUtil.newCell(cellOuterInsets: self.cellOuterInsets)

            let avatarView = ConversationAvatarView(sizeClass: .thirtySix,
                                                    localUserDisplayMode: .asUser,
                                                    badged: true)
            let (recipientName, disappearingMessagesDuration) = self.databaseStorage.read { transaction -> (String, UInt32) in
                avatarView.update(transaction) { config in
                    config.dataSource = avatarViewDataSource
                }

                let recipientName = self.contactsManager.displayName(for: thread, transaction: transaction)
                let disappearingMessagesDuration = thread.disappearingMessagesDuration(with: transaction)

                return (recipientName, disappearingMessagesDuration)
            }

            let nameLabel = UILabel()
            nameLabel.text = recipientName
            nameLabel.font = .ows_dynamicTypeBody
            nameLabel.numberOfLines = 0
            nameLabel.minimumScaleFactor = 0.5

            let avatarAndNameView = UIStackView(arrangedSubviews: [avatarView, nameLabel])
            avatarAndNameView.spacing = ContactCellView.avatarTextHSpacing

            let contactCellView = self.contactCellView
            contactCellView.removeAllSubviews()
            contactCellView.addArrangedSubview(avatarAndNameView)
            self.updateDisappearingMessagesTimerView(durationSeconds: disappearingMessagesDuration)
            cell.contentView.addSubview(contactCellView)
            contactCellView.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        let messageInfoSection = OWSTableSection()
        messageInfoSection.hasBackground = false
        messageInfoSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let cell = AppSettingsViewsUtil.newCell(cellOuterInsets: self.cellOuterInsets)

            let messageInfoLabel = UILabel()
            messageInfoLabel.text = NSLocalizedString("BADGE_GIFTING_ADDITIONAL_MESSAGE",
                                                      comment: "Text telling the user that they can add a message along with their gift badge")
            messageInfoLabel.font = .ows_dynamicTypeBody2
            messageInfoLabel.textColor = Theme.primaryTextColor
            messageInfoLabel.numberOfLines = 0
            cell.contentView.addSubview(messageInfoLabel)
            messageInfoLabel.autoPinEdgesToSuperviewMargins()

            return cell
        }))

        let messageTextSection = OWSTableSection()
        messageTextSection.add(.init(customCellBlock: { [weak self] in
            guard let self = self else { return UITableViewCell() }
            let cell = AppSettingsViewsUtil.newCell(cellOuterInsets: self.cellOuterInsets)

            cell.contentView.addSubview(messageTextView)
            messageTextView.autoPinEdgesToSuperviewMargins()
            messageTextView.autoSetDimension(.height, toSize: 102, relation: .greaterThanOrEqual)

            return cell
        }))

        contents = OWSTableContents(sections: [badgeSection,
                                               recipientSection,
                                               messageInfoSection,
                                               messageTextSection])
    }

    private func updateDisappearingMessagesTimerLabelView(durationSeconds: UInt32) {
        disappearingMessagesTimerLabelView.text = NSString.formatDurationSeconds(durationSeconds, useShortFormat: true)
    }

    private func updateDisappearingMessagesTimerView(durationSeconds: UInt32) {
        updateDisappearingMessagesTimerLabelView(durationSeconds: durationSeconds)

        disappearingMessagesTimerView.removeFromSuperview()
        if durationSeconds != 0 {
            contactCellView.addArrangedSubview(disappearingMessagesTimerView)
        }
    }

    // MARK: - Footer

    private let bottomFooterStackView = UIStackView()

    open override var bottomFooter: UIView? {
        get { bottomFooterStackView }
        set {}
    }

    private func setUpBottomFooter() {
        bottomFooterStackView.axis = .vertical
        bottomFooterStackView.alignment = .center
        bottomFooterStackView.layer.backgroundColor = self.tableBackgroundColor.cgColor
        bottomFooterStackView.spacing = 16
        bottomFooterStackView.isLayoutMarginsRelativeArrangement = true
        bottomFooterStackView.preservesSuperviewLayoutMargins = true
        bottomFooterStackView.layoutMargins = UIEdgeInsets(margin: 16)
        bottomFooterStackView.removeAllSubviews()

        let amountView: UIStackView = {
            let descriptionLabel = UILabel()
            descriptionLabel.text = NSLocalizedString("BADGE_GIFTING_PAYMENT_DESCRIPTION",
                                                      comment: "Text telling the user that their gift is a one-time donation")
            descriptionLabel.font = .ows_dynamicTypeBody
            descriptionLabel.numberOfLines = 0

            let priceLabel = UILabel()
            priceLabel.text = DonationUtilities.formatCurrency(NSDecimalNumber(value: price), currencyCode: currencyCode)
            priceLabel.font = .ows_dynamicTypeBody
            priceLabel.numberOfLines = 0

            let view = UIStackView(arrangedSubviews: [descriptionLabel, priceLabel])
            view.axis = .horizontal
            view.distribution = .equalSpacing
            view.layer.cornerRadius = 10
            view.layer.backgroundColor = (Theme.isDarkThemeEnabled ? UIColor.black : UIColor.white).cgColor
            view.layoutMargins = cellOuterInsets
            view.isLayoutMarginsRelativeArrangement = true

            return view
        }()

        let applePayButton = ApplePayButton { [weak self] in
            self?.requestApplePayDonation()
        }

        for view in [amountView, applePayButton] {
            bottomFooterStackView.addArrangedSubview(view)
            view.autoSetDimension(.height, toSize: 48, relation: .greaterThanOrEqual)
            view.autoPinWidthToSuperview(withMargin: 23)
        }
    }
}

// MARK: - Database observer delegate

extension BadgeGiftingConfirmationViewController: DatabaseChangeDelegate {
    private func updateDisappearingMessagesTimerWithSneakyTransaction() {
        let durationSeconds = databaseStorage.read { self.thread.disappearingMessagesDuration(with: $0) }
        updateDisappearingMessagesTimerView(durationSeconds: durationSeconds)
    }

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        if databaseChanges.didUpdate(thread: thread) {
            updateDisappearingMessagesTimerWithSneakyTransaction()
        }
    }

    func databaseChangesDidUpdateExternally() {
        updateDisappearingMessagesTimerWithSneakyTransaction()
    }

    func databaseChangesDidReset() {
        updateDisappearingMessagesTimerWithSneakyTransaction()
    }
}

// MARK: - Text view delegate

extension BadgeGiftingConfirmationViewController: TextViewWithPlaceholderDelegate {
    func textViewDidUpdateSelection(_ textView: TextViewWithPlaceholder) {
        textView.scrollToFocus(in: tableView, animated: true)
    }

    func textViewDidUpdateText(_ textView: TextViewWithPlaceholder) {
        // Kick the tableview so it recalculates sizes
        UIView.performWithoutAnimation {
            tableView.performBatchUpdates(nil) { (_) in
                // And when the size changes have finished, make sure we're scrolled
                // to the focused line
                textView.scrollToFocus(in: self.tableView, animated: false)
            }
        }
    }

    func textView(_ textView: TextViewWithPlaceholder,
                  uiTextView: UITextView,
                  shouldChangeTextIn range: NSRange,
                  replacementText text: String) -> Bool { true }
}

// MARK: - Apple Pay delegate

extension BadgeGiftingConfirmationViewController: PKPaymentAuthorizationControllerDelegate {
    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        var hasChargeCompleted = false

        let priceAsDecimal = NSDecimalNumber(value: price)

        firstly(on: .global()) {
            Stripe.boost(amount: priceAsDecimal, in: self.currencyCode, level: .giftBadge, for: payment)
        }.then { (intentId: String) -> Promise<ReceiptCredentialPresentation> in
            hasChargeCompleted = true

            // TODO (GB): Make this operation durable.
            let (receiptCredentialRequestContext, receiptCredentialRequest) = try SubscriptionManager.generateReceiptRequest()
            return try SubscriptionManager.requestBoostReceiptCredentialPresentation(
                for: intentId,
                context: receiptCredentialRequestContext,
                request: receiptCredentialRequest,
                expectedBadgeLevel: .giftBadge
            )
        }.then { (receiptCredentialPresentation: ReceiptCredentialPresentation) -> Promise<Void> in
            self.databaseStorage.write { transaction -> Promise<Void> in
                func send(_ preparer: OutgoingMessagePreparer) -> Promise<Void> {
                    preparer.insertMessage(transaction: transaction)
                    return ThreadUtil.enqueueMessagePromise(message: preparer.unpreparedMessage,
                                                            transaction: transaction)
                }

                let giftMessagePromise = send(OutgoingMessagePreparer(
                    giftBadgeReceiptCredentialPresentation: receiptCredentialPresentation,
                    thread: self.thread,
                    transaction: transaction
                ))

                let messagesPromise: Promise<Void>
                if self.messageText.isEmpty {
                    messagesPromise = giftMessagePromise
                } else {
                    let textMessagePromise = send(OutgoingMessagePreparer(
                        messageBody: MessageBody(text: self.messageText, ranges: .empty),
                        thread: self.thread,
                        transaction: transaction
                    ))
                    messagesPromise = giftMessagePromise.then { textMessagePromise }
                }

                return messagesPromise.asVoid()
            }
        }.done(on: .main) {
            completion(.init(status: .success, errors: nil))
            SignalApp.shared().presentConversation(for: self.thread, action: .none, animated: false)
            self.dismiss(animated: true)
            controller.dismiss()
        }.catch(on: .main) { error in
            owsFailDebugUnlessNetworkFailure(error)

            completion(.init(status: .failure, errors: [error]))

            let title: String
            let message: String
            if hasChargeCompleted {
                title = NSLocalizedString("BADGE_GIFTING_PAYMENT_SUCCEEDED_BUT_GIFTING_FAILED_TITLE",
                                          comment: "Title for the action sheet when you try to send a gift badge. They were charged but the badge could not be sent. They should contact support.")
                message = NSLocalizedString("BADGE_GIFTING_PAYMENT_SUCCEEDED_BUT_GIFTING_FAILED_BODY",
                                            comment: "Text in the action sheet when you try to send a gift badge. They were charged but the badge could not be sent. They should contact support.")
            } else {
                title = NSLocalizedString("BADGE_GIFTING_PAYMENT_FAILED_TITLE",
                                          comment: "Title for the action sheet when you try to send a gift badge but the payment failed")
                message = NSLocalizedString("BADGE_GIFTING_PAYMENT_FAILED_BODY",
                                            comment: "Text in the action sheet when you try to send a gift badge but the payment failed. Tells the user that they have not been charged")
            }

            OWSActionSheets.showActionSheet(title: title, message: message)
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
    }
}

// MARK: - Outgoing message preparer

extension OutgoingMessagePreparer {
    public convenience init(giftBadgeReceiptCredentialPresentation: ReceiptCredentialPresentation,
                            thread: TSThread,
                            transaction: SDSAnyReadTransaction) {
        let message = TSOutgoingMessageBuilder(
            thread: thread,
            expiresInSeconds: thread.disappearingMessagesDuration(with: transaction),
            giftBadge: OWSGiftBadge(redemptionCredential: Data(giftBadgeReceiptCredentialPresentation.serialize()))
        ).build(transaction: transaction)

        self.init(message)
    }
}
