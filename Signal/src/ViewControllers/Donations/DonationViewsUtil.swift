//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import Foundation
import Lottie
import SignalMessaging
import SignalUI
import UIKit
import SafariServices

// MARK: - Profile badge lookup

public class ProfileBadgeLookup {
    let boostBadge: ProfileBadge?
    let giftBadge: ProfileBadge?
    let badgesBySubscriptionLevel: [UInt: ProfileBadge]

    public convenience init() {
        self.init(boostBadge: nil, giftBadge: nil, subscriptionLevels: [])
    }

    public init(boostBadge: ProfileBadge?, giftBadge: ProfileBadge?, subscriptionLevels: [SubscriptionLevel]) {
        self.boostBadge = boostBadge
        self.giftBadge = giftBadge

        var badgesBySubscriptionLevel = [UInt: ProfileBadge]()
        for subscriptionLevel in subscriptionLevels {
            badgesBySubscriptionLevel[subscriptionLevel.level] = subscriptionLevel.badge
        }
        self.badgesBySubscriptionLevel = badgesBySubscriptionLevel
    }

    private func get(donationReceipt: DonationReceipt) -> ProfileBadge? {
        switch donationReceipt.receiptType {
        case .boost: return boostBadge
        case .subscription(let subscriptionLevel): return badgesBySubscriptionLevel[subscriptionLevel]
        case .gift: return giftBadge
        }
    }

    public func getImage(donationReceipt: DonationReceipt, preferDarkTheme: Bool) -> UIImage? {
        guard let assets = get(donationReceipt: donationReceipt)?.assets else { return nil }
        return preferDarkTheme ? assets.dark16 : assets.light16
    }

    public func attemptToPopulateBadgeAssets(populateAssetsOnBadge: (ProfileBadge) -> Promise<Void>) -> Guarantee<Void> {
        var badgesToLoad = Array(badgesBySubscriptionLevel.values)
        if let boostBadge = boostBadge { badgesToLoad.append(boostBadge) }
        if let giftBadge = giftBadge { badgesToLoad.append(giftBadge) }

        let promises = badgesToLoad.map { populateAssetsOnBadge($0) }
        return Promise.when(fulfilled: promises).recover { _ in Guarantee.value(()) }
    }
}

// MARK: - Currency picker view

public class DonationCurrencyPickerButton: UIStackView {
    init(
        currentCurrencyCode: Currency.Code,
        hasLabel: Bool,
        block: @escaping () -> Void
    ) {
        super.init(frame: .zero)

        self.axis = .horizontal
        self.alignment = .center
        self.spacing = 8

        if hasLabel {
            let label = UILabel()
            label.font = .dynamicTypeBodyClamped
            label.textColor = Theme.primaryTextColor
            label.text = OWSLocalizedString(
                "DONATIONS_CURRENCY_PICKER_LABEL",
                comment: "Label for the currency picker button in donation views"
            )
            self.addArrangedSubview(label)
        }

        let picker = OWSButton(block: block)
        picker.setAttributedTitle(NSAttributedString.composed(of: [
            currentCurrencyCode,
            Special.noBreakSpace,
            NSAttributedString.with(
                image: UIImage(imageLiteralResourceName: "chevron-down-extra-small"),
                font: .regularFont(ofSize: 17)
            ).styled(
                with: .color(DonationViewsUtil.bubbleBorderColor)
            )
        ]).styled(
            with: .font(.regularFont(ofSize: 17)),
            .color(Theme.primaryTextColor)
        ), for: .normal)

        picker.setBackgroundImage(UIImage(color: DonationViewsUtil.bubbleBackgroundColor), for: .normal)
        picker.setBackgroundImage(UIImage(color: DonationViewsUtil.bubbleBackgroundColor.withAlphaComponent(0.8)), for: .highlighted)

        let pillView = PillView()
        pillView.layer.borderWidth = DonationViewsUtil.bubbleBorderWidth
        pillView.layer.borderColor = DonationViewsUtil.bubbleBorderColor.cgColor
        pillView.clipsToBounds = true
        pillView.addSubview(picker)
        picker.autoPinEdgesToSuperviewEdges()
        picker.autoSetDimension(.width, toSize: 74, relation: .greaterThanOrEqual)

        self.addArrangedSubview(pillView)
        pillView.autoSetDimension(.height, toSize: 36, relation: .greaterThanOrEqual)

        let leadingSpacer = UIView.hStretchingSpacer()
        let trailingSpacer = UIView.hStretchingSpacer()
        self.insertArrangedSubview(leadingSpacer, at: 0)
        self.addArrangedSubview(trailingSpacer)
        leadingSpacer.autoMatch(.width, to: .width, of: trailingSpacer)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Gift badge cell view

public class GiftBadgeCellView: UIStackView {
    init(badge: ProfileBadge, price: FiatMoney) {
        super.init(frame: .zero)

        self.axis = .horizontal
        self.spacing = 12
        self.alignment = .center

        let badgeImageView: UIView = {
            let badgeImage = badge.assets?.universal160
            return UIImageView(image: badgeImage)
        }()
        self.addArrangedSubview(badgeImageView)
        badgeImageView.autoSetDimensions(to: CGSize(square: 64))

        let titleLabel = UILabel()
        titleLabel.text = badge.localizedName
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = .dynamicTypeBody.semibold()
        titleLabel.numberOfLines = 0

        let secondLineLabel = UILabel()
        secondLineLabel.text = {
            let formattedPrice = DonationUtilities.format(money: price)

            let formattedDuration: String = {
                guard let duration = badge.duration else {
                    owsFailDebug("Gift badge had no duration but one was expected")
                    return ""
                }

                let durationFormatter = DateComponentsFormatter()
                durationFormatter.unitsStyle = .short
                durationFormatter.allowedUnits = [.day]
                guard let formattedDuration = durationFormatter.string(from: duration) else {
                    owsFailDebug("Could not format gift badge duration")
                    return ""
                }

                return formattedDuration
            }()
            let formattedDurationText = String(
                format: OWSLocalizedString(
                    "DONATION_FOR_A_FRIEND_ROW_DURATION",
                    comment: "When donating on behalf of a friend, a badge will be sent. This shows how long the badge lasts. Embeds {{formatted duration}}."
                ),
                formattedDuration
            )

            return String(
                format: OWSLocalizedString(
                    "JOINED_WITH_DOT",
                    comment: "Two strings, joined by a dot. Embeds {first} and {second}, which are on opposite sides of the dot"
                ),
                formattedPrice, formattedDurationText
            )
        }()
        secondLineLabel.textColor = Theme.primaryTextColor
        secondLineLabel.font = .dynamicTypeBody2
        secondLineLabel.numberOfLines = 0

        let vStackView = UIStackView(arrangedSubviews: [titleLabel, secondLineLabel])
        vStackView.axis = .vertical
        vStackView.distribution = .equalCentering
        vStackView.spacing = 4
        self.addArrangedSubview(vStackView)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Misc. utilities

public final class DonationViewsUtil {
    public static let bubbleBorderWidth: CGFloat = 1.5
    fileprivate static var bubbleBorderColor: UIColor { Theme.isDarkThemeEnabled ? UIColor.ows_gray65 : UIColor(rgbHex: 0xdedede) }
    public static var bubbleBackgroundColor: UIColor { Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white }

    public static func avatarView() -> ConversationAvatarView {
        let sizeClass = ConversationAvatarView.Configuration.SizeClass.eightyEight
        return ConversationAvatarView(sizeClass: sizeClass, localUserDisplayMode: .asUser)
    }

    /// Complete the monthly donation and allow for an optional onFinished block to be called with the
    /// result of the subscription.  Regardless of success or failure here, the pending donation is cleared
    /// since there isn't anything actionable for the user to do on failure other than try again with a new
    /// donation.
    public static func completeMonthlyDonations(
        subscriberId: Data,
        paymentType: SubscriptionManagerImpl.RecurringSubscriptionPaymentType,
        newSubscriptionLevel: SubscriptionLevel,
        priorSubscriptionLevel: SubscriptionLevel?,
        currencyCode: Currency.Code,
        databaseStorage: SDSDatabaseStorage,
        onFinished: ((Error?, ProfileBadge, DonationPaymentMethod) -> Void)? = nil
    ) -> Promise<Void> {
        let pendingStore = DependenciesBridge.shared.externalPendingIDEALDonationStore
        let badge = newSubscriptionLevel.badge
        let paymentMethod = paymentType.paymentMethod
        return firstly(on: DispatchQueue.sharedUserInitiated) {
            DonationViewsUtil.finalizeAndRedeemSubscription(
                subscriberId: subscriberId,
                paymentType: paymentType,
                newSubscriptionLevel: newSubscriptionLevel,
                priorSubscriptionLevel: priorSubscriptionLevel,
                currencyCode: currencyCode
            )
        }.done(on: DispatchQueue.main) {
            onFinished?(nil, badge, paymentMethod)
        }.catch(on: DispatchQueue.main) { error in
            onFinished?(error, badge, paymentMethod)
        }.ensure {
            databaseStorage.write { tx in
                pendingStore.clearPendingSubscription(tx: tx.asV2Write)
            }
        }
    }

    /// Complete the one-time donation and allow for an optional onFinished
    /// block to be called with the result of the transaction.
    public static func completeOneTimeDonation(
        paymentIntentId: String,
        amount: FiatMoney,
        paymentMethod: DonationPaymentMethod,
        databaseStorage: SDSDatabaseStorage,
        onFinished: ((Error?, ProfileBadge?, DonationPaymentMethod) -> Void)? = nil
    ) -> Promise<Void> {
        let pendingStore = DependenciesBridge.shared.externalPendingIDEALDonationStore
        var badge: ProfileBadge?

        return firstly(on: DispatchQueue.sharedUserInitiated) {
            // Fetch the badge so it's available for the onFinished callback.
            SubscriptionManagerImpl.getCachedBadge(level: .boostBadge)
                .fetchIfNeeded()
                .map(on: DispatchQueue.main) { result in
                    switch result {
                    case .notFound:
                        badge = nil
                    case let .profileBadge(profileBadge):
                        badge = profileBadge
                    }
                }
                .then(on: DispatchQueue.main) {
                    DonationViewsUtil.createAndRedeemOneTimeDonation(
                        paymentIntentId: paymentIntentId,
                        amount: amount,
                        paymentMethod: paymentMethod
                    )
                }
        }
        .ensure {
            databaseStorage.write { tx in
                pendingStore.clearPendingOneTimeDonation(tx: tx.asV2Write)
            }
        }
        .done {
            onFinished?(nil, badge, paymentMethod)
        }.catch { error in
            onFinished?(error, badge, paymentMethod)
        }
    }

    public static func createAndRedeemOneTimeDonation(
        paymentIntentId: String,
        amount: FiatMoney,
        paymentMethod: DonationPaymentMethod
    ) -> Promise<Void> {
        let redemptionJob = SubscriptionManagerImpl.requestAndRedeemReceipt(
            boostPaymentIntentId: paymentIntentId,
            amount: amount,
            paymentProcessor: .stripe,
            paymentMethod: paymentMethod
        )
        return DonationViewsUtil.waitForRedemptionJob(redemptionJob, paymentMethod: paymentMethod)
    }

    public static func finalizeAndRedeemSubscription(
        subscriberId: Data,
        paymentType: SubscriptionManagerImpl.RecurringSubscriptionPaymentType,
        newSubscriptionLevel: SubscriptionLevel,
        priorSubscriptionLevel: SubscriptionLevel?,
        currencyCode: Currency.Code
    ) -> Promise<Void> {
        firstly(on: DispatchQueue.sharedUserInitiated) { () -> Promise<Subscription> in
            Logger.info("[Donations] Finalizing new subscription")

            return SubscriptionManagerImpl.finalizeNewSubscription(
                forSubscriberId: subscriberId,
                paymentType: paymentType,
                subscription: newSubscriptionLevel,
                currencyCode: currencyCode
            )
        }.then(on: DispatchQueue.sharedUserInitiated) { _ in
            Logger.info("[Donations] Redeeming monthly receipts")

            let redemptionJob = SubscriptionManagerImpl.requestAndRedeemReceipt(
                subscriberId: subscriberId,
                subscriptionLevel: newSubscriptionLevel.level,
                priorSubscriptionLevel: priorSubscriptionLevel?.level,
                paymentProcessor: paymentType.paymentProcessor,
                paymentMethod: paymentType.paymentMethod,
                isNewSubscription: true,
                shouldSuppressPaymentAlreadyRedeemed: false
            )
            return DonationViewsUtil.waitForRedemptionJob(redemptionJob, paymentMethod: paymentType.paymentMethod)
        }
    }

    public static func loadSubscriptionLevels(badgeStore: BadgeStore) -> Promise<[SubscriptionLevel]> {
        firstly { () -> Promise<SubscriptionManagerImpl.DonationConfiguration> in
            SubscriptionManagerImpl.fetchDonationConfiguration()
        }.map { donationConfiguration -> [SubscriptionLevel] in
            donationConfiguration.subscription.levels
        }.then { (fetchedSubscriptions: [SubscriptionLevel]) -> Promise<[SubscriptionLevel]> in
            let badgeUpdatePromises = fetchedSubscriptions.map { badgeStore.populateAssetsOnBadge($0.badge) }
            return Promise.when(fulfilled: badgeUpdatePromises).map { fetchedSubscriptions }
        }
    }

    public static func loadCurrentSubscription(subscriberID: Data?) -> Promise<Subscription?> {
        if let subscriberID = subscriberID {
            return SubscriptionManagerImpl.getCurrentSubscriptionStatus(for: subscriberID)
        } else {
            return Promise.value(nil)
        }
    }

    public static func subscriptionLevelForSubscription(subscriptionLevels: [SubscriptionLevel],
                                                        subscription: Subscription) -> SubscriptionLevel? {
        subscriptionLevels.first { $0.level == subscription.level }
    }

    public static func openDonateWebsite() {
        UIApplication.shared.open(TSConstants.donateUrl, options: [:], completionHandler: nil)
    }

    public static func nonBankPaymentStillProcessingActionSheet() -> ActionSheetController {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SUSTAINER_STILL_PROCESSING_BADGE_TITLE",
                comment: "Action sheet title for Still Processing Badge sheet"
            ),
            message: OWSLocalizedString(
                "SUSTAINER_VIEW_STILL_PROCESSING_BADGE_MESSAGE",
                comment: "Action sheet message for Still Processing Badge sheet"
            )
        )
        actionSheet.addAction(OWSActionSheets.okayAction)

        return actionSheet
    }

    static func completeIDEALDonation(
        donationType: Stripe.IDEALCallbackType,
        databaseStorage: SDSDatabaseStorage,
        onFinished: ((Error?, ProfileBadge?, DonationPaymentMethod) -> Void)?
    ) -> Promise<Void> {
        let paymentStore = DependenciesBridge.shared.externalPendingIDEALDonationStore
        switch donationType {
        case let .monthly(success, clientSecret, intentId):
            guard let monthlyDonation = databaseStorage.read(block: { tx in
                paymentStore.getPendingSubscription(tx: tx.asV2Read)
            }) else {
                Logger.error("[Donations] Could not find iDEAL subscription to complete")
                return Promise.init(error: OWSUnretryableError())
            }
            guard
                clientSecret == monthlyDonation.clientSecret,
                intentId == monthlyDonation.setupIntentId
            else {
                owsFailDebug("[Donations] Pending iDEAL subscription details do not match")
                return Promise.init(error: OWSUnretryableError())
            }
            guard success else {
                return Promise.init(error: OWSUnretryableError())
            }

            return firstly(on: DispatchQueue.global()) {
                OWSProfileManager.shared.badgeStore.populateAssetsOnBadge(
                    monthlyDonation.newSubscriptionLevel.badge
                )
                .then(on: DispatchQueue.global()) {
                    DonationViewsUtil.completeMonthlyDonations(
                        subscriberId: monthlyDonation.subscriberId,
                        paymentType: .ideal(setupIntentId: monthlyDonation.setupIntentId),
                        newSubscriptionLevel: monthlyDonation.newSubscriptionLevel,
                        priorSubscriptionLevel: monthlyDonation.oldSubscriptionLevel,
                        currencyCode: monthlyDonation.amount.currencyCode,
                        databaseStorage: databaseStorage,
                        onFinished: onFinished
                    )
                }
            }
        case let .oneTime(success, intentId):
            guard let oneTimePayment = databaseStorage.read(block: { tx in
                paymentStore.getPendingOneTimeDonation(tx: tx.asV2Read)
            }) else {
                Logger.error("[Donations] Could not find iDEAL payment to complete")
                return Promise.init(error: OWSUnretryableError())
            }
            guard intentId == oneTimePayment.paymentIntentId else {
                owsFailDebug("[Donations] Could not find iDEAL subscription to complete")
                return Promise.init(error: OWSUnretryableError())
            }
            guard success else {
                return Promise.init(error: OWSUnretryableError())
            }

            return firstly(on: DispatchQueue.global()) {
                DonationViewsUtil.completeOneTimeDonation(
                    paymentIntentId: oneTimePayment.paymentIntentId,
                    amount: oneTimePayment.amount,
                    paymentMethod: .ideal,
                    databaseStorage: databaseStorage,
                    onFinished: onFinished
                )
            }
        }
    }

    static func presentErrorSheet(
        from viewController: UIViewController,
        error: Error,
        mode donateMode: DonateViewController.DonateMode,
        badge: ProfileBadge,
        paymentMethod: DonationPaymentMethod?
    ) {
        if let donationJobError = error as? DonationJobError {
            switch donationJobError {
            case .timeout:
                DonationViewsUtil.presentStillProcessingSheet(
                    from: viewController,
                    badge: badge,
                    paymentMethod: paymentMethod,
                    donateMode: donateMode
                )
            case .assertion:
                DonationViewsUtil.presentBadgeCantBeAddedSheet(
                    from: viewController,
                    donateMode: donateMode
                )
            }
        } else if let stripeError = error as? Stripe.StripeError {
            DonationViewsUtil.presentDonationErrorSheet(
                from: viewController,
                forDonationChargeErrorCode: stripeError.code,
                using: paymentMethod
            )
        } else {
            presentBadgeCantBeAddedSheet(
                from: viewController,
                donateMode: donateMode
            )
        }
    }

    static private func presentDonationErrorSheet(
        from viewController: UIViewController,
        forDonationChargeErrorCode chargeErrorCode: String,
        using paymentMethod: DonationPaymentMethod?
    ) {
        let errorSheetDetails = DonationViewsUtil.localizedDonationFailure(
            chargeErrorCode: chargeErrorCode,
            paymentMethod: paymentMethod
        )
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SUSTAINER_VIEW_ERROR_PROCESSING_PAYMENT_TITLE",
                comment: "Action sheet title for Error Processing Payment sheet"
            ),
            message: errorSheetDetails.message
        )

        actionSheet.addAction(.init(title: CommonStrings.okButton, style: .cancel, handler: nil))

        switch errorSheetDetails.actions {
        case .dismiss:
            break // No other actions needed
        case .learnMore(let learnMoreUrl):
            actionSheet.addAction(.init(title: CommonStrings.learnMore, style: .default) { _ in
                let vc = SFSafariViewController(url: learnMoreUrl)
                viewController.present(vc, animated: true, completion: nil)
            })
        }

        viewController.presentActionSheet(actionSheet)
    }

    static private func presentStillProcessingSheet(
        from viewController: UIViewController,
        badge: ProfileBadge,
        paymentMethod: DonationPaymentMethod?,
        donateMode: DonateViewController.DonateMode
    ) {
        switch paymentMethod {
        case nil, .applePay, .creditOrDebitCard, .paypal:
            viewController.presentActionSheet(
                DonationViewsUtil.nonBankPaymentStillProcessingActionSheet()
            )
        case .sepa, .ideal:
            let badgeIssueSheetMode: BadgeIssueSheetState.Mode = {
                switch donateMode {
                case .oneTime:
                    return .boostBankPaymentProcessing
                case .monthly:
                    return .subscriptionBankPaymentProcessing
                }
            }()

            viewController.present(
                BadgeIssueSheet(
                    badge: badge,
                    mode: badgeIssueSheetMode
                ),
                animated: true
            )
        }
    }

    static private func presentBadgeCantBeAddedSheet(
        from viewController: UIViewController,
        donateMode: DonateViewController.DonateMode
    ) {
        let receiptCredentialRequestError = SDSDatabaseStorage.shared.read { tx -> ReceiptCredentialRequestError? in
            let resultStore = DependenciesBridge.shared.receiptCredentialResultStore

            switch donateMode {
            case .oneTime:
                return resultStore.getRequestError(errorMode: .oneTimeBoost, tx: tx.asV2Read)
            case .monthly:
                // All subscriptions from this controller are being initiated.
                return resultStore.getRequestError(errorMode: .recurringSubscriptionInitiation, tx: tx.asV2Read)
            }
        }

        let title: String = {
            switch receiptCredentialRequestError?.errorCode {
            case .paymentFailed:
                return OWSLocalizedString("SUSTAINER_VIEW_ERROR_PROCESSING_PAYMENT_TITLE", comment: "Action sheet title for Error Processing Payment sheet")
            default:
                return OWSLocalizedString("SUSTAINER_VIEW_CANT_ADD_BADGE_TITLE", comment: "Action sheet title for Couldn't Add Badge sheet")
            }
        }()
        let message = OWSLocalizedString("SUSTAINER_VIEW_CANT_ADD_BADGE_MESSAGE", comment: "Action sheet message for Couldn't Add Badge sheet")

        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("CONTACT_SUPPORT", comment: "Button text to initiate an email to signal support staff"),
            style: .default,
            handler: { _ in
                let localizedSheetTitle = OWSLocalizedString("EMAIL_SIGNAL_TITLE",
                                                            comment: "Title for the fallback support sheet if user cannot send email")
                let localizedSheetMessage = OWSLocalizedString("EMAIL_SIGNAL_MESSAGE",
                                                              comment: "Description for the fallback support sheet if user cannot send email")
                guard ComposeSupportEmailOperation.canSendEmails else {
                    let fallbackSheet = ActionSheetController(title: localizedSheetTitle,
                                                              message: localizedSheetMessage)
                    let buttonTitle = OWSLocalizedString("BUTTON_OKAY", comment: "Label for the 'okay' button.")
                    fallbackSheet.addAction(ActionSheetAction(title: buttonTitle, style: .default))
                    viewController.presentActionSheet(fallbackSheet)
                    return
                }
                let supportVC = ContactSupportViewController()
                supportVC.selectedFilter = .donationsAndBadges
                let navVC = OWSNavigationController(rootViewController: supportVC)
                viewController.presentFormSheet(navVC, animated: true)
            }
        ))

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("SUSTAINER_VIEW_SUBSCRIPTION_CONFIRMATION_NOT_NOW", comment: "Sustainer view Not Now Action sheet button"),
            style: .cancel,
            handler: nil
        ))
        viewController.presentActionSheet(actionSheet)
    }
}
