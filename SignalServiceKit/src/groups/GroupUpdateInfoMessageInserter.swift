//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol GroupUpdateInfoMessageInserter {
    func insertGroupUpdateInfoMessageForNewGroup(
        localIdentifiers: LocalIdentifiers,
        groupThread: TSGroupThread,
        groupModel: TSGroupModel,
        disappearingMessageToken: DisappearingMessageToken,
        groupUpdateSource: GroupUpdateSource,
        transaction: DBWriteTransaction
    )

    func insertGroupUpdateInfoMessage(
        localIdentifiers: LocalIdentifiers,
        groupThread: TSGroupThread,
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken,
        newDisappearingMessageToken: DisappearingMessageToken,
        newlyLearnedPniToAciAssociations: [Pni: Aci],
        groupUpdateSource: GroupUpdateSource,
        transaction: DBWriteTransaction
    )
}

class GroupUpdateInfoMessageInserterImpl: GroupUpdateInfoMessageInserter {
    let notificationsManager: NotificationsProtocol

    init(notificationsManager: NotificationsProtocol) {
        self.notificationsManager = notificationsManager
    }

    public func insertGroupUpdateInfoMessageForNewGroup(
        localIdentifiers: LocalIdentifiers,
        groupThread: TSGroupThread,
        groupModel: TSGroupModel,
        disappearingMessageToken: DisappearingMessageToken,
        groupUpdateSource: GroupUpdateSource,
        transaction v2Transaction: DBWriteTransaction
    ) {
        _insertGroupUpdateInfoMessage(
            localIdentifiers: localIdentifiers,
            groupThread: groupThread,
            oldGroupModel: nil,
            newGroupModel: groupModel,
            oldDisappearingMessageToken: nil,
            newDisappearingMessageToken: disappearingMessageToken,
            newlyLearnedPniToAciAssociations: [:],
            groupUpdateSource: groupUpdateSource,
            transaction: v2Transaction
        )
    }

    public func insertGroupUpdateInfoMessage(
        localIdentifiers: LocalIdentifiers,
        groupThread: TSGroupThread,
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken,
        newDisappearingMessageToken: DisappearingMessageToken,
        newlyLearnedPniToAciAssociations: [Pni: Aci],
        groupUpdateSource: GroupUpdateSource,
        transaction v2Transaction: DBWriteTransaction
    ) {
        _insertGroupUpdateInfoMessage(
            localIdentifiers: localIdentifiers,
            groupThread: groupThread,
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            oldDisappearingMessageToken: oldDisappearingMessageToken,
            newDisappearingMessageToken: newDisappearingMessageToken,
            newlyLearnedPniToAciAssociations: newlyLearnedPniToAciAssociations,
            groupUpdateSource: groupUpdateSource,
            transaction: v2Transaction
        )
    }

    private func _insertGroupUpdateInfoMessage(
        localIdentifiers: LocalIdentifiers,
        groupThread: TSGroupThread,
        oldGroupModel: TSGroupModel?,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken,
        newlyLearnedPniToAciAssociations: [Pni: Aci],
        groupUpdateSource: GroupUpdateSource,
        transaction v2Transaction: DBWriteTransaction
    ) {
        let transaction = SDSDB.shimOnlyBridge(v2Transaction)

        var updateItemsForNewMessage: [TSInfoMessage.PersistableGroupUpdateItem] = []

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
                    localIdentifiers: localIdentifiers,
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
                case .updateItemForNewMessage(let updateItem)?:
                    updateItemsForNewMessage.append(updateItem)
                }
            case .invitedPnisPromotedToFullMemberAcis(let promotions):
                for (pni, aci) in promotions {
                    updateItemsForNewMessage.append(
                        .invitedPniPromotedToFullMemberAci(
                            newMember: aci.codableUuid,
                            inviter: oldGroupModel.groupMembership.addedByAci(
                                forInvitedMember: .init(pni)
                            )?.codableUuid
                        )
                    )
                }
            case .invitesRemoved(let inviteeServiceIds):
                // Maps from the remover's aci (or unknown) to count.
                var unnamedInvitesRemoved = [Aci?: Int]()
                var inviteesRemovedByLocalUser = [ServiceId]()
                for inviteeServiceId in inviteeServiceIds {
                    let item = Self.persistableUpdateForRemovedInvite(
                        inviteeServiceId: inviteeServiceId,
                        groupUpdateSource: groupUpdateSource,
                        oldGroupMembership: oldGroupModel.groupMembership,
                        localIdentifiers: localIdentifiers,
                        unnamedInvitesRemoved: &unnamedInvitesRemoved,
                        inviteesRemovedByLocalUser: &inviteesRemovedByLocalUser
                    )
                    if let item {
                        updateItemsForNewMessage.append(item)
                    }
                }
                if inviteesRemovedByLocalUser.count == 1 {
                    updateItemsForNewMessage.append(
                        .otherUserInviteRevokedByLocalUser(
                            invitee: inviteesRemovedByLocalUser[0].codableUppercaseString
                        )
                    )
                } else if inviteesRemovedByLocalUser.count > 1 {
                    updateItemsForNewMessage.append(
                        .unnamedUserInvitesWereRevokedByLocalUser(
                            count: UInt(inviteesRemovedByLocalUser.count)
                        )
                    )
                }
                for (removerAci, removedInviteCount) in unnamedInvitesRemoved {
                    guard removedInviteCount > 0 else {
                        continue
                    }
                    if let removerAci {
                        updateItemsForNewMessage.append(
                            .unnamedUserInvitesWereRevokedByOtherUser(
                                updaterAci: removerAci.codableUuid,
                                count: UInt(removedInviteCount)
                            )
                        )
                    } else {
                        updateItemsForNewMessage.append(
                            .unnamedUserInvitesWereRevokedByUnknownUser(
                                count: UInt(removedInviteCount)
                            )
                        )
                    }
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

        TSInfoMessage.insertGroupUpdateSource(
            groupUpdateSource,
            intoInfoMessageUserInfoDict: &userInfoForNewMessage,
            localIdentifiers: localIdentifiers
        )

        if !updateItemsForNewMessage.isEmpty {
            userInfoForNewMessage[.groupUpdateItems] = TSInfoMessage.PersistableGroupUpdateItemsWrapper(updateItemsForNewMessage)
        }

        let infoMessage = TSInfoMessage(
            thread: groupThread,
            messageType: .typeGroupUpdate,
            infoMessageUserInfo: userInfoForNewMessage
        )
        infoMessage.anyInsert(transaction: transaction)

        let wasLocalUserInGroup = oldGroupModel?.groupMembership.isLocalUserMemberOfAnyKind ?? false
        let isLocalUserInGroup = newGroupModel.groupMembership.isLocalUserMemberOfAnyKind

        let isLocalUserUpdate: Bool
        switch groupUpdateSource {
        case .unknown:
            isLocalUserUpdate = false
        case .legacyE164(let e164):
            isLocalUserUpdate = localIdentifiers.contains(phoneNumber: e164)
        case .aci(let aci):
            isLocalUserUpdate = localIdentifiers.contains(serviceId: aci)
        case .rejectedInviteToPni(let pni):
            isLocalUserUpdate = localIdentifiers.contains(serviceId: pni)
        }
        if isLocalUserUpdate {
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

    private static func persistableUpdateForRemovedInvite(
        inviteeServiceId: ServiceId,
        groupUpdateSource: GroupUpdateSource,
        oldGroupMembership: GroupMembership,
        localIdentifiers: LocalIdentifiers,
        unnamedInvitesRemoved: inout [Aci?: Int],
        inviteesRemovedByLocalUser: inout [ServiceId]
    ) -> TSInfoMessage.PersistableGroupUpdateItem? {
        let inviteeIsLocalUser = localIdentifiers.contains(
            serviceId: inviteeServiceId
        )
        let inviterAci = oldGroupMembership.addedByAci(
            forInvitedMember: .init(inviteeServiceId)
        )
        let inviterIsLocalUser = inviterAci == localIdentifiers.aci
        switch groupUpdateSource {
        case .unknown:
            if inviteeIsLocalUser {
                return .localUserInviteRevokedByUnknownUser
            } else {
                unnamedInvitesRemoved[nil] = (unnamedInvitesRemoved[nil] ?? 0) + 1
                return nil
            }
        case .legacyE164:
            owsFailDebug("Cannot remove invites from an e164")
            return nil
        case .aci(let revokerAci):
            let revokerIsLocalUser = revokerAci == localIdentifiers.aci
            if inviteeIsLocalUser {
                if revokerIsLocalUser {
                    if let inviterAci {
                        return .localUserDeclinedInviteFromInviter(
                            inviterAci: inviterAci.codableUuid
                        )
                    } else {
                        return .localUserDeclinedInviteFromUnknownUser
                    }
                } else {
                    return .localUserInviteRevoked(
                        revokerAci: revokerAci.codableUuid
                    )
                }
            } else if revokerAci == inviteeServiceId {
                if inviterIsLocalUser {
                    return .otherUserDeclinedInviteFromLocalUser(
                        invitee: inviteeServiceId.codableUppercaseString
                    )
                } else if let inviterAci {
                    return .otherUserDeclinedInviteFromInviter(
                        invitee: inviteeServiceId.codableUppercaseString,
                        inviterAci: inviterAci.codableUuid
                    )
                } else {
                    return .otherUserDeclinedInviteFromUnknownUser(
                        invitee: inviteeServiceId.codableUppercaseString
                    )
                }
            } else {
                if revokerIsLocalUser {
                    inviteesRemovedByLocalUser.append(inviteeServiceId)
                    return nil
                } else {
                    unnamedInvitesRemoved[revokerAci] =
                        (unnamedInvitesRemoved[revokerAci] ?? 0) + 1
                    return nil
                }
            }
        case .rejectedInviteToPni(let revokerPni):
            // Only two options: we rejected our own pni invite,
            // or another user rejected their own pni invite.
            if revokerPni == localIdentifiers.pni {
                if let inviterAci {
                    return .localUserDeclinedInviteFromInviter(
                        inviterAci: inviterAci.codableUuid
                    )
                } else {
                    return.localUserDeclinedInviteFromUnknownUser
                }
            } else {
                if let inviterAci {
                    if inviterAci == localIdentifiers.aci {
                        return .otherUserDeclinedInviteFromLocalUser(
                            invitee: inviteeServiceId.codableUppercaseString
                        )
                    } else {
                        return.otherUserDeclinedInviteFromInviter(
                            invitee: inviteeServiceId.codableUppercaseString,
                            inviterAci: inviterAci.codableUuid
                        )
                    }
                } else {
                    return .otherUserDeclinedInviteFromUnknownUser(
                        invitee: inviteeServiceId.codableUppercaseString
                    )
                }
            }
        }
    }
}
