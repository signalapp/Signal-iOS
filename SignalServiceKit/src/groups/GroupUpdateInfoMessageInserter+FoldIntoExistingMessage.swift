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
            let (mostRecentInfoMsg, secondMostRecentInfoMsgMaybe) =
                Self.mostRecentVisibleInteractionsAsInfoMessages(
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

        if let (mostRecentInfoMsgJoiner, count) = mostRecentInfoMsg.representsSequenceOfRequestsAndCancelsWithAdditionalRequestToJoin(
            localIdentifiers: localIdentifiers
        ) {
            guard mostRecentInfoMsgJoiner == cancelingAci else {
                return nil
            }
            // collapse into the single most recent message; it already represents
            // a sequence of requests + cancels and one more request.
            mostRecentInfoMsg.setSingleUpdateItem(
                singleUpdateItem: .sequenceOfInviteLinkRequestAndCancels(
                    requester: cancelingAci.codableUuid,
                    count: count + 1,
                    isTail: true
                )
            )
            mostRecentInfoMsg.anyUpsert(transaction: transaction)

            return .updatesCollapsedIntoExistingMessage
        }

        guard
            let mostRecentInfoMsgJoiner = mostRecentInfoMsg.representsCollapsibleSingleRequestToJoin(
                localIdentifiers: localIdentifiers,
                tx: transaction
            ),
            cancelingAci == mostRecentInfoMsgJoiner
        else {
            return nil
        }

        if
            let secondMostRecentInfoMsg,
            let (requester, count) = secondMostRecentInfoMsg
                .representsSingleSequenceOfRequestsAndCancels(
                    localIdentifiers: localIdentifiers
                ),
            cancelingAci == requester
        {
            mostRecentInfoMsg.anyRemove(transaction: transaction)

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

    /// See ``GroupUpdateInfoMessageInserterBackupHelper``.
    public static func collapseFromBackupIfNeeded(
        updates: inout [TSInfoMessage.PersistableGroupUpdateItem],
        localIdentifiers: LocalIdentifiers,
        groupThread: TSGroupThread,
        transaction: SDSAnyWriteTransaction
    ) {
        if
            updates.count == 2,
            let (sequenceRequestor, count) = updates[0]
                .representsSequenceOfRequestsAndCancels(),
            let singleRequestor = updates[1]
                .representsCollapsibleSingleRequestToJoin(),
            sequenceRequestor == singleRequestor
        {
            // These updates are collapsible in isolation.
            // Mark the first one as not the tail; thats the only change
            // we need to make to "collapse" this one.
            updates[0] =
                .sequenceOfInviteLinkRequestAndCancels(
                    requester: sequenceRequestor.codableUuid,
                    count: count,
                    isTail: false
                )
            return
        }

        guard
            updates.count == 1,
            let requestingAci = updates[0].representsCollapsibleSingleRequestToJoin()
        else {
            // No change needed.
            return
        }

        // This latest message is collapsible; try and collapse it.

        guard let (mostRecentInfoMsg, _) =
            mostRecentVisibleInteractionsAsInfoMessages(
                forGroupThread: groupThread,
                withTransaction: transaction
            )
        else {
            return
        }

        guard let (mostRecentMsgAci, count) = mostRecentInfoMsg
            .representsSingleSequenceOfRequestsAndCancels(
                localIdentifiers: localIdentifiers
            ),
            requestingAci == mostRecentMsgAci
        else {
            return
        }

        mostRecentInfoMsg.anyUpdateInfoMessage(
            transaction: transaction,
            block: {
                $0.setSingleUpdateItem(
                    singleUpdateItem: .sequenceOfInviteLinkRequestAndCancels(
                        requester: mostRecentMsgAci.codableUuid,
                        // Count stays the same.
                        count: count,
                        // Its not the tail because of the subsequent request.
                        isTail: false
                    )
                )
            }
        )
        // No need to change the updates in the new info message.
        return
    }

    private static func mostRecentVisibleInteractionsAsInfoMessages(
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

    func representsCollapsibleSingleRequestToJoin(
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyReadTransaction
    ) -> Aci? {
        switch groupUpdateMetadata(localIdentifiers: localIdentifiers) {
        case .newGroup, .nonGroupUpdate, .legacyRawString:
            return nil
        case .precomputed(let precomputedItems):
            return precomputedItems
                .asSingleUpdateItem?
                .representsCollapsibleSingleRequestToJoin()
        case .modelDiff:
            // In the case of a model diff, convert to a persistable item first, and see if
            // that persistable item is a single request to join. The persistable item
            // generation logic already has logic to determine this case; no need to
            // replicate it here.
            guard
                let groupUpdateItems = computedGroupUpdateItems(
                    localIdentifiers: localIdentifiers,
                    tx: tx
                ),
                groupUpdateItems.count == 1
            else {
                return nil
            }

            return groupUpdateItems.first?.representsCollapsibleSingleRequestToJoin()
        }
    }

    func representsSingleSequenceOfRequestsAndCancels(
        localIdentifiers: LocalIdentifiers
    ) -> (Aci, count: UInt)? {
        switch self.groupUpdateMetadata(localIdentifiers: localIdentifiers) {
        case .modelDiff, .legacyRawString, .newGroup, .nonGroupUpdate:
            // This is a phenomenon exclusive to precomputed cases.
            return nil
        case .precomputed(let precomputedItems):
            return precomputedItems
                .asSingleUpdateItem?
                .representsSequenceOfRequestsAndCancels()
        }
    }

    /// It is possible (e.g. when restoring from a desktop-generated backup) to have a single info message
    /// containing both a ``sequenceOfInviteLinkRequestAndCancels`` and a single request to
    /// join that happens right after.
    /// If this is the latest message, and we get a new cancel, we want to collapse everything down to
    /// a single ``sequenceOfInviteLinkRequestAndCancels`` with an incremented count.
    func representsSequenceOfRequestsAndCancelsWithAdditionalRequestToJoin(
        localIdentifiers: LocalIdentifiers
    ) -> (Aci, count: UInt)? {
        switch groupUpdateMetadata(localIdentifiers: localIdentifiers) {
        case .newGroup, .nonGroupUpdate, .legacyRawString, .modelDiff:
            // This is a phenomenon exclusive to precomputed cases.
            return nil
        case .precomputed(let precomputedItems):
            let precomputedItems = precomputedItems.updateItems
            guard precomputedItems.count == 2 else {
                return nil
            }
            let firstItemRequester: Aci
            let firstItemCount: UInt
            let firstMessageIsTail: Bool
            switch precomputedItems[0] {
            case let .sequenceOfInviteLinkRequestAndCancels(requester, count, isTail):
                firstItemRequester = requester.wrappedValue
                firstItemCount = count
                firstMessageIsTail = isTail
            default:
                return nil
            }

            guard let secondItemRequester = precomputedItems[1]
                .representsCollapsibleSingleRequestToJoin()
            else {
                return nil
            }

            guard firstItemRequester == secondItemRequester else {
                return nil
            }
            owsAssertDebug(
                !firstMessageIsTail,
                "Should not be tail when there is a subsequent request!"
            )
            return (firstItemRequester, firstItemCount)
        }
    }
}

public extension TSInfoMessage.PersistableGroupUpdateItem {

    func representsSequenceOfRequestsAndCancels() -> (Aci, count: UInt)? {
        guard
            case let .sequenceOfInviteLinkRequestAndCancels(requester, count, _) = self
        else {
            return nil
        }
        return (requester.wrappedValue, count)
    }

    func representsCollapsibleSingleRequestToJoin() -> Aci? {
        switch self {
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
    }
}
