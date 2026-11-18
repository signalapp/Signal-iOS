//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol GroupUpdateInfoMessageInserter {
    func insertGroupUpdateInfoMessageForNewGroup(
        localIdentifiers: LocalIdentifiers,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        groupThread: TSGroupThread,
        groupModel: TSGroupModel,
        disappearingMessageToken: DisappearingMessageToken,
        groupUpdateSource: GroupUpdateSource,
        transaction: DBWriteTransaction,
    )

    func insertGroupUpdateInfoMessage(
        localIdentifiers: LocalIdentifiers,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        groupThread: TSGroupThread,
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken,
        newDisappearingMessageToken: DisappearingMessageToken,
        newlyLearnedPniToAciAssociations: [Pni: Aci],
        groupUpdateSource: GroupUpdateSource,
        dataDeletionRequest: GroupDataDeletionRequest?,
        transaction: DBWriteTransaction,
    )
}

class GroupUpdateInfoMessageInserterImpl: GroupUpdateInfoMessageInserter {
    private let dateProvider: DateProvider
    private let groupDataDeletionManager: any GroupDataDeletionManager
    private let groupUpdateItemBuilder: GroupUpdateItemBuilder
    private let isGroupDataDeletionEnabled: Bool
    private let notificationPresenter: any NotificationPresenter

    init(
        dateProvider: @escaping DateProvider,
        groupDataDeletionManager: any GroupDataDeletionManager,
        groupUpdateItemBuilder: GroupUpdateItemBuilder,
        isGroupDataDeletionEnabled: Bool,
        notificationPresenter: any NotificationPresenter,
    ) {
        self.dateProvider = dateProvider
        self.groupDataDeletionManager = groupDataDeletionManager
        self.groupUpdateItemBuilder = groupUpdateItemBuilder
        self.isGroupDataDeletionEnabled = isGroupDataDeletionEnabled
        self.notificationPresenter = notificationPresenter
    }

    func insertGroupUpdateInfoMessageForNewGroup(
        localIdentifiers: LocalIdentifiers,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        groupThread: TSGroupThread,
        groupModel: TSGroupModel,
        disappearingMessageToken: DisappearingMessageToken,
        groupUpdateSource: GroupUpdateSource,
        transaction tx: DBWriteTransaction,
    ) {
        _insertGroupUpdateInfoMessage(
            localIdentifiers: localIdentifiers,
            spamReportingMetadata: spamReportingMetadata,
            groupThread: groupThread,
            oldGroupModel: nil,
            newGroupModel: groupModel,
            oldDisappearingMessageToken: nil,
            newDisappearingMessageToken: disappearingMessageToken,
            newlyLearnedPniToAciAssociations: [:],
            groupUpdateSource: groupUpdateSource,
            dataDeletionRequest: nil,
            transaction: tx,
        )
    }

    func insertGroupUpdateInfoMessage(
        localIdentifiers: LocalIdentifiers,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        groupThread: TSGroupThread,
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken,
        newDisappearingMessageToken: DisappearingMessageToken,
        newlyLearnedPniToAciAssociations: [Pni: Aci],
        groupUpdateSource: GroupUpdateSource,
        dataDeletionRequest: GroupDataDeletionRequest?,
        transaction tx: DBWriteTransaction,
    ) {
        _insertGroupUpdateInfoMessage(
            localIdentifiers: localIdentifiers,
            spamReportingMetadata: spamReportingMetadata,
            groupThread: groupThread,
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            oldDisappearingMessageToken: oldDisappearingMessageToken,
            newDisappearingMessageToken: newDisappearingMessageToken,
            newlyLearnedPniToAciAssociations: newlyLearnedPniToAciAssociations,
            groupUpdateSource: groupUpdateSource,
            dataDeletionRequest: dataDeletionRequest,
            transaction: tx,
        )
    }

    private func _insertGroupUpdateInfoMessage(
        localIdentifiers: LocalIdentifiers,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        groupThread: TSGroupThread,
        oldGroupModel: TSGroupModel?,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken,
        newlyLearnedPniToAciAssociations: [Pni: Aci],
        groupUpdateSource: GroupUpdateSource,
        dataDeletionRequest: GroupDataDeletionRequest?,
        transaction tx: DBWriteTransaction,
    ) {
        var updateItemsForNewMessage: [TSInfoMessage.PersistableGroupUpdateItem]

        if
            let oldGroupModel,
            let invitedPniPromotions: InvitedPnisPromotionToFullMemberAcis = .from(
                oldGroupMembership: oldGroupModel.groupMembership,
                newGroupMembership: newGroupModel.groupMembership,
                newlyLearnedPniToAciAssociations: newlyLearnedPniToAciAssociations,
            )
        {
            /// We can't accurately detect PNI -> ACI promotions via the group
            /// model approach we'll take below, so we need to check for it in a
            /// one-off fashion here before going into that flow.
            updateItemsForNewMessage = invitedPniPromotions.promotions.map { pni, aci in
                return .invitedPniPromotedToFullMemberAci(
                    newMember: aci.codableUuid,
                    inviter: oldGroupModel.groupMembership.addedByAci(
                        forInvitedMember: .init(pni),
                    )?.codableUuid,
                )
            }
        } else {
            let persistibleGroupUpdateItems: [TSInfoMessage.PersistableGroupUpdateItem] = {
                if let oldGroupModel {
                    return groupUpdateItemBuilder.precomputedUpdateItemsByDiffingModels(
                        oldGroupModel: oldGroupModel,
                        newGroupModel: newGroupModel,
                        oldDisappearingMessageToken: oldDisappearingMessageToken,
                        newDisappearingMessageToken: newDisappearingMessageToken,
                        localIdentifiers: localIdentifiers,
                        groupUpdateSource: groupUpdateSource,
                        dataDeletionRequest: dataDeletionRequest,
                        tx: tx,
                    )
                } else {
                    return groupUpdateItemBuilder.precomputedUpdateItemsForNewGroup(
                        newGroupModel: newGroupModel,
                        newDisappearingMessageToken: newDisappearingMessageToken,
                        localIdentifiers: localIdentifiers,
                        groupUpdateSource: groupUpdateSource,
                        tx: tx,
                    )
                }
            }()

            let possiblyCollapsibleMembershipChange: PossiblyCollapsibleMembershipChange? = {
                if
                    persistibleGroupUpdateItems.count == 1,
                    case let .otherUserRequestedToJoin(requesterAci) = persistibleGroupUpdateItems.first!
                {
                    return .newJoinRequestFromSingleUser(requestingAci: requesterAci.wrappedValue)
                } else if
                    persistibleGroupUpdateItems.count == 1,
                    case let .otherUserRequestCanceledByOtherUser(requesterAci) = persistibleGroupUpdateItems.first!
                {
                    return .canceledJoinRequestFromSingleUser(cancelingAci: requesterAci.wrappedValue)
                }

                return nil
            }()

            if
                let possiblyCollapsibleMembershipChange,
                let collapseResult = handlePossiblyCollapsibleMembershipChange(
                    possiblyCollapsibleMembershipChange: possiblyCollapsibleMembershipChange,
                    localIdentifiers: localIdentifiers,
                    groupThread: groupThread,
                    newGroupModel: newGroupModel,
                    transaction: tx,
                )
            {
                switch collapseResult {
                case .updatesCollapsedIntoExistingMessage:
                    // If we collapsed this update into an existing info
                    // message, we should bail out before doing anything with a
                    // new info message.
                    return
                case let .updateItemForNewMessage(persistableGroupUpdateItem):
                    updateItemsForNewMessage = [persistableGroupUpdateItem]
                }
            } else {
                updateItemsForNewMessage = persistibleGroupUpdateItems
            }
        }

        /// This is true because the list of group update items we
        /// compute above will never be empty. Even if we get a strange group
        /// update that somehow doesn't produce a diff, we'll get back a list
        /// with a single "generic group update" item in it.
        owsPrecondition(!updateItemsForNewMessage.isEmpty)

        /// If this is a data deletion request, reset updateItemsForNewMessage to only contain that one item.
        /// The others should not be shown to the user because we are deleting the group content anyway.
        let dataDeletionItem = updateItemsForNewMessage.first(where: \.isLocalDataDeletion)
        if
            let dataDeletionItem,
            isGroupDataDeletionEnabled
        {
            updateItemsForNewMessage = [dataDeletionItem]
        }

        let timestamp = dateProvider().ows_millisecondsSince1970
        let insertedMessages: [(
            updateItem: TSInfoMessage.PersistableGroupUpdateItem,
            message: TSInfoMessage,
        )] = updateItemsForNewMessage.map { item in
            let message: TSInfoMessage = .makeForGroupUpdate(
                timestamp: timestamp,
                spamReportingMetadata: spamReportingMetadata,
                groupThread: groupThread,
                updateItems: [item],
            )
            message.anyInsert(transaction: tx)
            return (item, message)
        }

        if
            isGroupDataDeletionEnabled,
            dataDeletionItem != nil,
            let dataDeletionMessage = insertedMessages.first?.message
        {
            groupDataDeletionManager.deleteGroupData(
                groupThread: groupThread,
                preservedInteraction: dataDeletionMessage,
                localIdentifiers: localIdentifiers,
                tx: tx,
            )
        }

        let wasLocalUserRequestingMember = oldGroupModel?.groupMembership.isLocalUserRequestingMember ?? false
        let isLocalUserRequestingMember = newGroupModel.groupMembership.isLocalUserRequestingMember

        var isTerminatedGroup = false

        let isLocalUserUpdate: Bool
        switch groupUpdateSource {
        case .localUser:
            isLocalUserUpdate = true
        default:
            isLocalUserUpdate = false
        }
        if isLocalUserUpdate || (!wasLocalUserRequestingMember && isLocalUserRequestingMember) {
            let now = NSDate.ows_millisecondTimeStamp()
            insertedMessages.map(\.message).forEach { message in
                message.markAsRead(
                    atTimestamp: now,
                    thread: groupThread,
                    circumstance: .onThisDevice,
                    shouldClearNotifications: true,
                    transaction: tx,
                )
            }
        } else {
            // Notify when the local user is added or invited to a group.
            for groupJoinMessage in insertedMessages.compactMap({ item, message -> TSInfoMessage? in
                switch item {
                case
                    .localUserWasInvitedByLocalUser,
                    .localUserWasInvitedByOtherUser,
                    .localUserWasInvitedByUnknownUser,
                    .localUserAddedByLocalUser,
                    .localUserAddedByOtherUser,
                    .localUserAddedByUnknownUser,
                    .localUserInvitedAfterMigration,
                    .localUserJoined,
                    .localUserJoinedViaInviteLink:
                    return message
                default:
                    return nil
                }
            }) {
                notificationPresenter.notifyUser(
                    forTSMessage: groupJoinMessage,
                    thread: groupThread,
                    wantsSound: true,
                    transaction: tx,
                )
            }

            // Notify when the group ends.
            for groupTerminateMessage in insertedMessages.compactMap({ item, message -> TSInfoMessage? in
                switch item {
                case
                    .groupTerminatedByLocalUser,
                    .groupTerminatedByOtherUser,
                    .groupTerminatedByUnknownUser,
                    .groupTerminatedWithDataDeletionByLocalUser,
                    .groupTerminatedWithDataDeletionByOtherUser:
                    return message
                default:
                    return nil
                }
            }) {
                notificationPresenter.notifyUser(
                    forTSMessage: groupTerminateMessage,
                    thread: groupThread,
                    wantsSound: true,
                    transaction: tx,
                )
                isTerminatedGroup = true
            }
        }

        // Delete intents for terminated group.
        if isTerminatedGroup {
            DependenciesBridge.shared.threadDeletionManager.removeIntents(threadUniqueId: groupThread.uniqueId)
        }
    }
}

// MARK: -

/// Represents a group change that consists exclusively of invited PNIs being
/// promoted to a full-member ACI.
///
/// When a user is invited to a group by PNI and accept, their ACI joins the
/// group as a full member. To a ``TSGroupModel`` diff that looks like "someone
/// declined an invite and someone entirely unrelated joined the group", because
/// PNI:ACI association isn't tracked in the group model.
///
/// Consequently, we check for this in a one-off fashion here.
private struct InvitedPnisPromotionToFullMemberAcis {
    let promotions: [(pni: Pni, aci: Aci)]

    private init(promotions: [(pni: Pni, aci: Aci)]) {
        self.promotions = promotions
    }

    static func from(
        oldGroupMembership: GroupMembership,
        newGroupMembership: GroupMembership,
        newlyLearnedPniToAciAssociations: [Pni: Aci],
    ) -> InvitedPnisPromotionToFullMemberAcis? {
        let membersDiff: Set<ServiceId> = newGroupMembership.allMembersOfAnyKindServiceIds
            .symmetricDifference(oldGroupMembership.allMembersOfAnyKindServiceIds)

        var remainingMembers = membersDiff
        var promotions: [(pni: Pni, aci: Aci)] = []

        for possiblyInvitedPni in membersDiff.compactMap({ $0 as? Pni }) {
            if
                oldGroupMembership.isInvitedMember(possiblyInvitedPni),
                let fullMemberAci = newlyLearnedPniToAciAssociations[possiblyInvitedPni],
                newGroupMembership.isFullMember(fullMemberAci)
            {
                remainingMembers.remove(possiblyInvitedPni)
                remainingMembers.remove(fullMemberAci)

                promotions.append((pni: possiblyInvitedPni, aci: fullMemberAci))
            }
        }

        if remainingMembers.isEmpty, !promotions.isEmpty {
            return InvitedPnisPromotionToFullMemberAcis(promotions: promotions)
        }

        return nil
    }
}
