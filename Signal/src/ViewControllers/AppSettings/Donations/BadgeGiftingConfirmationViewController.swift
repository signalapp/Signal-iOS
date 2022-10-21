//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit
import SignalMessaging
import SignalServiceKit
import UIKit

class BadgeGiftingConfirmationViewController: OWSTableViewController2 {
    // MARK: - View state

    private let badge: ProfileBadge
    private let price: Decimal
    private let currencyCode: Currency.Code
    private let thread: TSContactThread

    public init(
        badge: ProfileBadge,
        price: Decimal,
        currencyCode: Currency.Code,
        thread: TSContactThread
    ) {
        self.badge = badge
        self.price = price
        self.currencyCode = currencyCode
        self.thread = thread
    }

    private class func showRecipientIsBlockedError() {
        OWSActionSheets.showActionSheet(title: NSLocalizedString("BADGE_GIFTING_ERROR_RECIPIENT_IS_BLOCKED_TITLE",
                                                                 comment: "Title for error message dialog indicating that the person you're trying to send to has been blocked."),
                                        message: NSLocalizedString("BADGE_GIFTING_ERROR_RECIPIENT_IS_BLOCKED_BODY",
                                                                   comment: "Error message indicating that the person you're trying to send has been blocked."))
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

    private func isRecipientBlocked(transaction: SDSAnyReadTransaction) -> Bool {
        self.blockingManager.isAddressBlocked(self.thread.contactAddress, transaction: transaction)
    }

    private func isRecipientBlockedWithSneakyTransaction() -> Bool {
        databaseStorage.read { self.isRecipientBlocked(transaction: $0) }
    }

    /// Queries the database to see if the recipient can receive gift badges.
    private func canReceiveGiftBadgesViaDatabase() -> Bool {
        databaseStorage.read { transaction -> Bool in
            self.profileManager.getUserProfile(for: self.thread.contactAddress, transaction: transaction)?.canReceiveGiftBadges ?? false
        }
    }

    enum ProfileFetchError: Error { case timeout }

    /// Fetches the recipient's profile, then queries the database to see if they can receive gift badges.
    /// Times out after 30 seconds.
    private func canReceiveGiftBadgesViaProfileFetch() -> Promise<Bool> {
        firstly {
            profileManager.fetchProfile(forAddressPromise: self.thread.contactAddress)
        }.timeout(seconds: 30) {
            ProfileFetchError.timeout
        }.map { [weak self] _ in
            self?.canReceiveGiftBadgesViaDatabase() ?? false
        }
    }

    /// Look up whether the recipient can receive gift badges.
    /// If the operation takes more half a second, we show a spinner.
    /// We first consult the database.
    /// If they are capable there, we don't need to fetch their profile.
    /// If they aren't (or we have no profile saved), we fetch the profile because we might have stale data.
    private func canReceiveGiftBadgesWithUi() -> Promise<Bool> {
        if canReceiveGiftBadgesViaDatabase() {
            return Promise.value(true)
        }

        let (resultPromise, resultFuture) = Promise<Bool>.pending()

        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false,
                                                     presentationDelay: 0.5) { modal in
            firstly {
                self.canReceiveGiftBadgesViaProfileFetch()
            }.done(on: .main) { canReceiveGiftBadges in
                modal.dismiss { resultFuture.resolve(canReceiveGiftBadges) }
            }.catch(on: .main) { error in
                modal.dismiss { resultFuture.reject(error) }
            }
        }

        return resultPromise
    }

    private enum SafetyNumberConfirmationResult {
        case userDidNotConfirmSafetyNumberChange
        case userConfirmedSafetyNumberChangeOrNoChangeWasNeeded
    }

    private func showSafetyNumberConfirmationIfNecessary() -> (needsUserInteraction: Bool, promise: Promise<SafetyNumberConfirmationResult>) {
        let (promise, future) = Promise<SafetyNumberConfirmationResult>.pending()

        let needsUserInteraction = SafetyNumberConfirmationSheet.presentIfNecessary(address: thread.contactAddress,
                                                                                    confirmationText: SafetyNumberStrings.confirmSendButton) { didConfirm in
            future.resolve(didConfirm ? .userConfirmedSafetyNumberChangeOrNoChangeWasNeeded : .userDidNotConfirmSafetyNumberChange)
        }
        if needsUserInteraction {
            Logger.info("[Gifting] Showing safety number confirmation sheet")
        } else {
            Logger.info("[Gifting] Not showing safety number confirmation sheet; it was not needed")
            future.resolve(.userConfirmedSafetyNumberChangeOrNoChangeWasNeeded)
        }

        return (needsUserInteraction: needsUserInteraction, promise: promise)
    }

    @objc
    private func checkRecipientAndRequestApplePay() {
        // We want to resign this SOMETIME before this VC dismisses and switches to the chat.
        // In addition to offering slightly better UX, resigning first responder status prevents it
        // from eating events after the VC is dismissed.
        messageTextView.resignFirstResponder()

        guard !isRecipientBlockedWithSneakyTransaction() else {
            Logger.warn("[Gifting] Not requesting Apple Pay because recipient is blocked")
            Self.showRecipientIsBlockedError()
            return
        }

        firstly(on: .main) { [weak self] () -> Promise<Bool> in
            guard let self = self else {
                throw SendGiftBadgeError.userCanceledBeforeChargeCompleted
            }
            return self.canReceiveGiftBadgesWithUi()
        }.then(on: .main) { [weak self] canReceiveGiftBadges -> Promise<SafetyNumberConfirmationResult> in
            guard let self = self else {
                throw SendGiftBadgeError.userCanceledBeforeChargeCompleted
            }
            guard canReceiveGiftBadges else {
                throw SendGiftBadgeError.cannotReceiveGiftBadges
            }
            return self.showSafetyNumberConfirmationIfNecessary().promise
        }.done(on: .main) { [weak self] safetyNumberConfirmationResult in
            guard let self = self else {
                throw SendGiftBadgeError.userCanceledBeforeChargeCompleted
            }

            switch safetyNumberConfirmationResult {
            case .userDidNotConfirmSafetyNumberChange:
                throw SendGiftBadgeError.userCanceledBeforeChargeCompleted
            case .userConfirmedSafetyNumberChangeOrNoChangeWasNeeded:
                break
            }

            Logger.info("[Gifting] Requesting Apple Pay...")

            let request = DonationUtilities.newPaymentRequest(
                for: self.price,
                currencyCode: self.currencyCode,
                isRecurring: false
            )

            let paymentController = PKPaymentAuthorizationController(paymentRequest: request)
            paymentController.delegate = self
            paymentController.present { presented in
                if !presented {
                    // This can happen under normal conditions if the user double-taps the button,
                    // but may also indicate a problem.
                    Logger.warn("[Gifting] Failed to present payment controller")
                }
            }
        }.catch { error in
            if let error = error as? SendGiftBadgeError {
                Logger.warn("[Gifting] Error \(error)")
                switch error {
                case .userCanceledBeforeChargeCompleted:
                    return
                case .cannotReceiveGiftBadges:
                    OWSActionSheets.showActionSheet(
                        title: NSLocalizedString(
                            "BADGE_GIFTING_ERROR_RECIPIENT_CANNOT_RECEIVE_GIFT_BADGES_TITLE",
                            comment: "Title for error message dialog indicating that a user can't receive gifts."
                        ),
                        message: NSLocalizedString(
                            "BADGE_GIFTING_ERROR_RECIPIENT_CANNOT_RECEIVE_GIFT_BADGES_BODY",
                            comment: "Error message indicating that a user can't receive gifts."
                        )
                    )
                    return
                default:
                    break
                }
            }

            owsFailDebugUnlessNetworkFailure(error)
            OWSActionSheets.showActionSheet(title: NSLocalizedString("BADGE_GIFTING_CANNOT_SEND_TO_RECIPIENT_GENERIC_ERROR_TITLE",
                                                                     comment: "Title for error message dialog indicating that you can't send the gift badge for some reason."),
                                            message: NSLocalizedString("BADGE_GIFTING_CANNOT_SEND_TO_RECIPIENT_GENERIC_ERROR_BODY",
                                                                       comment: "Error message indicating that you can't send the gift badge for some reason."))
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
        view.returnKeyType = .done
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
        bottomFooterStackView.layoutMargins = UIEdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16)
        bottomFooterStackView.removeAllSubviews()

        let amountView: UIStackView = {
            let descriptionLabel = UILabel()
            descriptionLabel.text = NSLocalizedString("BADGE_GIFTING_PAYMENT_DESCRIPTION",
                                                      comment: "Text telling the user that their gift is a one-time donation")
            descriptionLabel.font = .ows_dynamicTypeBody
            descriptionLabel.numberOfLines = 0

            let priceLabel = UILabel()
            priceLabel.text = DonationUtilities.formatCurrency(price, currencyCode: currencyCode)
            priceLabel.font = .ows_dynamicTypeBody.ows_semibold
            priceLabel.numberOfLines = 0

            let view = UIStackView(arrangedSubviews: [descriptionLabel, priceLabel])
            view.axis = .horizontal
            view.distribution = .equalSpacing
            view.layoutMargins = cellOuterInsets
            view.isLayoutMarginsRelativeArrangement = true

            return view
        }()

        let applePayButton = ApplePayButton { [weak self] in
            self?.checkRecipientAndRequestApplePay()
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
                  replacementText text: String) -> Bool {
        if text == "\n" {
            uiTextView.resignFirstResponder()
        }
        return true
    }
}

// MARK: - Apple Pay delegate

extension BadgeGiftingConfirmationViewController: PKPaymentAuthorizationControllerDelegate {
    private struct PreparedPayment {
        let paymentIntent: Stripe.PaymentIntent
        let paymentMethodId: String
    }

    enum SendGiftBadgeError: Error {
        case recipientIsBlocked
        case failedAndUserNotCharged
        case failedAndUserMaybeCharged
        case cannotReceiveGiftBadges
        case userCanceledBeforeChargeCompleted
    }

    private func prepareToPay(authorizedPayment: PKPayment) -> Promise<PreparedPayment> {
        firstly {
            Stripe.createBoostPaymentIntent(
                for: self.price,
                in: self.currencyCode,
                level: .giftBadge(.signalGift)
            )
        }.then { paymentIntent in
            Stripe.createPaymentMethod(with: authorizedPayment).map { paymentMethodId in
                PreparedPayment(paymentIntent: paymentIntent, paymentMethodId: paymentMethodId)
            }
        }
    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        var hasCalledCompletion = false
        func wrappedCompletion(_ result: PKPaymentAuthorizationResult) {
            guard !hasCalledCompletion else { return }
            hasCalledCompletion = true
            completion(result)
        }

        firstly(on: .global()) { () -> Promise<PreparedPayment> in
            // Bail if the user is already sending a gift to this person. This unusual case can happen if:
            //
            // 1. The user enqueues a "send gift badge" job for this recipient
            // 2. The app is terminated (e.g., due to a crash)
            // 3. Before the job finishes, the user restarts the app and tries to gift another badge to the same person
            //
            // This *could* happen without a Signal developer making a mistake, if the app is terminated at the right time.
            let isAlreadyGifting = self.databaseStorage.read {
                DonationUtilities.sendGiftBadgeJobQueue.alreadyHasJob(for: self.thread, transaction: $0)
            }
            guard !isAlreadyGifting else {
                Logger.warn("Already sending a gift to this recipient")
                throw SendGiftBadgeError.failedAndUserNotCharged
            }

            // Prepare to pay. We haven't charged the user yet, so we don't need to do anything durably,
            // e.g. a job.
            return firstly { () -> Promise<PreparedPayment> in
                self.prepareToPay(authorizedPayment: payment)
            }.timeout(seconds: 30) {
                Logger.warn("Timed out after preparing gift badge payment")
                return SendGiftBadgeError.failedAndUserNotCharged
            }.recover(on: .global()) { error -> Promise<PreparedPayment> in
                if !(error is SendGiftBadgeError) { owsFailDebugUnlessNetworkFailure(error) }
                throw SendGiftBadgeError.failedAndUserNotCharged
            }
        }.then { [weak self] preparedPayment -> Promise<PreparedPayment> in
            guard let self = self else { throw SendGiftBadgeError.userCanceledBeforeChargeCompleted }

            let safetyNumberConfirmationResult = self.showSafetyNumberConfirmationIfNecessary()
            if safetyNumberConfirmationResult.needsUserInteraction {
                wrappedCompletion(.init(status: .success, errors: nil))
            }

            return safetyNumberConfirmationResult.promise.map { safetyNumberConfirmationResult in
                switch safetyNumberConfirmationResult {
                case .userDidNotConfirmSafetyNumberChange:
                    throw SendGiftBadgeError.userCanceledBeforeChargeCompleted
                case .userConfirmedSafetyNumberChangeOrNoChangeWasNeeded:
                    return preparedPayment
                }
            }
        }.then { [weak self] preparedPayment -> Promise<Void> in
            guard let self = self else { throw SendGiftBadgeError.userCanceledBeforeChargeCompleted }

            // Durably enqueue a job to (1) do the charge (2) redeem the receipt credential (3) enqueue
            // a gift badge message (and optionally a text message) to the recipient. We also want to
            // update the UI partway through the job's execution, and when it completes.
            let jobRecord = SendGiftBadgeJobQueue.createJob(receiptRequest: try SubscriptionManager.generateReceiptRequest(),
                                                            amount: self.price,
                                                            currencyCode: self.currencyCode,
                                                            paymentIntent: preparedPayment.paymentIntent,
                                                            paymentMethodId: preparedPayment.paymentMethodId,
                                                            thread: self.thread,
                                                            messageText: self.messageText)
            let jobId = jobRecord.uniqueId

            let (promise, future) = Promise<Void>.pending()

            var modalActivityIndicatorViewController: ModalActivityIndicatorViewController?
            var shouldDismissActivityIndicator = false
            func presentModalActivityIndicatorIfNotAlreadyPresented() {
                guard modalActivityIndicatorViewController == nil else { return }
                ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modal in
                    DispatchQueue.main.async {
                        modalActivityIndicatorViewController = modal
                        // Depending on how things are dispatched, we could need the modal closed immediately.
                        if shouldDismissActivityIndicator {
                            modal.dismiss {}
                        }
                    }
                }
            }

            // This is unusual, but can happen if the Apple Pay sheet was dismissed earlier in the process,
            // which can happen if the user needed to confirm a safety number change.
            if hasCalledCompletion {
                presentModalActivityIndicatorIfNotAlreadyPresented()
            }

            var hasCharged = false

            // The happy path is two steps: payment method is charged (showing a spinner), then job finishes (opening the chat).
            //
            // The valid sad paths are:
            // 1. We started charging the card but we don't know whether it succeeded before the job failed
            // 2. The card is "definitively" charged, but then the job fails
            //
            // There are some invalid sad paths that we try to handle, but those indicate Signal bugs.
            let observer = NotificationCenter.default.addObserver(forName: SendGiftBadgeJobQueue.JobEventNotification,
                                                                  object: nil,
                                                                  queue: .main) { notification in
                guard let userInfo = notification.userInfo,
                      let notificationJobId = userInfo["jobId"] as? String,
                      let rawJobEvent = userInfo["jobEvent"] as? Int,
                      let jobEvent = SendGiftBadgeJobQueue.JobEvent(rawValue: rawJobEvent) else {
                    owsFail("Received a gift badge job event with invalid user data")
                }
                guard notificationJobId == jobId else {
                    // This can happen if:
                    //
                    // 1. The user enqueues a "send gift badge" job
                    // 2. The app terminates before it can complete (e.g., due to a crash)
                    // 3. Before the job finishes, the user restarts the app and tries to gift another badge
                    //
                    // This is unusual and may indicate a bug, so we log, but we don't error/crash because it can happen under "normal" circumstances.
                    Logger.warn("Received an event for a different badge gifting job.")
                    return
                }

                switch jobEvent {
                case .jobFailed:
                    future.reject(SendGiftBadgeError.failedAndUserMaybeCharged)
                case .chargeSucceeded:
                    guard !hasCharged else {
                        // This job event can be emitted twice if the job fails (e.g., due to network) after the payment method is charged, and then it's restarted.
                        // That's unusual, but isn't necessarily a bug.
                        Logger.warn("Received a \"charge succeeded\" event more than once")
                        break
                    }
                    hasCharged = true
                    wrappedCompletion(.init(status: .success, errors: nil))
                    controller.dismiss()
                    presentModalActivityIndicatorIfNotAlreadyPresented()
                case .jobSucceeded:
                    future.resolve(())
                }
            }

            try self.databaseStorage.write { transaction in
                // We should already have checked this earlier, but it's possible that the state has changed on another device.
                // We'll also check this inside the job before running it.
                guard !self.isRecipientBlocked(transaction: transaction) else {
                    throw SendGiftBadgeError.recipientIsBlocked
                }

                // If we've gotten this far, we want to snooze the megaphone.
                ExperienceUpgradeManager.snoozeExperienceUpgrade(.subscriptionMegaphone,
                                                                 transaction: transaction.unwrapGrdbWrite)

                DonationUtilities.sendGiftBadgeJobQueue.addJob(jobRecord, transaction: transaction)
            }

            func finish() {
                NotificationCenter.default.removeObserver(observer)
                if let modalActivityIndicatorViewController = modalActivityIndicatorViewController {
                    modalActivityIndicatorViewController.dismiss {}
                } else {
                    shouldDismissActivityIndicator = true
                }
            }

            return promise.done(on: .main) {
                owsAssertDebug(hasCharged, "Expected \"charge succeeded\" event")
                finish()
            }.recover(on: .main) { error in
                finish()
                throw error
            }
        }.done { [weak self] in
            // We shouldn't need to dismiss the Apple Pay sheet here, but if the `chargeSucceeded` event was missed, we do our best.
            wrappedCompletion(.init(status: .success, errors: nil))
            guard let self = self else { return }
            SignalApp.shared().presentConversation(for: self.thread, action: .none, animated: false)
            self.dismiss(animated: true) {
                SignalApp.shared().conversationSplitViewControllerForSwift?.present(
                    BadgeGiftingThanksSheet(thread: self.thread, badge: self.badge),
                    animated: true
                )
            }
        }.catch { error in
            guard let error = error as? SendGiftBadgeError else {
                owsFail("\(error)")
            }

            wrappedCompletion(.init(status: .failure, errors: [error]))

            switch error {
            case .userCanceledBeforeChargeCompleted:
                break
            case .recipientIsBlocked:
                Self.showRecipientIsBlockedError()
            case .failedAndUserNotCharged, .cannotReceiveGiftBadges:
                OWSActionSheets.showActionSheet(title: NSLocalizedString("BADGE_GIFTING_PAYMENT_FAILED_TITLE",
                                                                         comment: "Title for the action sheet when you try to send a gift badge but the payment failed"),
                                                message: NSLocalizedString("BADGE_GIFTING_PAYMENT_FAILED_BODY",
                                                                           comment: "Text in the action sheet when you try to send a gift badge but the payment failed. Tells the user that they have not been charged"))
            case .failedAndUserMaybeCharged:
                OWSActionSheets.showActionSheet(title: NSLocalizedString("BADGE_GIFTING_PAYMENT_SUCCEEDED_BUT_GIFTING_FAILED_TITLE",
                                                                         comment: "Title for the action sheet when you try to send a gift badge. They were charged but the badge could not be sent. They should contact support."),
                                                message: NSLocalizedString("BADGE_GIFTING_PAYMENT_SUCCEEDED_BUT_GIFTING_FAILED_BODY",
                                                                           comment: "Text in the action sheet when you try to send a gift badge. They were charged but the badge could not be sent. They should contact support."))
            }
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
    }
}
