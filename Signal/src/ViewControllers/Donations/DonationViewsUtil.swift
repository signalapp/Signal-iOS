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
}

/// Not the best place for this to live, but at the time of writing I wanted to
/// minimize the diff (these methods lived here before) while restricting these
/// methods to ``DonateViewController``.
extension DonateViewController {
   func presentErrorSheet(
        error: Error,
        mode donateMode: DonateMode,
        badge: ProfileBadge,
        paymentMethod: DonationPaymentMethod?
    ) {
        if let donationJobError = error as? DonationJobError {
            switch donationJobError {
            case .timeout:
                presentStillProcessingSheet(
                    badge: badge,
                    paymentMethod: paymentMethod,
                    donateMode: donateMode
                )
            case .assertion:
                presentBadgeCantBeAddedSheet(donateMode: donateMode)
            }
        } else if let stripeError = error as? Stripe.StripeError {
            presentDonationErrorSheet(
                forDonationChargeErrorCode: stripeError.code,
                using: paymentMethod
            )
        } else {
            presentBadgeCantBeAddedSheet(donateMode: donateMode)
        }
    }

    private func presentDonationErrorSheet(
        forDonationChargeErrorCode chargeErrorCode: String,
        using paymentMethod: DonationPaymentMethod?
    ) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SUSTAINER_VIEW_ERROR_PROCESSING_PAYMENT_TITLE",
                comment: "Action sheet title for Error Processing Payment sheet"
            ),
            message: DonationViewsUtil.localizedDonationFailure(
                chargeErrorCode: chargeErrorCode,
                paymentMethod: paymentMethod
            )
        )

        actionSheet.addAction(.init(title: CommonStrings.okayButton, style: .cancel, handler: nil))

        self.presentActionSheet(actionSheet)
    }

    private func presentStillProcessingSheet(
        badge: ProfileBadge,
        paymentMethod: DonationPaymentMethod?,
        donateMode: DonateMode
    ) {
        switch paymentMethod {
        case nil, .applePay, .creditOrDebitCard, .paypal:
            self.presentActionSheet(
                DonationViewsUtil.nonBankPaymentStillProcessingActionSheet()
            )
        case .sepa:
            let badgeIssueSheetMode: BadgeIssueSheetState.Mode = {
                switch donateMode {
                case .oneTime:
                    return .boostBankPaymentProcessing
                case .monthly:
                    return .subscriptionBankPaymentProcessing
                }
            }()

            self.present(
                BadgeIssueSheet(
                    badge: badge,
                    mode: badgeIssueSheetMode
                ),
                animated: true
            )
        }
    }

    private func presentBadgeCantBeAddedSheet(donateMode: DonateMode) {
        let receiptCredentialRequestError = SDSDatabaseStorage.shared.read { tx -> SubscriptionReceiptCredentialRequestError? in
            let resultStore = DependenciesBridge.shared.subscriptionReceiptCredentialResultStore

            switch donateMode {
            case .oneTime:
                return resultStore.getRequestError(errorMode: .oneTimeBoost, tx: tx.asV2Read)
            case .monthly:
                return resultStore.getRequestError(errorMode: .recurringSubscription, tx: tx.asV2Read)
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
                    self.presentActionSheet(fallbackSheet)
                    return
                }
                let supportVC = ContactSupportViewController()
                supportVC.selectedFilter = .donationsAndBadges
                let navVC = OWSNavigationController(rootViewController: supportVC)
                self.presentFormSheet(navVC, animated: true)
            }
        ))

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("SUSTAINER_VIEW_SUBSCRIPTION_CONFIRMATION_NOT_NOW", comment: "Sustainer view Not Now Action sheet button"),
            style: .cancel,
            handler: nil
        ))
        self.presentActionSheet(actionSheet)
    }
}
