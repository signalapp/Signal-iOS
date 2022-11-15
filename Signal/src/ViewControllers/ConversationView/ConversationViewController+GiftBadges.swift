//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit

extension ConversationViewController {

    public func willWrapGift(_ messageUniqueId: String) -> Bool {
        // If a gift is unwrapped at roughly the same we're reloading the
        // conversation for an unrelated reason, there's a chance we'll try to
        // re-wrap a gift that was just unwrapped. This provides an opportunity to
        // override that behavior.
        return !self.viewState.unwrappedGiftMessageIds.contains(messageUniqueId)
    }

    public func willShakeGift(_ messageUniqueId: String) -> Bool {
        let (justInserted, _) = self.viewState.shakenGiftMessageIds.insert(messageUniqueId)
        return justInserted
    }

    public func willUnwrapGift(_ itemViewModel: CVItemViewModelImpl) {
        self.viewState.unwrappedGiftMessageIds.insert(itemViewModel.interaction.uniqueId)
        self.markGiftAsOpened(itemViewModel.interaction)
    }

    private func markGiftAsOpened(_ interaction: TSInteraction) {
        guard let outgoingMessage = interaction as? TSOutgoingMessage else {
            return
        }
        guard outgoingMessage.giftBadge?.redemptionState == .pending else {
            return
        }
        self.databaseStorage.asyncWrite { transaction in
            outgoingMessage.anyUpdateOutgoingMessage(transaction: transaction) {
                $0.giftBadge?.redemptionState = .opened
            }

            self.receiptManager.outgoingGiftWasOpened(outgoingMessage, transaction: transaction)
        }
    }

    public func didTapGiftBadge(_ itemViewModel: CVItemViewModelImpl, profileBadge: ProfileBadge, isExpired: Bool, isRedeemed: Bool) {
        AssertIsOnMainThread()

        let viewControllerToPresent: UIViewController

        switch itemViewModel.interaction {
        case let incomingMessage as TSIncomingMessage:
            viewControllerToPresent = self.incomingGiftSheet(
                incomingMessage: incomingMessage,
                profileBadge: profileBadge,
                isExpired: isExpired,
                isRedeemed: isRedeemed
            )

        case is TSOutgoingMessage:
            guard let thread = thread as? TSContactThread else {
                owsFailDebug("Clicked a gift badge that wasn't in a contact thread")
                return
            }

            viewControllerToPresent = BadgeGiftingThanksSheet(thread: thread, badge: profileBadge)

        default:
            owsFailDebug("Tapped on gift that's not a message")
            return
        }

        self.present(viewControllerToPresent, animated: true)
    }

    private func incomingGiftSheet(
        incomingMessage: TSIncomingMessage,
        profileBadge: ProfileBadge,
        isExpired: Bool,
        isRedeemed: Bool
    ) -> UIViewController {
        if isExpired {
            let mode: BadgeExpirationSheetState.Mode
            if isRedeemed {
                let hasCurrentSubscription = self.databaseStorage.read { transaction -> Bool in
                    self.subscriptionManager.hasCurrentSubscription(transaction: transaction)
                }
                mode = .giftBadgeExpired(hasCurrentSubscription: hasCurrentSubscription)
            } else {
                let fullName = self.databaseStorage.read { transaction -> String in
                    let authorAddress = incomingMessage.authorAddress
                    return self.contactsManager.displayName(for: authorAddress, transaction: transaction)
                }
                mode = .giftNotRedeemed(fullName: fullName)
            }
            let sheet = BadgeExpirationSheet(badge: profileBadge, mode: mode)
            sheet.delegate = self
            return sheet
        }
        if isRedeemed {
            let fullName = self.databaseStorage.read { transaction -> String in
                let authorAddress = incomingMessage.authorAddress
                return self.contactsManager.displayName(for: authorAddress, transaction: transaction)
            }
            return BadgeGiftingAlreadyRedeemedSheet(badge: profileBadge, fullName: fullName)
        }
        return self.giftRedemptionSheet(incomingMessage: incomingMessage, profileBadge: profileBadge)
    }

    private func giftRedemptionSheet(incomingMessage: TSIncomingMessage, profileBadge: ProfileBadge) -> UIViewController {
        let (shortName, fullName) = self.databaseStorage.read { transaction -> (String, String) in
            let authorAddress = incomingMessage.authorAddress
            return (
                self.contactsManager.shortDisplayName(for: authorAddress, transaction: transaction),
                self.contactsManager.displayName(for: authorAddress, transaction: transaction)
            )
        }
        return BadgeThanksSheet(badge: profileBadge, type: .gift(
            shortName: shortName,
            fullName: fullName,
            notNowAction: { [weak self] in self?.showRedeemBadgeLaterText() },
            incomingMessage: incomingMessage
        ))
    }

    private func showRedeemBadgeLaterText() {
        let text = NSLocalizedString(
            "BADGE_GIFTING_REDEEM_LATER",
            comment: "A toast that appears at the bottom of the screen after tapping 'Not Now' when redeeming a gift."
        )
        self.presentToastCVC(text)
    }

}

extension ConversationViewController: BadgeExpirationSheetDelegate {
    func badgeExpirationSheetActionTapped(_ action: BadgeExpirationSheetAction) {
        switch action {
        case .dismiss:
            break
        case .openDonationView:
            let appSettings = AppSettingsViewController.inModalNavigationController()
            let donateViewController = DonateViewController(startingDonationMode: .oneTime) { [weak self] finishResult in
                switch finishResult {
                case let .completedDonation(donateSheet, thanksSheet):
                    donateSheet.dismiss(animated: true) { [weak self] in
                        self?.present(thanksSheet, animated: true)
                    }
                case let .monthlySubscriptionCancelled(donateSheet, toastText):
                    donateSheet.dismiss(animated: true) { [weak self] in
                        guard let self = self else { return }
                        self.view.presentToast(text: toastText, fromViewController: self)
                    }
                }
            }
            appSettings.viewControllers += [
                DonationSettingsViewController(),
                donateViewController
            ]
            self.presentFormSheet(appSettings, animated: true, completion: nil)
        }
    }
}
