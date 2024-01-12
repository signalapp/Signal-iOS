//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension GroupUpdateInfoMessageInserterImpl {
    /// Represents updates to a group's membership that may be possible to
    /// collapse into existing info messages.
    enum PossiblyCollapsibleMembershipChange {
        case newJoinRequestFromSingleUser(requestingAci: Aci)
        case canceledJoinRequestFromSingleUser(cancelingAci: Aci)
    }

    /// Represents the result of collapsing updates into existing messages.
    enum CollapsibleMembershipChangeResult {
        /// Membership changes were collapsed into an existing, now-updated,
        /// info message.
        case updatesCollapsedIntoExistingMessage
        /// Update messages pertaining to the membership change are available
        /// and a new info message should be inserted containing them. Existing
        /// messages may have been updated while computing these updates.
        case updateItemForNewMessage(TSInfoMessage.PersistableGroupUpdateItem)
    }

    func handlePossiblyCollapsibleMembershipChange(
        possiblyCollapsibleMembershipChange: PossiblyCollapsibleMembershipChange,
        localIdentifiers: LocalIdentifiers,
        groupThread: TSGroupThread,
        newGroupModel: TSGroupModel,
        transaction: SDSAnyWriteTransaction
    ) -> CollapsibleMembershipChangeResult? {
        guard
            let (mostRecentInfoMsg, secondMostRecentInfoMsgMaybe) = mostRecentVisibleInteractionsAsInfoMessages(
                forGroupThread: groupThread,
                withTransaction: transaction
            )
        else {
            return nil
        }

        switch possiblyCollapsibleMembershipChange {
        case .newJoinRequestFromSingleUser(let requestingAci):
            /// By requesting and canceling over and over, a user who is not in
            /// a group would be able to fill the group's chat history with info
            /// messages detailing their actions. To address that, we'll
            /// "collapse" a request/cancel event into a preexisting info
            /// message, if appropriate, rather than letting the events pile up.

            guard localIdentifiers.aci != requestingAci else {
                return nil
            }

            return maybeUpdate(
                mostRecentInfoMsg: mostRecentInfoMsg,
                withNewJoinRequestFrom: requestingAci,
                localIdentifiers: localIdentifiers,
                transaction: transaction
            )
        case .canceledJoinRequestFromSingleUser(let cancelingAci):
            /// See the comment above for why we care about this case.

            guard localIdentifiers.aci != cancelingAci else {
                return nil
            }

            return maybeUpdate(
                mostRecentInfoMsg: mostRecentInfoMsg,
                andSecondMostRecentInfoMsg: secondMostRecentInfoMsgMaybe,
                withCanceledJoinRequestFrom: cancelingAci,
                newGroupModel: newGroupModel,
                localIdentifiers: localIdentifiers,
                transaction: transaction
            )
        }
    }

    private func maybeUpdate(
        mostRecentInfoMsg: TSInfoMessage,
        withNewJoinRequestFrom requestingAci: Aci,
        localIdentifiers: LocalIdentifiers,
        transaction: SDSAnyWriteTransaction
    ) -> CollapsibleMembershipChangeResult? {

        // For a new join request we always want a new info message. However,
        // if the new request matches collapsed request/cancel events on the
        // most recent message we should make a note on the new message that
        // it is no longer the tail of the sequence.
        //
        // Note that the new message might get collapsed further (into the
        // most recent message) in the future.

        let mostRecentUpdateItem: TSInfoMessage.PersistableGroupUpdateItem?
        switch mostRecentInfoMsg.groupUpdateMetadata(localIdentifiers: localIdentifiers) {
        case .precomputed(let precomputedItems):
            mostRecentUpdateItem = precomputedItems.asSingleUpdateItem
        case .modelDiff, .legacyRawString, .newGroup, .nonGroupUpdate:
            return nil
        }

        guard
            let mostRecentUpdateItem,
            case let .sequenceOfInviteLinkRequestAndCancels(requester, count, isTail) = mostRecentUpdateItem,
            requestingAci == requester.wrappedValue
        else {
            return nil
        }

        owsAssertDebug(isTail)

        mostRecentInfoMsg.setSingleUpdateItem(
            singleUpdateItem: .sequenceOfInviteLinkRequestAndCancels(
                requester: requestingAci.codableUuid,
                count: count,
                isTail: false
            )
        )
        mostRecentInfoMsg.anyUpsert(transaction: transaction)

        return .updateItemForNewMessage(
            .sequenceOfInviteLinkRequestAndCancels(
                requester: requestingAci.codableUuid,
                count: 0,
                isTail: true
            )
        )
    }

    private func maybeUpdate(
        mostRecentInfoMsg: TSInfoMessage,
        andSecondMostRecentInfoMsg secondMostRecentInfoMsg: TSInfoMessage?,
        withCanceledJoinRequestFrom cancelingAci: Aci,
        newGroupModel: TSGroupModel,
        localIdentifiers: LocalIdentifiers,
        transaction: SDSAnyWriteTransaction
    ) -> CollapsibleMembershipChangeResult? {

        // If the most recent message represents the join request that's being
        // canceled, we want to collapse into it.
        //
        // Further, if the second-most-recent message represents already-
        // collapsed join/cancel events from the same address, we can simply
        // increment that message's collapse counter and delete the most recent
        // message.

        guard
            let mostRecentInfoMsgJoiner = mostRecentInfoMsg.representsSingleRequestToJoin(
                localIdentifiers: localIdentifiers,
                tx: transaction
            ),
            cancelingAci == mostRecentInfoMsgJoiner
        else {
            return nil
        }

        let secondMostRecentUpdateItem: TSInfoMessage.PersistableGroupUpdateItem?
        switch secondMostRecentInfoMsg?.groupUpdateMetadata(localIdentifiers: localIdentifiers) {
        case .precomputed(let precomputedItems):
            secondMostRecentUpdateItem = precomputedItems.asSingleUpdateItem
        case .modelDiff, .legacyRawString, .newGroup, .nonGroupUpdate, .none:
            secondMostRecentUpdateItem = nil
        }

        if
            let secondMostRecentInfoMsg,
            let secondMostRecentUpdateItem,
            case let .sequenceOfInviteLinkRequestAndCancels(requester, count, isTail) = secondMostRecentUpdateItem,
            cancelingAci == requester.wrappedValue
        {
            mostRecentInfoMsg.anyRemove(transaction: transaction)

            owsAssertDebug(!isTail)
            secondMostRecentInfoMsg.setSingleUpdateItem(
                singleUpdateItem: .sequenceOfInviteLinkRequestAndCancels(
                    requester: cancelingAci.codableUuid,
                    count: count + 1,
                    isTail: true
                )
            )
            secondMostRecentInfoMsg.anyUpsert(transaction: transaction)

            return .updatesCollapsedIntoExistingMessage
        } else {
            mostRecentInfoMsg.setSingleUpdateItem(
                singleUpdateItem: .sequenceOfInviteLinkRequestAndCancels(
                    requester: cancelingAci.codableUuid,
                    count: 1,
                    isTail: true
                )
            )
            mostRecentInfoMsg.anyUpsert(transaction: transaction)

            return .updatesCollapsedIntoExistingMessage
        }
    }

    private func mostRecentVisibleInteractionsAsInfoMessages(
        forGroupThread groupThread: TSGroupThread,
        withTransaction transaction: SDSAnyReadTransaction
    ) -> (first: TSInfoMessage, second: TSInfoMessage?)? {
        var mostRecentVisibleInteraction: TSInteraction?
        var secondMostRecentVisibleInteraction: TSInteraction?
        do {
            try InteractionFinder(threadUniqueId: groupThread.uniqueId)
                .enumerateRecentInteractions(
                    excludingPlaceholders: !DebugFlags.showFailedDecryptionPlaceholders.get(), // This matches how messages are loaded in MessageLoader
                    transaction: transaction,
                    block: { interaction, shouldStop in
                        if mostRecentVisibleInteraction == nil {
                            mostRecentVisibleInteraction = interaction
                        } else if secondMostRecentVisibleInteraction == nil {
                            secondMostRecentVisibleInteraction = interaction
                            shouldStop.pointee = true
                        }
                    })
        } catch let error {
            Logger.warn("Failed to get most recent interactions for thread: \(error.localizedDescription)")
            return nil
        }

        guard let mostRecentInfoMessage = mostRecentVisibleInteraction as? TSInfoMessage else {
            Logger.debug("Most recent visible interaction not found as info message")
            return nil
        }

        guard let secondMostRecentInfoMessage = secondMostRecentVisibleInteraction as? TSInfoMessage else {
            Logger.debug("Second most recent visible interaction not found as info message")
            return (mostRecentInfoMessage, nil)
        }

        return (mostRecentInfoMessage, secondMostRecentInfoMessage)
    }
}

// MARK: TSInfoMessage extension

public extension TSInfoMessage.PersistableGroupUpdateItemsWrapper {
    var asSingleUpdateItem: TSInfoMessage.PersistableGroupUpdateItem? {
        guard updateItems.count == 1 else {
            return nil
        }

        return updateItems.first
    }
}

private extension TSInfoMessage {
    func setSingleUpdateItem(singleUpdateItem: PersistableGroupUpdateItem) {
        setGroupUpdateItemsWrapper(PersistableGroupUpdateItemsWrapper([singleUpdateItem]))
    }

    func representsSingleRequestToJoin(
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyReadTransaction
    ) -> Aci? {
        switch groupUpdateMetadata(localIdentifiers: localIdentifiers) {
        case .newGroup, .nonGroupUpdate, .legacyRawString:
            return nil
        case .precomputed(let precomputedItems):
            switch precomputedItems.asSingleUpdateItem {
            case let .sequenceOfInviteLinkRequestAndCancels(requester, count, isTail):
                guard isTail, count == 0 else {
                    return nil
                }
                return requester.wrappedValue
            case .localUserRequestedToJoin:
                // Just calling out that we don't collapse the local user's requests.
                return nil
            case let .otherUserRequestedToJoin(requester):
                return requester.wrappedValue
            default:
                return nil
            }
        case .modelDiff:
            // In the case of a model diff, convert to a displayable item first, and see if
            // that displayable item is a single request to join. The displayable item
            // generation logic already has logic to determine this case; no need to
            // replicate it here (although this method is wasteful since it will fetch
            // a bunch of metadata we throw away)
            guard
                let groupUpdateItems = computedGroupUpdateItems(
                    localIdentifiers: localIdentifiers,
                    tx: tx
                ),
                groupUpdateItems.count == 1,
                case let .otherUserRequestedToJoin(requesterAci) = groupUpdateItems.first!
            else {
                return nil
            }

            return requesterAci.wrappedValue
        }
    }
}
