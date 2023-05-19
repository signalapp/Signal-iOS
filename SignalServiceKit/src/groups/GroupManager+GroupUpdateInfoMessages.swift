//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

private enum CollapseRelatedMembershipEvent {
    case newJoinRequestFromSingleUser(address: SignalServiceAddress)
    case canceledJoinRequestFromSingleUser(address: SignalServiceAddress)
    case onlyBannedMemberChange

    static func from(
        oldGroupMembership: GroupMembership,
        newGroupMembership: GroupMembership
    ) -> CollapseRelatedMembershipEvent? {
        let membersDiff = newGroupMembership.allMembersOfAnyKind
            .symmetricDifference(oldGroupMembership.allMembersOfAnyKind)

        let bannedDiff = newGroupMembership.bannedMemberAddresses
            .symmetricDifference(oldGroupMembership.bannedMemberAddresses)

        if bannedDiff.isEmpty,
           membersDiff.count == 1,
           let changedMember = membersDiff.first {
            if newGroupMembership.isRequestingMember(changedMember) {
                return .newJoinRequestFromSingleUser(address: changedMember)
            } else if oldGroupMembership.isRequestingMember(changedMember) {
                return .canceledJoinRequestFromSingleUser(address: changedMember)
            }
        } else if membersDiff.isEmpty, !bannedDiff.isEmpty {
            return .onlyBannedMemberChange
        }

        return nil
    }
}

extension GroupManager {
    // NOTE: This should only be called by GroupManager and by DebugUI.
    @discardableResult
    public static func insertGroupUpdateInfoMessage(groupThread: TSGroupThread,
                                                    oldGroupModel: TSGroupModel?,
                                                    newGroupModel: TSGroupModel,
                                                    oldDisappearingMessageToken: DisappearingMessageToken?,
                                                    newDisappearingMessageToken: DisappearingMessageToken,
                                                    groupUpdateSourceAddress: SignalServiceAddress?,
                                                    transaction: SDSAnyWriteTransaction) -> TSInfoMessage? {

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return nil
        }

        var userInfoForNewMessage: [InfoMessageUserInfoKey: Any] = [:]

        if let oldGroupModel = oldGroupModel,
           let oldDisappearingMessageToken = oldDisappearingMessageToken,
           let groupUpdateSourceAddress = groupUpdateSourceAddress {
            switch Self.maybeCollapseUpdateIntoExistingMessages(
                localAddress: localAddress,
                groupThread: groupThread,
                oldGroupModel: oldGroupModel,
                newGroupModel: newGroupModel,
                oldDisappearingMessageToken: oldDisappearingMessageToken,
                newDisappearingMessageToken: newDisappearingMessageToken,
                groupUpdateSourceAddress: groupUpdateSourceAddress,
                transaction: transaction
            ) {
            case .noUpdate:
                break
            case .updatedExisting(let existingMessage):
                return existingMessage
            case .updatedExistingAndShouldAddNew(let seededUserInfo):
                userInfoForNewMessage = seededUserInfo
            }
        }

        userInfoForNewMessage[.newGroupModel] = newGroupModel
        userInfoForNewMessage[.newDisappearingMessageToken] = newDisappearingMessageToken

        if let oldGroupModel = oldGroupModel {
            userInfoForNewMessage[.oldGroupModel] = oldGroupModel
        }
        if let oldDisappearingMessageToken = oldDisappearingMessageToken {
            userInfoForNewMessage[.oldDisappearingMessageToken] = oldDisappearingMessageToken
        }
        if let groupUpdateSourceAddress = groupUpdateSourceAddress {
            userInfoForNewMessage[.groupUpdateSourceAddress] = groupUpdateSourceAddress
        }
        let infoMessage = TSInfoMessage(thread: groupThread,
                                        messageType: .typeGroupUpdate,
                                        infoMessageUserInfo: userInfoForNewMessage)
        infoMessage.anyInsert(transaction: transaction)

        let wasLocalUserInGroup = oldGroupModel?.groupMembership.isMemberOfAnyKind(localAddress) ?? false
        let isLocalUserInGroup = newGroupModel.groupMembership.isMemberOfAnyKind(localAddress)

        if let groupUpdateSourceAddress = groupUpdateSourceAddress,
           groupUpdateSourceAddress.isLocalAddress {
            infoMessage.markAsRead(atTimestamp: NSDate.ows_millisecondTimeStamp(),
                                   thread: groupThread,
                                   circumstance: .onThisDevice,
                                   shouldClearNotifications: true,
                                   transaction: transaction)
        } else if !wasLocalUserInGroup && isLocalUserInGroup {
            // Notify when the local user is added or invited to a group.
            self.notificationsManager?.notifyUser(
                forTSMessage: infoMessage,
                thread: groupThread,
                wantsSound: true,
                transaction: transaction
            )
        }
        return infoMessage
    }
}

private extension GroupManager {
    typealias UpdateMessages = TSInfoMessage.UpdateMessages

    enum UpdateExistingMessagesResult {
        case noUpdate
        case updatedExisting(existingMessage: TSInfoMessage)
        case updatedExistingAndShouldAddNew(seededUserInfo: [InfoMessageUserInfoKey: Any])
    }

    static func maybeCollapseUpdateIntoExistingMessages(
        localAddress: SignalServiceAddress,
        groupThread: TSGroupThread,
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken,
        newDisappearingMessageToken: DisappearingMessageToken,
        groupUpdateSourceAddress: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) -> UpdateExistingMessagesResult {
        guard newDisappearingMessageToken == oldDisappearingMessageToken else {
            // Do not update existing if disappearing messages were updated
            return .noUpdate
        }

        guard let membershipEvent = CollapseRelatedMembershipEvent.from(
            oldGroupMembership: oldGroupModel.groupMembership,
            newGroupMembership: newGroupModel.groupMembership
        ) else {
            return .noUpdate
        }

        guard
            let (mostRecentInfoMsg, secondMostRecentInfoMsgMaybe) = Self.mostRecentVisibleInteractionsAsInfoMessages(
                forGroupThread: groupThread,
                withTransaction: transaction
            )
        else {
            return .noUpdate
        }

        owsAssertDebug(mostRecentInfoMsg.newGroupModel == oldGroupModel)

        switch membershipEvent {
        case .newJoinRequestFromSingleUser(let requestingAddress):
            guard localAddress != requestingAddress else {
                return .noUpdate
            }

            return maybeUpdate(
                mostRecentInfoMsg: mostRecentInfoMsg,
                withNewJoinRequestFrom: requestingAddress,
                transaction: transaction
            )
        case .canceledJoinRequestFromSingleUser(let cancelingAddress):
            guard localAddress != cancelingAddress else {
                return .noUpdate
            }

            return maybeUpdate(
                mostRecentInfoMsg: mostRecentInfoMsg,
                andSecondMostRecentInfoMsg: secondMostRecentInfoMsgMaybe,
                withCanceledJoinRequestFrom: cancelingAddress,
                newGroupModel: newGroupModel,
                oldDisappearingMessageToken: oldDisappearingMessageToken,
                newDisappearingMessageToken: newDisappearingMessageToken,
                transaction: transaction
            )
        case .onlyBannedMemberChange:
            // If we know only banned members changed we don't want to make a
            // new info message, and should simply update the most recent info
            // message with the new group model so it accurately reflects the
            // latest group state, i.e. is aware of the now-banned members.

            mostRecentInfoMsg.setNewGroupModel(newGroupModel)
            mostRecentInfoMsg.anyUpsert(transaction: transaction)

            return .updatedExisting(existingMessage: mostRecentInfoMsg)
        }
    }

    private static func maybeUpdate(
        mostRecentInfoMsg: TSInfoMessage,
        withNewJoinRequestFrom requestingAddress: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) -> UpdateExistingMessagesResult {

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
            requestingAddress == mostRecentInfoMsg.groupUpdateSourceAddress
        else {
            return .noUpdate
        }

        owsAssertDebug(isTail)

        mostRecentInfoMsg.setUpdateMessages(UpdateMessages(
            .sequenceOfInviteLinkRequestAndCancels(count: count, isTail: false)
        ))
        mostRecentInfoMsg.anyUpsert(transaction: transaction)

        return .updatedExistingAndShouldAddNew(seededUserInfo: [
            .updateMessages: UpdateMessages(.sequenceOfInviteLinkRequestAndCancels(count: 0, isTail: true))
        ])
    }

    private static func maybeUpdate(
        mostRecentInfoMsg: TSInfoMessage,
        andSecondMostRecentInfoMsg secondMostRecentInfoMsg: TSInfoMessage?,
        withCanceledJoinRequestFrom cancelingAddress: SignalServiceAddress,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken,
        newDisappearingMessageToken: DisappearingMessageToken,
        transaction: SDSAnyWriteTransaction
    ) -> UpdateExistingMessagesResult {

        // If the most recent message represents the join request that's being
        // canceled, we want to collapse into it.
        //
        // Further, if the second-most-recent message represents already-
        // collapsed join/cancel events from the same address, we can simply
        // increment that message's collapse counter and delete the most recent
        // message.

        guard
            let mostRecentInfoMsgJoiner = mostRecentInfoMsg.representsSingleRequestToJoin(),
            cancelingAddress == mostRecentInfoMsgJoiner
        else {
            return .noUpdate
        }

        if
            let secondMostRecentInfoMsg = secondMostRecentInfoMsg,
            let updateMessage = secondMostRecentInfoMsg.updateMessages?.asSingleMessage,
            case let .sequenceOfInviteLinkRequestAndCancels(count, isTail) = updateMessage,
            cancelingAddress == secondMostRecentInfoMsg.groupUpdateSourceAddress
        {
            switch mostRecentInfoMsg.updateMessages?.asSingleMessage {
            case .some(.sequenceOfInviteLinkRequestAndCancels(0, true)): break
            default: owsFailDebug("Unexpected state for most recent info message")
            }
            mostRecentInfoMsg.anyRemove(transaction: transaction)

            owsAssertDebug(!isTail)
            secondMostRecentInfoMsg.setNewGroupModel(newGroupModel)
            secondMostRecentInfoMsg.setUpdateMessages(TSInfoMessage.UpdateMessages(
                .sequenceOfInviteLinkRequestAndCancels(count: count + 1, isTail: true)
            ))
            secondMostRecentInfoMsg.anyUpsert(transaction: transaction)

            return .updatedExisting(existingMessage: secondMostRecentInfoMsg)
        } else {
            mostRecentInfoMsg.setNewGroupModel(newGroupModel)
            mostRecentInfoMsg.setUpdateMessages(UpdateMessages(
                .sequenceOfInviteLinkRequestAndCancels(count: 1, isTail: true)
            ))
            mostRecentInfoMsg.anyUpsert(transaction: transaction)

            return .updatedExisting(existingMessage: mostRecentInfoMsg)
        }
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

private extension TSInfoMessage {
    func representsSingleRequestToJoin() -> SignalServiceAddress? {
        guard oldDisappearingMessageToken == newDisappearingMessageToken else {
            return nil
        }

        guard let oldGroupModel = oldGroupModel,
              let newGroupModel = newGroupModel,
              let groupUpdateSourceAddress = groupUpdateSourceAddress,
              let membershipEvent = CollapseRelatedMembershipEvent.from(
                oldGroupMembership: oldGroupModel.groupMembership,
                newGroupMembership: newGroupModel.groupMembership
              ),
              case .newJoinRequestFromSingleUser(let requestingAddress) = membershipEvent,
              requestingAddress == groupUpdateSourceAddress
        else {
            return nil
        }

        return requestingAddress
    }
}
