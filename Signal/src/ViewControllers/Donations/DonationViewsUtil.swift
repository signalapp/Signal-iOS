//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import Foundation
import Lottie
import SignalMessaging
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
            label.font = .ows_dynamicTypeBodyClamped
            label.textColor = Theme.primaryTextColor
            label.text = NSLocalizedString(
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
                image: #imageLiteral(resourceName: "chevron-down-18").withRenderingMode(.alwaysTemplate),
                font: .ows_regularFont(withSize: 17)
            ).styled(
                with: .color(DonationViewsUtil.bubbleBorderColor)
            )
        ]).styled(
            with: .font(.ows_regularFont(withSize: 17)),
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
        titleLabel.font = .ows_dynamicTypeBody.ows_semibold
        titleLabel.numberOfLines = 0

        let secondLineLabel = UILabel()
        secondLineLabel.text = NSLocalizedString(
            "BADGE_GIFTING_GIFT_ROW_SUBTITLE",
            comment: "When gifting a badge, the subtitle 'Send a Gift Badge' under the badge title"
        )
        secondLineLabel.textColor = Theme.primaryTextColor
        secondLineLabel.font = .ows_dynamicTypeBody2
        secondLineLabel.numberOfLines = 0

        let thirdLineLabel = UILabel()
        thirdLineLabel.text = {
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
                format: NSLocalizedString(
                    "BADGE_GIFTING_ROW_DURATION",
                    comment: "When gifting a badge, shows how long the badge lasts. Embeds {formatted duration}."
                ),
                formattedDuration
            )

            return String(
                format: NSLocalizedString(
                    "JOINED_WITH_DOT",
                    comment: "Two strings, joined by a dot. Embeds {first} and {second}, which are on opposite sides of the dot"
                ),
                formattedPrice, formattedDurationText
            )
        }()
        thirdLineLabel.textColor = Theme.primaryTextColor
        thirdLineLabel.font = .ows_dynamicTypeBody2
        thirdLineLabel.numberOfLines = 0

        let vStackView = UIStackView(arrangedSubviews: [titleLabel, secondLineLabel, thirdLineLabel])
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
        firstly { () -> Promise<SubscriptionManager.DonationConfiguration> in
            SubscriptionManager.fetchDonationConfiguration()
        }.map { donationConfiguration -> [SubscriptionLevel] in
            donationConfiguration.subscription.levels
        }.then { (fetchedSubscriptions: [SubscriptionLevel]) -> Promise<[SubscriptionLevel]> in
            let badgeUpdatePromises = fetchedSubscriptions.map { badgeStore.populateAssetsOnBadge($0.badge) }
            return Promise.when(fulfilled: badgeUpdatePromises).map { fetchedSubscriptions }
        }
    }

    public static func loadCurrentSubscription(subscriberID: Data?) -> Promise<Subscription?> {
        if let subscriberID = subscriberID {
            return SubscriptionManager.getCurrentSubscriptionStatus(for: subscriberID)
        } else {
            return Promise.value(nil)
        }
    }

    public static func subscriptionLevelForSubscription(subscriptionLevels: [SubscriptionLevel],
                                                        subscription: Subscription) -> SubscriptionLevel? {
        subscriptionLevels.first { $0.level == subscription.level }
    }

    public static func getMySupportCurrentSubscriptionTableItem(subscriptionLevel: SubscriptionLevel?,
                                                                currentSubscription: Subscription,
                                                                isSubscriptionRedemptionPending isPending: Bool,
                                                                subscriptionRedemptionFailureReason: SubscriptionRedemptionFailureReason,
                                                                statusLabelToModify: LinkingTextView) -> OWSTableItem {
        OWSTableItem.init(customCellBlock: {
            let didFail = subscriptionRedemptionFailureReason != .none
            if subscriptionLevel == nil {
                owsFailDebug("A subscription level should be provided. We'll do our best without one")
            }

            let cell = OWSTableItem.newCell()

            let hStackView = UIStackView()
            cell.contentView.addSubview(hStackView)
            hStackView.axis = .horizontal
            hStackView.spacing = 12
            hStackView.alignment = .center
            hStackView.autoPinEdgesToSuperviewMargins()

            let badgeImage = subscriptionLevel?.badge.assets?.universal160
            let badgeImageView: UIImageView = UIImageView(image: badgeImage)
            hStackView.addArrangedSubview(badgeImageView)
            badgeImageView.autoSetDimensions(to: CGSize(square: 64))
            badgeImageView.alpha = isPending || didFail ? 0.5 : 1

            if isPending {
                let redemptionLoadingSpinner = AnimationView(name: "indeterminate_spinner_blue")
                hStackView.addSubview(redemptionLoadingSpinner)
                redemptionLoadingSpinner.loopMode = .loop
                redemptionLoadingSpinner.contentMode = .scaleAspectFit
                redemptionLoadingSpinner.autoPin(toEdgesOf: badgeImageView, with: UIEdgeInsets(hMargin: 14, vMargin: 14))
                redemptionLoadingSpinner.play()
            }

            let vStackView: UIView = {
                let titleLabel: UILabel = {
                    let titleLabel = UILabel()
                    titleLabel.text = subscriptionLevel?.name
                    titleLabel.textColor = Theme.primaryTextColor
                    titleLabel.font = .ows_dynamicTypeBody.ows_semibold
                    titleLabel.numberOfLines = 0
                    return titleLabel
                }()

                let pricingLabel: UILabel = {
                    let pricingLabel = UILabel()
                    let pricingFormat = NSLocalizedString("SUSTAINER_VIEW_PRICING", comment: "Pricing text for sustainer view badges, embeds {{price}}")
                    let currencyString = DonationUtilities.format(money: currentSubscription.amount)
                    pricingLabel.text = String(format: pricingFormat, currencyString)
                    pricingLabel.textColor = Theme.primaryTextColor
                    pricingLabel.font = .ows_dynamicTypeBody2
                    pricingLabel.numberOfLines = 0
                    return pricingLabel
                }()

                let statusText: NSMutableAttributedString
                if isPending {
                    let text = NSLocalizedString("SUSTAINER_VIEW_PROCESSING_TRANSACTION", comment: "Status text while processing a badge redemption")
                    statusText = NSMutableAttributedString(string: text, attributes: [.foregroundColor: Theme.secondaryTextAndIconColor, .font: UIFont.ows_dynamicTypeBody2])
                } else if didFail {
                    let helpFormat = subscriptionRedemptionFailureReason == .paymentFailed ? NSLocalizedString("SUSTAINER_VIEW_PAYMENT_ERROR", comment: "Payment error occurred text, embeds {{link to contact support}}")
                    : NSLocalizedString("SUSTAINER_VIEW_CANT_ADD_BADGE", comment: "Couldn't add badge text, embeds {{link to contact support}}")
                    let contactSupport = NSLocalizedString("SUSTAINER_VIEW_CONTACT_SUPPORT", comment: "Contact support link")
                    let text = String(format: helpFormat, contactSupport)
                    let attributedText = NSMutableAttributedString(string: text, attributes: [.foregroundColor: Theme.secondaryTextAndIconColor, .font: UIFont.ows_dynamicTypeBody2])
                    attributedText.addAttributes([.link: NSURL()], range: NSRange(location: text.utf16.count - contactSupport.utf16.count, length: contactSupport.utf16.count))
                    statusText = attributedText
                } else {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .medium
                    let renewalFormat = NSLocalizedString("SUSTAINER_VIEW_RENEWAL", comment: "Renewal date text for sustainer view level, embeds {{renewal date}}")
                    let renewalDate = Date(timeIntervalSince1970: currentSubscription.endOfCurrentPeriod)
                    let renewalString = dateFormatter.string(from: renewalDate)
                    let text = String(format: renewalFormat, renewalString)
                    statusText = NSMutableAttributedString(string: text, attributes: [.foregroundColor: Theme.secondaryTextAndIconColor, .font: UIFont.ows_dynamicTypeBody2])
                }

                statusLabelToModify.attributedText = statusText
                statusLabelToModify.linkTextAttributes = [
                    .foregroundColor: Theme.accentBlueColor,
                    .underlineColor: UIColor.clear,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]

                let view = UIStackView(arrangedSubviews: [titleLabel,
                                                          pricingLabel,
                                                          statusLabelToModify])
                view.axis = .vertical
                view.distribution = .equalCentering
                view.spacing = 4

                return view
            }()
            hStackView.addArrangedSubview(vStackView)

            return cell
        })
    }

    public static func getSubscriptionRedemptionFailureReason(subscription: Subscription?) -> SubscriptionRedemptionFailureReason {
        if let subscription = subscription {
            switch subscription.status {
            case .incomplete, .incompleteExpired, .pastDue, .unpaid:
                return .paymentFailed
            case .active, .trialing, .canceled, .unknown:
                break
            }
        }

        return SDSDatabaseStorage.shared.read { transaction in
            SubscriptionManager.lastReceiptRedemptionFailed(transaction: transaction)
        }
    }

    public static func openDonateWebsite() {
        UIApplication.shared.open(TSConstants.donateUrl, options: [:], completionHandler: nil)
    }

    public static func presentDonationErrorSheet(
        from viewController: UIViewController,
        error rawError: Error,
        paymentMethod: DonationPaymentMethod,
        currentSubscription: Subscription? = nil
    ) {
        if let stripeError = rawError as? Stripe.StripeError {
            presentStripeDonationErrorSheet(
                for: stripeError,
                from: viewController,
                using: paymentMethod
            )
            return
        }

        let error: DonationJobError
        if let jobError = rawError as? DonationJobError {
            error = jobError
        } else {
            owsFailDebug("[Donations] Unexpected error \(rawError)")
            error = .assertion
        }

        switch error {
        case .timeout:
            presentStillProcessingSheet(from: viewController)
        case .assertion:
            presentBadgeCantBeAddedSheet(
                from: viewController,
                currentSubscription: currentSubscription
            )
        }
    }

    private static func presentStripeDonationErrorSheet(
        for error: Stripe.StripeError,
        from viewController: UIViewController,
        using paymentMethod: DonationPaymentMethod
    ) {
        let actionSheet = ActionSheetController(
            title: NSLocalizedString(
                "SUSTAINER_VIEW_ERROR_PROCESSING_PAYMENT_TITLE",
                comment: "Action sheet title for Error Processing Payment sheet"
            ),
            message: localizedDonationFailure(stripeCode: error.code, paymentMethod: paymentMethod)
        )

        actionSheet.addAction(.init(title: CommonStrings.okayButton, style: .cancel, handler: nil))

        viewController.navigationController?.topViewController?.presentActionSheet(actionSheet)
    }

    private static func presentStillProcessingSheet(from viewController: UIViewController) {
        guard
            let topViewController = viewController.navigationController?.topViewController,
            topViewController == viewController
        else {
            Logger.info("Not showing the \"still processing\" sheet because we're no longer the top view controller")
            return
        }

        let title = NSLocalizedString("SUSTAINER_STILL_PROCESSING_BADGE_TITLE", comment: "Action sheet title for Still Processing Badge sheet")
        let message = NSLocalizedString("SUSTAINER_VIEW_STILL_PROCESSING_BADGE_MESSAGE", comment: "Action sheet message for Still Processing Badge sheet")
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(OWSActionSheets.okayAction)
        topViewController.presentActionSheet(actionSheet)
    }

    public static func presentBadgeCantBeAddedSheet(
        from viewController: UIViewController,
        currentSubscription: Subscription? = nil
    ) {
        let failureReason = getSubscriptionRedemptionFailureReason(subscription: currentSubscription)

        let title = failureReason == .paymentFailed ? NSLocalizedString("SUSTAINER_VIEW_ERROR_PROCESSING_PAYMENT_TITLE", comment: "Action sheet title for Error Processing Payment sheet") : NSLocalizedString("SUSTAINER_VIEW_CANT_ADD_BADGE_TITLE", comment: "Action sheet title for Couldn't Add Badge sheet")
        let message = NSLocalizedString("SUSTAINER_VIEW_CANT_ADD_BADGE_MESSAGE", comment: "Action sheet message for Couldn't Add Badge sheet")

        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(ActionSheetAction(
            title: NSLocalizedString("CONTACT_SUPPORT", comment: "Button text to initiate an email to signal support staff"),
            style: .default,
            handler: { _ in
                let localizedSheetTitle = NSLocalizedString("EMAIL_SIGNAL_TITLE",
                                                            comment: "Title for the fallback support sheet if user cannot send email")
                let localizedSheetMessage = NSLocalizedString("EMAIL_SIGNAL_MESSAGE",
                                                              comment: "Description for the fallback support sheet if user cannot send email")
                guard ComposeSupportEmailOperation.canSendEmails else {
                    let fallbackSheet = ActionSheetController(title: localizedSheetTitle,
                                                              message: localizedSheetMessage)
                    let buttonTitle = NSLocalizedString("BUTTON_OKAY", comment: "Label for the 'okay' button.")
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
            title: NSLocalizedString("SUSTAINER_VIEW_SUBSCRIPTION_CONFIRMATION_NOT_NOW", comment: "Sustainer view Not Now Action sheet button"),
            style: .cancel,
            handler: nil
        ))
        viewController.navigationController?.topViewController?.presentActionSheet(actionSheet)
    }
}
