//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ConversationViewModel {
    let groupCallInProgress: Bool
    let isSystemContact: Bool
    let shouldShowVerifiedBadge: Bool
    let unreadMentionMessageIds: [String]

    static func load(for thread: TSThread, tx: SDSAnyReadTransaction) -> ConversationViewModel {
        let groupCallInProgress = InteractionFinder.unendedCallsForGroupThread(thread, transaction: tx)
            .filter { $0.joinedMemberAddresses.count > 0 }
            .count > 0

        let isSystemContact: Bool
        if let contactThread = thread as? TSContactThread {
            let contactsManager = NSObject.contactsManagerImpl
            isSystemContact = contactsManager.isSystemContact(address: contactThread.contactAddress, transaction: tx)
        } else {
            isSystemContact = false
        }

        let unreadMentionMessageIds = MentionFinder.messagesMentioning(
            aci: NSObject.tsAccountManager.localIdentifiers(transaction: tx)!.aci,
            in: thread,
            includeReadMessages: false,
            tx: tx
        ).map { $0.uniqueId }

        return ConversationViewModel(
            groupCallInProgress: groupCallInProgress,
            isSystemContact: isSystemContact,
            shouldShowVerifiedBadge: shouldShowVerifiedBadge(for: thread, tx: tx),
            unreadMentionMessageIds: unreadMentionMessageIds
        )
    }

    init(
        groupCallInProgress: Bool,
        isSystemContact: Bool,
        shouldShowVerifiedBadge: Bool,
        unreadMentionMessageIds: [String]
    ) {
        self.groupCallInProgress = groupCallInProgress
        self.isSystemContact = isSystemContact
        self.shouldShowVerifiedBadge = shouldShowVerifiedBadge
        self.unreadMentionMessageIds = unreadMentionMessageIds
    }

    private static func shouldShowVerifiedBadge(for thread: TSThread, tx: SDSAnyReadTransaction) -> Bool {
        let identityManager = NSObject.identityManager
        switch thread {
        case let groupThread as TSGroupThread:
            if groupThread.groupModel.groupMembers.isEmpty {
                return false
            }
            return !identityManager.groupContainsUnverifiedMember(groupThread.uniqueId, transaction: tx)

        case let contactThread as TSContactThread:
            return identityManager.verificationState(for: contactThread.contactAddress, transaction: tx) == .verified

        default:
            owsFailDebug("Showing conversation for unexpected thread type.")
            return false
        }
    }
}
