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
        transaction: DBWriteTransaction,
    )
}

class GroupUpdateInfoMessageInserterImpl: GroupUpdateInfoMessageInserter {
    private let dateProvider: DateProvider
    private let groupUpdateItemBuilder: GroupUpdateItemBuilder
    private let notificationPresenter: any NotificationPresenter

    init(
        dateProvider: @escaping DateProvider,
        groupUpdateItemBuilder: GroupUpdateItemBuilder,
        notificationPresenter: any NotificationPresenter,
    ) {
        self.dateProvider = dateProvider
        self.groupUpdateItemBuilder = groupUpdateItemBuilder
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
        transaction tx: DBWriteTransaction,
    ) {
        let updateItemsForNewMessage: [TSInfoMessage.PersistableGroupUpdateItem]

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
        let infoMessage: TSInfoMessage = .makeForGroupUpdate(
            timestamp: dateProvider().ows_millisecondsSince1970,
            spamReportingMetadata: spamReportingMetadata,
            groupThread: groupThread,
            updateItems: updateItemsForNewMessage,
        )
        infoMessage.anyInsert(transaction: tx)

        let wasLocalUserInGroup = oldGroupModel?.groupMembership.isLocalUserMemberOfAnyKind ?? false
        let isLocalUserInGroup = newGroupModel.groupMembership.isLocalUserMemberOfAnyKind
        let wasLocalUserRequestingMember = oldGroupModel?.groupMembership.isLocalUserRequestingMember ?? false
        let isLocalUserRequestingMember = newGroupModel.groupMembership.isLocalUserRequestingMember

        let isLocalUserUpdate: Bool
        switch groupUpdateSource {
        case .localUser:
            isLocalUserUpdate = true
        default:
            isLocalUserUpdate = false
        }
        if isLocalUserUpdate || (!wasLocalUserRequestingMember && isLocalUserRequestingMember) {
            infoMessage.markAsRead(
                atTimestamp: NSDate.ows_millisecondTimeStamp(),
                thread: groupThread,
                circumstance: .onThisDevice,
                shouldClearNotifications: true,
                transaction: tx,
            )
        } else if !wasLocalUserInGroup, isLocalUserInGroup {
            // Notify when the local user is added or invited to a group.
            notificationPresenter.notifyUser(
                forTSMessage: infoMessage,
                thread: groupThread,
                wantsSound: true,
                transaction: tx,
            )
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
