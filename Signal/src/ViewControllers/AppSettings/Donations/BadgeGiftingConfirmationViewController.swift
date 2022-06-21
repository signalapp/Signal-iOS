//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import PassKit
import SignalUI

// TODO (GB) This view is unfinished.
class BadgeGiftingConfirmationViewController: OWSTableViewController2 {
    // MARK: - View state

    private let badge: ProfileBadge
    private let price: UInt
    private let currencyCode: Currency.Code
    private let recipientAddress: SignalServiceAddress
    private let recipientName: String

    public init(badge: ProfileBadge,
                price: UInt,
                currencyCode: Currency.Code,
                recipientAddress: SignalServiceAddress,
                recipientName: String) {
        self.badge = badge
        self.price = price
        self.currencyCode = currencyCode
        self.recipientAddress = recipientAddress
        self.recipientName = recipientName
    }

    // MARK: - Callbacks

    public override func viewDidLoad() {
        self.shouldAvoidKeyboard = true

        super.viewDidLoad()

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

    private lazy var avatarViewDataSource: ConversationAvatarDataSource = .address(self.recipientAddress)

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
        let recipientName = recipientName
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
            self.databaseStorage.read { transaction in
                avatarView.update(transaction) { config in
                    config.dataSource = avatarViewDataSource
                }
            }

            let nameLabel = UILabel()
            nameLabel.text = recipientName
            nameLabel.font = .ows_dynamicTypeBody
            nameLabel.numberOfLines = 0

            let avatarAndNameView = UIStackView(arrangedSubviews: [avatarView, nameLabel])
            avatarAndNameView.spacing = ContactCellView.avatarTextHSpacing

            let contactCellView = UIStackView(arrangedSubviews: [avatarAndNameView])
            contactCellView.distribution = .equalSpacing
            cell.contentView.addSubview(contactCellView)
            contactCellView.autoPinEdgesToSuperviewMargins()

            // TODO (GB) Show disappearing messages timer

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
        // TODO (GB) Actually charge the card and send the badge.
        let authResult = PKPaymentAuthorizationResult(status: .success, errors: nil)
        completion(authResult)

        firstly { () -> Promise<TSContactThread> in
            let (thread, messagePromise) = databaseStorage.write { transaction -> (TSContactThread, Promise<Void>) in
                let thread = TSContactThread.getOrCreateThread(withContactAddress: recipientAddress,
                                                               transaction: transaction)

                let messagePromise: Promise<Void>
                if messageText.isEmpty {
                    messagePromise = Promise.value(())
                } else {
                    let preparer = OutgoingMessagePreparer(
                        messageBody: MessageBody(text: messageText, ranges: .empty),
                        mediaAttachments: [],
                        thread: thread,
                        quotedReplyModel: nil,
                        transaction: transaction
                    )
                    preparer.insertMessage(linkPreviewDraft: nil, transaction: transaction)
                    messagePromise = ThreadUtil.enqueueMessagePromise(message: preparer.unpreparedMessage,
                                                                      transaction: transaction)
                }

                return (thread, messagePromise)
            }

            return messagePromise.map { thread }
        }.done { (thread: TSContactThread) in
            SignalApp.shared().presentConversation(for: thread, action: .none, animated: false)
            self.dismiss(animated: true)
            controller.dismiss()
        }.catch { error in
            // TODO (GB) If the user has been charged, show a different error.
            OWSActionSheets.showActionSheet(
                title: NSLocalizedString("BADGE_GIFTING_PAYMENT_FAILED_TITLE",
                                         comment: "Title for the action sheet when you try to send a gift badge but the payment failed"),
                message: NSLocalizedString("BADGE_GIFTING_PAYMENT_FAILED_BODY",
                                           comment: "Text in the action sheet when you try to send a gift badge but the payment failed. Tells the user that they have not been charged")
            )
            owsFailDebug("Failed to send gift: \(error)")
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
    }
}
