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

    static func load(for thread: TSThread, tx: DBReadTransaction) -> ConversationViewModel {
        let groupCallInProgress = GroupCallInteractionFinder().unendedCallsForGroupThread(thread, transaction: tx)
            .filter { !$0.joinedMemberAcis.isEmpty }
            .count > 0

        let isSystemContact = thread.isSystemContact(contactsManager: SSKEnvironment.shared.contactManagerImplRef, tx: tx)

        let unreadMentionMessageIds = MentionFinder.messagesMentioning(
            aci: DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx)!.aci,
            in: thread.uniqueId,
            includeReadMessages: false,
            tx: tx,
        ).map { $0.uniqueId }

        return ConversationViewModel(
            groupCallInProgress: groupCallInProgress,
            isSystemContact: isSystemContact,
            shouldShowVerifiedBadge: shouldShowVerifiedBadge(for: thread, tx: tx),
            unreadMentionMessageIds: unreadMentionMessageIds,
        )
    }

    init(
        groupCallInProgress: Bool,
        isSystemContact: Bool,
        shouldShowVerifiedBadge: Bool,
        unreadMentionMessageIds: [String],
    ) {
        self.groupCallInProgress = groupCallInProgress
        self.isSystemContact = isSystemContact
        self.shouldShowVerifiedBadge = shouldShowVerifiedBadge
        self.unreadMentionMessageIds = unreadMentionMessageIds
    }

    private static func shouldShowVerifiedBadge(for thread: TSThread, tx: DBReadTransaction) -> Bool {
        let identityManager = DependenciesBridge.shared.identityManager
        switch thread {
        case let groupThread as TSGroupThread:
            if groupThread.groupModel.groupMembers.isEmpty {
                return false
            }
            return !identityManager.groupContainsUnverifiedMember(groupThread.uniqueId, tx: tx)

        case let contactThread as TSContactThread:
            return identityManager.verificationState(for: contactThread.contactAddress, tx: tx) == .verified

        default:
            owsFailDebug("Showing conversation for unexpected thread type.")
            return false
        }
    }
}
