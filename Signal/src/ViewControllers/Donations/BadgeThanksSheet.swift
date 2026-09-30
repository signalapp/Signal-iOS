//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

struct VisibleBadgeResolver {
    let badgesSnapshot: ProfileBadgesSnapshot

    enum SwitchType {
        case displayOnProfile
        case makeFeaturedBadge
        case none
    }

    func switchType(for newBadgeId: String) -> SwitchType {
        if self.isVisibleAndFeatured(badgeId: newBadgeId) {
            return .none
        }
        if self.isAnyBadgeVisible() {
            return .makeFeaturedBadge
        }
        return .displayOnProfile
    }

    func switchDefault(for newBadgeId: String) -> Bool {
        // If the badge is already featured, suggest keeping it featured. In this
        // case, no switch is presented to the user (see above), so the eventual
        // position of the badge would be determined entirely by the following if
        // statements, which could lead to odd behavior in some cases.
        if self.isVisibleAndFeatured(badgeId: newBadgeId) {
            return true
        }
        // If you're buying a recurring badge, suggest featuring it.
        if SubscriptionBadgeIds.contains(newBadgeId) {
            return true
        }
        // If you're buying a one-time badge (prior check didn't pass), don't
        // suggest featuring it if you already have a recurring badge.
        if self.hasAnySustainerBadge() {
            return false
        }
        return true
    }

    func currentlyVisibleBadgeIds() -> [String] {
        self.badgesSnapshot.existingBadges.lazy.filter { $0.isVisible }.map { $0.id }
    }

    func visibleBadgeIds(adding newBadgeId: String, isVisibleAndFeatured: Bool) -> [String] {
        lazy var currentlyVisibleBadgeIds = self.currentlyVisibleBadgeIds()
        lazy var nonNewBadgeIds = self.badgesSnapshot.existingBadges.lazy.filter { $0.id != newBadgeId }.map { $0.id }

        // If the user has selected "Display on Profile" or "Make Featured Badge",
        // we make this the first visible badge. We also make all other badges
        // visible -- we don't currently support displaying only a subset.
        if isVisibleAndFeatured {
            return [newBadgeId] + nonNewBadgeIds
        }

        // For all the remaining cases, the switch was shown, and it's set to "off".

        // If there aren't any badges visible, don't make this one visible.
        if currentlyVisibleBadgeIds.isEmpty {
            return []
        }

        // We have some visible badges, but the user doesn't want this badge to be featured.
        if currentlyVisibleBadgeIds.first == newBadgeId {
            return nonNewBadgeIds + [newBadgeId]
        }

        // The badge is already visible. Leave it where it is to avoid a redundant profile update.
        if currentlyVisibleBadgeIds.contains(newBadgeId) {
            return currentlyVisibleBadgeIds
        }

        // The badge isn't visible but should be. At it to the end of the list of badges.
        return nonNewBadgeIds + [newBadgeId]
    }

    private func hasAnySustainerBadge() -> Bool {
        self.badgesSnapshot.existingBadges.first { SubscriptionBadgeIds.contains($0.id) } != nil
    }

    private func firstVisibleBadge() -> ProfileBadgesSnapshot.Badge? {
        self.badgesSnapshot.existingBadges.first { $0.isVisible }
    }

    private func isAnyBadgeVisible() -> Bool {
        self.firstVisibleBadge() != nil
    }

    private func isVisibleAndFeatured(badgeId: String) -> Bool {
        self.firstVisibleBadge()?.id == badgeId
    }

}

class BadgeThanksSheet: HeroSheetViewController {

    enum ThanksType {
        /// We redeemed a badge that was paid for via bank transfer.
        case badgeRedeemedViaBankPayment
        /// We redeemed a badge that was paid for via a method other than bank
        /// transfer.
        case badgeRedeemedViaNonBankPayment
        /// We received a gift badge.
        case giftReceived(shortName: String, notNowAction: () -> Void, incomingMessage: TSIncomingMessage)
    }

    private let badge: ProfileBadge
    private let thanksType: ThanksType

    private var shouldMakeVisibleAndPrimary: Bool

    // For checking manual sheet dismissal in viewDidDisappear
    private var didHandleResult = false

    convenience init(
        receiptCredentialRedemptionSuccess: DonationReceiptCredentialRedemptionSuccess,
        newBadge: ProfileBadge,
    ) {
        owsPrecondition(receiptCredentialRedemptionSuccess.badgeID == newBadge.id)

        let thanksType: ThanksType = {
            switch receiptCredentialRedemptionSuccess.paymentMethod {
            case nil, .applePay, .creditOrDebitCard, .paypal:
                return .badgeRedeemedViaNonBankPayment
            case .sepa, .ideal:
                return .badgeRedeemedViaBankPayment
            }
        }()

        self.init(
            newBadge: newBadge,
            thanksType: thanksType,
            oldBadgesSnapshot: receiptCredentialRedemptionSuccess.badgesSnapshotBeforeJob,
        )
    }

    /// Displays a message after a badge has been redeemed.
    ///
    /// - Parameter newBadge: The badge that was just redeemed.
    ///
    /// - Parameter thanksType: The type of thanks we want to show.
    ///
    /// - Parameter oldBadgesSnapshot: A snapshot of the user's badges before
    /// `newBadge` was redeemed. You can capture this value by calling
    /// ``ProfileBadgesSnapshot/current()``.
    init(
        newBadge badge: ProfileBadge,
        thanksType: ThanksType,
        oldBadgesSnapshot: ProfileBadgesSnapshot,
    ) {
        self.badge = badge
        self.thanksType = thanksType

        let visibleBadgeResolver = VisibleBadgeResolver(badgesSnapshot: oldBadgesSnapshot)
        let shouldMakeVisibleAndPrimary = visibleBadgeResolver.switchDefault(for: badge.id)
        self.shouldMakeVisibleAndPrimary = shouldMakeVisibleAndPrimary

        switch thanksType {
        case .badgeRedeemedViaBankPayment, .badgeRedeemedViaNonBankPayment:
            owsAssertDebug(BoostBadgeIds.contains(badge.id) || SubscriptionBadgeIds.contains(badge.id))
        case .giftReceived:
            owsAssertDebug(GiftBadgeIds.contains(badge.id))
        }

        // Assigned after super.init for the toggle and button callbacks.
        weak var sheet: BadgeThanksSheet?

        var bodyElements: [Body.Element] = [
            .text(.plain(Self.bodyText(thanksType: thanksType, badge: badge))),
        ]
        if
            let toggle = Self.visibilityToggle(
                switchType: visibleBadgeResolver.switchType(for: badge.id),
                isOn: shouldMakeVisibleAndPrimary,
                onValueChanged: { sheet?.shouldMakeVisibleAndPrimary = $0 },
            )
        {
            bodyElements.append(.toggle(toggle))
        }

        let primaryButton: Button
        let secondaryButton: Button?
        switch thanksType {
        case let .giftReceived(_, notNowAction, incomingMessage):
            primaryButton = Button(
                title: CommonStrings.redeemGiftButton,
                action: .custom { _ in sheet?.didTapRedeem(incomingMessage: incomingMessage) },
            )
            secondaryButton = Button(
                title: CommonStrings.notNowButton,
                style: .secondary,
                action: .custom { _ in sheet?.didTapNotNow(notNowAction: notNowAction) },
            )
        case .badgeRedeemedViaBankPayment, .badgeRedeemedViaNonBankPayment:
            primaryButton = Button(
                title: CommonStrings.doneButton,
                action: .custom { _ in sheet?.didTapDone() },
            )
            secondaryButton = nil
        }

        super.init(
            hero: .image(badge.assets.universal160 ?? UIImage(), height: 80),
            title: Self.titleText(thanksType: thanksType),
            body: Body(bodyElements),
            primary: .button(primaryButton),
            secondary: secondaryButton.map { .button($0) },
        )
        sheet = self
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        guard isBeingDismissed, !didHandleResult else { return }
        didHandleResult = true

        switch self.thanksType {
        case .badgeRedeemedViaBankPayment, .badgeRedeemedViaNonBankPayment:
            // Capture this value on the main thread.
            let shouldMakeVisibleAndPrimary = self.shouldMakeVisibleAndPrimary
            Task {
                do {
                    try await self.saveVisibilityChanges(shouldMakeVisibleAndPrimary: shouldMakeVisibleAndPrimary)
                } catch {
                    Logger.error("Unable to save visibility changes: \(error)")
                }
            }
        case let .giftReceived(_, notNowAction, _):
            notNowAction()
        }
    }

    private func performConfirmationAction(_ operation: @escaping () async throws -> Void) async throws {
        do {
            try await ModalActivityIndicatorViewController.presentAndPropagateResult(from: self, wrappedAsyncBlock: {
                do {
                    return try await operation()
                } catch {
                    owsFailDebug("Unexpectedly failed to confirm badge action \(error)")
                    throw error
                }
            })
            self.didHandleResult = true
            self.dismiss(animated: true)
        }
    }

    private func saveVisibilityChanges(shouldMakeVisibleAndPrimary: Bool) async throws {
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx -> Promise<Void> in
            let visibleBadgeResolver = VisibleBadgeResolver(
                badgesSnapshot: .forLocalProfile(profileManager: SSKEnvironment.shared.profileManagerRef, tx: tx),
            )
            let visibleBadgeIds = visibleBadgeResolver.visibleBadgeIds(
                adding: self.badge.id,
                isVisibleAndFeatured: shouldMakeVisibleAndPrimary,
            )
            if visibleBadgeIds == visibleBadgeResolver.currentlyVisibleBadgeIds() {
                // No change, we can skip the profile update.
                return Promise.value(())
            }
            return SSKEnvironment.shared.profileManagerRef.updateLocalProfile(
                profileGivenName: .noChange,
                profileFamilyName: .noChange,
                profileBio: .noChange,
                profileBioEmoji: .noChange,
                profileAvatarData: .noChange,
                visibleBadgeIds: .setTo(visibleBadgeIds),
                unsavedRotatedProfileKey: nil,
                userProfileWriter: .localUser,
                authedAccount: .implicit,
                tx: tx,
            )
        }.awaitable()
    }

    private static func redeemGiftBadge(incomingMessage: TSIncomingMessage) async throws {
        guard let giftBadge = incomingMessage.giftBadge else {
            throw OWSAssertionError("trying to redeem message without a badge")
        }
        try await DependenciesBridge.shared.donationSubscriptionManager.redeemReceiptCredentialPresentation(
            receiptCredentialPresentation: try giftBadge.getReceiptCredentialPresentation(),
        )
        await Self.updateGiftBadge(incomingMessage: incomingMessage, state: .redeemed)
    }

    private static func updateGiftBadge(incomingMessage: TSIncomingMessage, state: OWSGiftBadgeRedemptionState) async {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            incomingMessage.anyUpdateIncomingMessage(transaction: transaction) {
                $0.giftBadge?.redemptionState = state
            }

            if state == .redeemed {
                SSKEnvironment.shared.receiptManagerRef.incomingGiftWasRedeemed(incomingMessage, transaction: transaction)
            }
        }
    }

    private static func titleText(thanksType: ThanksType) -> String {
        switch thanksType {
        case .badgeRedeemedViaBankPayment:
            return OWSLocalizedString(
                "BADGE_THANKS_BANK_DONATION_COMPLETE_TITLE",
                comment: "Title for a sheet explaining that a bank transfer donation is complete, and that you have received a badge.",
            )
        case .badgeRedeemedViaNonBankPayment:
            return OWSLocalizedString(
                "BADGE_THANKS_TITLE",
                comment: "When you make a donation to Signal, you will receive a badge. A thank-you sheet appears when this happens. This is the title of that sheet.",
            )
        case let .giftReceived(shortName, _, _):
            let formatText = OWSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_REDEEM_BADGE_TITLE_FORMAT",
                comment: "A friend has donated on your behalf and you received a badge. A sheet opens for you to redeem this badge. Embeds {{contact's short name, such as a first name}}.",
            )
            return String.nonPluralLocalizedStringWithFormat(formatText, shortName)
        }
    }

    private static func bodyText(thanksType: ThanksType, badge: ProfileBadge) -> String {
        switch thanksType {
        case .badgeRedeemedViaBankPayment:
            return OWSLocalizedString(
                "BADGE_THANKS_BANK_DONATION_COMPLETE_BODY",
                comment: "Body for a sheet explaining that a bank transfer donation is complete, and that you have received a badge.",
            )
        case .badgeRedeemedViaNonBankPayment:
            let formatText = OWSLocalizedString(
                "BADGE_THANKS_BODY",
                comment: "When you make a donation to Signal, you will receive a badge. A thank-you sheet appears when this happens. This is the body text on that sheet.",
            )
            return String.nonPluralLocalizedStringWithFormat(formatText, badge.localizedName)
        case let .giftReceived(shortName, _, _):
            let formatText = OWSLocalizedString(
                "DONATION_ON_BEHALF_OF_A_FRIEND_YOU_RECEIVED_A_BADGE_FORMAT",
                comment: "A friend has donated on your behalf and you received a badge. This text says that you received a badge, and from whom. Embeds {{contact's short name, such as a first name}}.",
            )
            return String.nonPluralLocalizedStringWithFormat(formatText, shortName)
        }
    }

    // MARK: -

    private static func visibilityToggle(
        switchType: VisibleBadgeResolver.SwitchType,
        isOn: Bool,
        onValueChanged: @escaping (Bool) -> Void,
    ) -> Body.Toggle? {
        let title: String
        let footer: String?
        switch switchType {
        case .none:
            return nil
        case .displayOnProfile:
            title = OWSLocalizedString(
                "BADGE_THANKS_DISPLAY_ON_PROFILE_LABEL",
                comment: "Label prompting the user to display the new badge on their profile on the badge thank you sheet.",
            )
            footer = nil
        case .makeFeaturedBadge:
            title = OWSLocalizedString(
                "BADGE_THANKS_MAKE_FEATURED",
                comment: "Label prompting the user to feature the new badge on their profile on the badge thank you sheet.",
            )
            footer = OWSLocalizedString(
                "BADGE_THANKS_TOGGLE_FOOTER",
                comment: "Footer explaining that only one badge can be featured at a time on the thank you sheet.",
            )
        }
        return Body.Toggle(
            title: title,
            footer: footer,
            isOn: isOn,
            onValueChanged: onValueChanged,
        )
    }

    // MARK: - Actions

    private func didTapDone() {
        // Capture this value on the main thread.
        let shouldMakeVisibleAndPrimary = self.shouldMakeVisibleAndPrimary
        Task {
            do {
                try await self.performConfirmationAction {
                    try await self.saveVisibilityChanges(shouldMakeVisibleAndPrimary: shouldMakeVisibleAndPrimary)
                }
            } catch {
                self.didHandleResult = true
                self.dismiss(animated: true)
            }
        }
    }

    private func didTapRedeem(incomingMessage: TSIncomingMessage) {
        // Capture this value on the main thread.
        let shouldMakeVisibleAndPrimary = self.shouldMakeVisibleAndPrimary
        Task {
            do {
                try await self.performConfirmationAction {
                    try await Self.redeemGiftBadge(incomingMessage: incomingMessage)
                    try await self.saveVisibilityChanges(shouldMakeVisibleAndPrimary: shouldMakeVisibleAndPrimary)
                }
            } catch {
                OWSActionSheets.showActionSheet(
                    title: OWSLocalizedString(
                        "FAILED_TO_REDEEM_BADGE_RECEIVED_AFTER_DONATION_FROM_A_FRIEND_TITLE",
                        comment: "Shown as the title of an alert when failing to redeem a badge that was received after a friend donated on your behalf.",
                    ),
                    message: OWSLocalizedString(
                        "FAILED_TO_REDEEM_BADGE_RECEIVED_AFTER_DONATION_FROM_A_FRIEND_BODY",
                        comment: "Shown as the body of an alert when failing to redeem a badge that was received after a friend donated on your behalf.",
                    ),
                )
            }
        }
    }

    private func didTapNotNow(notNowAction: () -> Void) {
        didHandleResult = true
        notNowAction()
        dismiss(animated: true)
    }
}
