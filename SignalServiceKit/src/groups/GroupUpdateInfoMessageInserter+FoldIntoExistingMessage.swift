//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension GroupUpdateInfoMessageInserterImpl {
    /// Represents the result of collapsing updates into existing messages.
    enum CollapsibleMembershipChangeResult {
        /// Membership changes were collapsed into an existing, now-updated,
        /// info message.
        case updatesCollapsedIntoExistingMessage
        /// Update messages pertaining to the membership change are available
        /// and a new info message should be inserted containing them. Existing
        /// messages may have been updated while computing these updates.
        case updateMessageForNewMessage(TSInfoMessage.UpdateMessage)
    }

    func handlePossiblyCollapsibleMembershipChange(
        precomputedUpdateType: PrecomputedUpdateType,
        localAci: Aci,
        groupThread: TSGroupThread,
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken,
        newDisappearingMessageToken: DisappearingMessageToken,
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

        owsAssertDebug(mostRecentInfoMsg.newGroupModel == oldGroupModel)

        switch precomputedUpdateType {
        case .newJoinRequestFromSingleUser(let requestingAci):
            guard localAci != requestingAci else {
                return nil
            }

            return maybeUpdate(
                mostRecentInfoMsg: mostRecentInfoMsg,
                withNewJoinRequestFrom: requestingAci,
                transaction: transaction
            )
        case .canceledJoinRequestFromSingleUser(let cancelingAci):
            guard localAci != cancelingAci else {
                return nil
            }

            return maybeUpdate(
                mostRecentInfoMsg: mostRecentInfoMsg,
                andSecondMostRecentInfoMsg: secondMostRecentInfoMsgMaybe,
                withCanceledJoinRequestFrom: cancelingAci,
                newGroupModel: newGroupModel,
                transaction: transaction
            )
        case .bannedMemberChange:
            // If we know only banned members changed we don't want to make a
            // new info message, and should simply update the most recent info
            // message with the new group model so it accurately reflects the
            // latest group state, i.e. is aware of the now-banned members.

            mostRecentInfoMsg.setNewGroupModel(newGroupModel)
            mostRecentInfoMsg.anyUpsert(transaction: transaction)

            return .updatesCollapsedIntoExistingMessage
        case
                .invitedPnisPromotedToFullMemberAcis,
                .invitesRemoved:
            owsFail("Should never get here with a non-collapsible group update type!")
        }
    }

    private func maybeUpdate(
        mostRecentInfoMsg: TSInfoMessage,
        withNewJoinRequestFrom requestingAci: Aci,
        transaction: SDSAnyWriteTransaction
    ) -> CollapsibleMembershipChangeResult? {

        // For a new join request we always want a new info message. However,
        // if the new request matches collapsed request/cancel events on the
        // most recent message we should make a note on the new message that
        // it is no longer the tail of the sequence.
        //
        // Note that the new message might get collapsed further (into the
        // most recent message) in the future.

        guard
            let mostRecentUpdateMessage = mostRecentInfoMsg.updateMessages?.asSingleMessage,
            case let .sequenceOfInviteLinkRequestAndCancels(count, isTail) = mostRecentUpdateMessage,
            requestingAci == mostRecentInfoMsg.groupUpdateSourceAddress?.serviceId
        else {
            return nil
        }

        owsAssertDebug(isTail)

        mostRecentInfoMsg.setSingleUpdateMessage(
            singleUpdateMessage: .sequenceOfInviteLinkRequestAndCancels(count: count, isTail: false)
        )
        mostRecentInfoMsg.anyUpsert(transaction: transaction)

        return .updateMessageForNewMessage(
            .sequenceOfInviteLinkRequestAndCancels(count: 0, isTail: true)
        )
    }

    private func maybeUpdate(
        mostRecentInfoMsg: TSInfoMessage,
        andSecondMostRecentInfoMsg secondMostRecentInfoMsg: TSInfoMessage?,
        withCanceledJoinRequestFrom cancelingAci: Aci,
        newGroupModel: TSGroupModel,
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
            let mostRecentInfoMsgJoiner = mostRecentInfoMsg.representsSingleRequestToJoin(),
            cancelingAci == mostRecentInfoMsgJoiner
        else {
            return nil
        }

        if
            let secondMostRecentInfoMsg = secondMostRecentInfoMsg,
            let updateMessage = secondMostRecentInfoMsg.updateMessages?.asSingleMessage,
            case let .sequenceOfInviteLinkRequestAndCancels(count, isTail) = updateMessage,
            cancelingAci == secondMostRecentInfoMsg.groupUpdateSourceAddress?.serviceId
        {
            switch mostRecentInfoMsg.updateMessages?.asSingleMessage {
            case .sequenceOfInviteLinkRequestAndCancels(0, true)?: break
            default: owsFailDebug("Unexpected state for most recent info message")
            }

            mostRecentInfoMsg.anyRemove(transaction: transaction)

            owsAssertDebug(!isTail)
            secondMostRecentInfoMsg.setNewGroupModel(newGroupModel)
            secondMostRecentInfoMsg.setSingleUpdateMessage(
                singleUpdateMessage: .sequenceOfInviteLinkRequestAndCancels(count: count + 1, isTail: true)
            )
            secondMostRecentInfoMsg.anyUpsert(transaction: transaction)

            return .updatesCollapsedIntoExistingMessage
        } else {
            mostRecentInfoMsg.setNewGroupModel(newGroupModel)
            mostRecentInfoMsg.setSingleUpdateMessage(
                singleUpdateMessage: .sequenceOfInviteLinkRequestAndCancels(count: 1, isTail: true)
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

private extension TSInfoMessage.UpdateMessagesWrapper {
    var asSingleMessage: TSInfoMessage.UpdateMessage? {
        guard updateMessages.count == 1 else {
            return nil
        }

        return updateMessages.first
    }
}

private extension TSInfoMessage {
    func setSingleUpdateMessage(singleUpdateMessage: UpdateMessage) {
        setUpdateMessages(UpdateMessagesWrapper([singleUpdateMessage]))
    }

    func representsSingleRequestToJoin() -> Aci? {
        guard oldDisappearingMessageToken == newDisappearingMessageToken else {
            return nil
        }

        guard
            let oldGroupModel = oldGroupModel,
            let newGroupModel = newGroupModel,
            let groupUpdateSourceAddress = groupUpdateSourceAddress,
            let membershipEvent = GroupUpdateInfoMessageInserterImpl.PrecomputedUpdateType.from(
                oldGroupMembership: oldGroupModel.groupMembership,
                newGroupMembership: newGroupModel.groupMembership,
                newlyLearnedPniToAciAssociations: [:]
            ),
            case .newJoinRequestFromSingleUser(let requestingAci) = membershipEvent,
            requestingAci == groupUpdateSourceAddress.serviceId
        else {
            return nil
        }

        return requestingAci
    }
}
