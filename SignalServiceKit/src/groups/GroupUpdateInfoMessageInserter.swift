//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol GroupUpdateInfoMessageInserter {
    func insertGroupUpdateInfoMessage(
        localIdentifiers: LocalIdentifiers,
        groupThread: TSGroupThread,
        oldGroupModel: TSGroupModel?,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken,
        newlyLearnedPniToAciAssociations: [UntypedServiceId: UntypedServiceId],
        groupUpdateSourceAddress: SignalServiceAddress?,
        transaction: DBWriteTransaction
    )
}

class GroupUpdateInfoMessageInserterImpl: GroupUpdateInfoMessageInserter {
    let notificationsManager: NotificationsProtocol

    init(notificationsManager: NotificationsProtocol) {
        self.notificationsManager = notificationsManager
    }

    func insertGroupUpdateInfoMessage(
        localIdentifiers: LocalIdentifiers,
        groupThread: TSGroupThread,
        oldGroupModel: TSGroupModel?,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken,
        newlyLearnedPniToAciAssociations: [UntypedServiceId: UntypedServiceId],
        groupUpdateSourceAddress: SignalServiceAddress?,
        transaction v2Transaction: DBWriteTransaction
    ) {
        let transaction = SDSDB.shimOnlyBridge(v2Transaction)

        var updateMessagesForNewMessage: [TSInfoMessage.UpdateMessage] = []

        if
            let oldGroupModel,
            let oldDisappearingMessageToken,
            oldDisappearingMessageToken == newDisappearingMessageToken,
            let precomputedUpdateType = PrecomputedUpdateType.from(
                oldGroupMembership: oldGroupModel.groupMembership,
                newGroupMembership: newGroupModel.groupMembership,
                newlyLearnedPniToAciAssociations: newlyLearnedPniToAciAssociations
            )
        {
            switch precomputedUpdateType {
            case
                    .newJoinRequestFromSingleUser,
                    .canceledJoinRequestFromSingleUser,
                    .bannedMemberChange:
                switch handlePossiblyCollapsibleMembershipChange(
                    precomputedUpdateType: precomputedUpdateType,
                    localAci: localIdentifiers.aci.untypedServiceId,
                    groupThread: groupThread,
                    oldGroupModel: oldGroupModel,
                    newGroupModel: newGroupModel,
                    oldDisappearingMessageToken: oldDisappearingMessageToken,
                    newDisappearingMessageToken: newDisappearingMessageToken,
                    transaction: transaction
                ) {
                case nil:
                    break
                case .updatesCollapsedIntoExistingMessage?:
                    return
                case .updateMessageForNewMessage(let updateMessage)?:
                    updateMessagesForNewMessage.append(updateMessage)
                }
            case .invitedPnisPromotedToFullMemberAcis(let promotions):
                for (pni, aci) in promotions {
                    updateMessagesForNewMessage.append(
                        .invitedPniPromotedToFullMemberAci(pni: pni, aci: aci)
                    )
                }
            case .invitesRemoved(let inviteeServiceIds):
                for removedInviteServiceId in inviteeServiceIds {
                    updateMessagesForNewMessage.append(
                        .inviteRemoved(
                            invitee: removedInviteServiceId,
                            wasLocalUser: localIdentifiers.contains(serviceId: removedInviteServiceId)
                        )
                    )
                }
            }
        }

        var userInfoForNewMessage: [InfoMessageUserInfoKey: Any] = [:]

        userInfoForNewMessage[.newGroupModel] = newGroupModel
        userInfoForNewMessage[.newDisappearingMessageToken] = newDisappearingMessageToken

        if let oldGroupModel = oldGroupModel {
            userInfoForNewMessage[.oldGroupModel] = oldGroupModel
        }

        if let oldDisappearingMessageToken = oldDisappearingMessageToken {
            userInfoForNewMessage[.oldDisappearingMessageToken] = oldDisappearingMessageToken
        }

        if let groupUpdateSourceAddress = groupUpdateSourceAddress {
            // If we know to whom this update should be attributed, record it.
            // Additionally record whether, while processing, we know that the
            // local user is the updater. This works around scenarios in which
            // the updating address may refer to a different user in the future,
            // such as a PNI moving from account to account.

            userInfoForNewMessage[.groupUpdateSourceAddress] = groupUpdateSourceAddress
            userInfoForNewMessage[.updaterKnownToBeLocalUser] = localIdentifiers.contains(address: groupUpdateSourceAddress)
        } else {
            userInfoForNewMessage[.updaterKnownToBeLocalUser] = false
        }

        if !updateMessagesForNewMessage.isEmpty {
            userInfoForNewMessage[.updateMessages] = TSInfoMessage.UpdateMessagesWrapper(updateMessagesForNewMessage)
        }

        let infoMessage = TSInfoMessage(
            thread: groupThread,
            messageType: .typeGroupUpdate,
            infoMessageUserInfo: userInfoForNewMessage
        )
        infoMessage.anyInsert(transaction: transaction)

        let wasLocalUserInGroup = oldGroupModel?.groupMembership.isLocalUserMemberOfAnyKind ?? false
        let isLocalUserInGroup = newGroupModel.groupMembership.isLocalUserMemberOfAnyKind

        if
            let groupUpdateSourceAddress,
            localIdentifiers.contains(address: groupUpdateSourceAddress)
        {
            infoMessage.markAsRead(
                atTimestamp: NSDate.ows_millisecondTimeStamp(),
                thread: groupThread,
                circumstance: .onThisDevice,
                shouldClearNotifications: true,
                transaction: transaction
            )
        } else if !wasLocalUserInGroup && isLocalUserInGroup {
            // Notify when the local user is added or invited to a group.
            notificationsManager.notifyUser(
                forTSMessage: infoMessage,
                thread: groupThread,
                wantsSound: true,
                transaction: transaction
            )
        }
    }
}
