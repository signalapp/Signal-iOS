//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

extension ConversationViewController {

    func willWrapGift(_ messageUniqueId: String) -> Bool {
        // If a gift is unwrapped at roughly the same we're reloading the
        // conversation for an unrelated reason, there's a chance we'll try to
        // re-wrap a gift that was just unwrapped. This provides an opportunity to
        // override that behavior.
        return !self.viewState.unwrappedGiftMessageIds.contains(messageUniqueId)
    }

    func willShakeGift(_ messageUniqueId: String) -> Bool {
        let (justInserted, _) = self.viewState.shakenGiftMessageIds.insert(messageUniqueId)
        return justInserted
    }

    func willUnwrapGift(_ itemViewModel: CVItemViewModelImpl) {
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

    func didTapGiftBadge(_ itemViewModel: CVItemViewModelImpl, profileBadge: ProfileBadge) {
        AssertIsOnMainThread()

        let viewControllerToPresent: UIViewController

        switch itemViewModel.interaction {
        case let incomingMessage as TSIncomingMessage:
            viewControllerToPresent = self.giftRedemptionSheet(incomingMessage: incomingMessage, profileBadge: profileBadge)

        case is TSOutgoingMessage:
            guard let thread = thread as? TSContactThread else {
                owsFailDebug("Clicked a gift badge that wasn't in a contact thread")
                return
            }

            viewControllerToPresent = BadgeGiftThanksSheet(thread: thread, badge: profileBadge)

        default:
            owsFailDebug("Tapped on gift that's not a message")
            return
        }

        self.present(viewControllerToPresent, animated: true)
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
