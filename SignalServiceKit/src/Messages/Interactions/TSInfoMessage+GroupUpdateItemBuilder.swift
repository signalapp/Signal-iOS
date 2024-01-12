//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public protocol GroupUpdateItemBuilder {
    /// Build a list of group updates using the given precomputed, persisted
    /// update items.
    ///
    /// - Important
    /// If there are precomputed update items available, this method should be
    /// preferred over all others.
    func displayableUpdateItemsForPrecomputed(
        precomputedUpdateItems: [TSInfoMessage.PersistableGroupUpdateItem],
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction
    ) -> [DisplayableGroupUpdateItem]

    /// Build group update items for a just-inserted group.
    ///
    /// - Note
    /// You should use this method if there are neither precomputed update items
    /// nor an "old group model" available.
    func precomputedUpdateItemsForNewGroup(
        newGroupModel: TSGroupModel,
        newDisappearingMessageToken: DisappearingMessageToken?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSource: GroupUpdateSource,
        tx: DBReadTransaction
    ) -> [TSInfoMessage.PersistableGroupUpdateItem]

    /// Build a list of group updates by "diffing" the old and new group states.
    ///
    /// - Note
    /// You should use this method if there are not precomputed update items,
    /// but we do have both an "old/new group model" from before and after a
    /// group update.
    func precomputedUpdateItemsByDiffingModels(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSource: GroupUpdateSource,
        tx: DBReadTransaction
    ) -> [TSInfoMessage.PersistableGroupUpdateItem]
}

extension GroupUpdateItemBuilder {
    /// Build group update items for a just-inserted group.
    ///
    /// - Note
    /// You should use this method if there are neither precomputed update items
    /// nor an "old group model" available.
    func displayableUpdateItemsForNewGroup(
        newGroupModel: TSGroupModel,
        newDisappearingMessageToken: DisappearingMessageToken?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSource: GroupUpdateSource,
        tx: DBReadTransaction
    ) -> [DisplayableGroupUpdateItem] {
        let precomputedItems = precomputedUpdateItemsForNewGroup(
            newGroupModel: newGroupModel,
            newDisappearingMessageToken: newDisappearingMessageToken,
            localIdentifiers: localIdentifiers,
            groupUpdateSource: groupUpdateSource,
            tx: tx
        )
        return displayableUpdateItemsForPrecomputed(
            precomputedUpdateItems: precomputedItems,
            localIdentifiers: localIdentifiers,
            tx: tx
        )
    }

    /// Build a list of group updates by "diffing" the old and new group states.
    ///
    /// - Note
    /// You should use this method if there are not precomputed update items,
    /// but we do have both an "old/new group model" from before and after a
    /// group update.
    func displayableUpdateItemsByDiffingModels(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSource: GroupUpdateSource,
        tx: DBReadTransaction
    ) -> [DisplayableGroupUpdateItem] {
        let precomputedItems = precomputedUpdateItemsByDiffingModels(
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            oldDisappearingMessageToken: oldDisappearingMessageToken,
            newDisappearingMessageToken: newDisappearingMessageToken,
            localIdentifiers: localIdentifiers,
            groupUpdateSource: groupUpdateSource,
            tx: tx
        )
        return displayableUpdateItemsForPrecomputed(
            precomputedUpdateItems: precomputedItems,
            localIdentifiers: localIdentifiers,
            tx: tx
        )
    }
}

public struct GroupUpdateItemBuilderImpl: GroupUpdateItemBuilder {
    private let contactsManager: Shims.ContactsManager
    private let signalRecipientStore: SignalRecipientStore

    init(
        contactsManager: Shims.ContactsManager,
        signalRecipientStore: SignalRecipientStore
    ) {
        self.contactsManager = contactsManager
        self.signalRecipientStore = signalRecipientStore
    }

    public func precomputedUpdateItemsForNewGroup(
        newGroupModel: TSGroupModel,
        newDisappearingMessageToken: DisappearingMessageToken?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSource: GroupUpdateSource,
        tx: DBReadTransaction
    ) -> [TSInfoMessage.PersistableGroupUpdateItem] {
        let groupUpdateSource = groupUpdateSource.sanitize(
            signalRecipientStore: signalRecipientStore,
            tx: tx
        )

        var precomputedItems = NewGroupUpdateItemBuilder(
            contactsManager: contactsManager
        ).buildGroupUpdateItems(
            newGroupModel: newGroupModel,
            newDisappearingMessageToken: newDisappearingMessageToken,
            groupUpdateSource: groupUpdateSource,
            localIdentifiers: localIdentifiers
        )

        return validateUpdateItemsNotEmpty(
            tentativeUpdateItems: precomputedItems,
            groupUpdateSource: groupUpdateSource,
            localIdentifiers: localIdentifiers
        )
    }

    public func displayableUpdateItemsForPrecomputed(
        precomputedUpdateItems: [TSInfoMessage.PersistableGroupUpdateItem],
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction
    ) -> [DisplayableGroupUpdateItem] {
        let precomputedUpdateItems = validateUpdateItemsNotEmpty(
            tentativeUpdateItems: precomputedUpdateItems,
            groupUpdateSource: .unknown,
            localIdentifiers: localIdentifiers
        )

        let builder = PrecomputedGroupUpdateItemBuilder(
            contactsManager: contactsManager
        )
        let items = precomputedUpdateItems.map {
            builder.buildGroupUpdateItem(
                precomputedUpdateItem: $0,
                localIdentifiers: localIdentifiers,
                tx: tx
            )
        }

        return items
    }

    public func precomputedUpdateItemsByDiffingModels(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSource: GroupUpdateSource,
        tx: DBReadTransaction
    ) -> [TSInfoMessage.PersistableGroupUpdateItem] {
        // Sanitize first so we map e164s to known acis.
        let groupUpdateSource = groupUpdateSource.sanitize(
            signalRecipientStore: signalRecipientStore,
            tx: tx
        )

        let precomputedItems = DiffingGroupUpdateItemBuilder(
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            oldDisappearingMessageToken: oldDisappearingMessageToken,
            newDisappearingMessageToken: newDisappearingMessageToken,
            groupUpdateSource: groupUpdateSource,
            localIdentifiers: localIdentifiers
        ).itemList

        return validateUpdateItemsNotEmpty(
            tentativeUpdateItems: precomputedItems,
            groupUpdateSource: groupUpdateSource,
            localIdentifiers: localIdentifiers
        )
    }

    private func validateUpdateItemsNotEmpty(
        tentativeUpdateItems: [TSInfoMessage.PersistableGroupUpdateItem],
        groupUpdateSource: GroupUpdateSource,
        localIdentifiers: LocalIdentifiers,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) -> [TSInfoMessage.PersistableGroupUpdateItem] {
        guard tentativeUpdateItems.isEmpty else {
            return tentativeUpdateItems
        }

        owsFailDebug("Empty group update!", file: file, function: function, line: line)

        switch groupUpdateSource {
        case .localUser:
            return [.genericUpdateByLocalUser]
        case let .aci(aci):
            return [.genericUpdateByOtherUser(updaterAci: aci.codableUuid)]
        case .rejectedInviteToPni, .legacyE164, .unknown:
            return [.genericUpdateByUnknownUser]
        }
    }
}

// MARK: -

public extension GroupUpdateSource {

    func sanitize(
        signalRecipientStore: SignalRecipientStore,
        tx: DBReadTransaction
    ) -> Self {
        switch self {
        case .legacyE164(let e164):
            // If we can map an e164 to an aci, do that. If we can't,
            // most of the time this becomes "unknown" (which only affects
            // gv1 updates)
            if
                let recipient = signalRecipientStore.recipient(for: .init(e164), tx: tx),
                let aci = recipient.aci
            {
                return .aci(aci)
            }
            return .legacyE164(e164)
        default:
            return self
        }
    }
}

// MARK: -

private enum MembershipStatus {
    case normalMember
    case invited(invitedBy: Aci?)
    case requesting
    case none

    static func local(
        localIdentifiers: LocalIdentifiers,
        groupMembership: GroupMembership
    ) -> MembershipStatus {
        let aciMembership = of(
            serviceId: localIdentifiers.aci,
            groupMembership: groupMembership
        )

        switch aciMembership {
        case .invited, .requesting, .normalMember:
            return aciMembership
        case .none:
            break
        }

        if let localPni = localIdentifiers.pni {
            return of(
                serviceId: localPni,
                groupMembership: groupMembership
            )
        }

        return .none
    }

    static func of(
        address: SignalServiceAddress,
        groupMembership: GroupMembership
    ) -> MembershipStatus {
        guard let serviceId = address.serviceId else {
            return .none
        }

        return of(
            serviceId: serviceId,
            groupMembership: groupMembership
        )
    }

    private static func of(
        serviceId: ServiceId,
        groupMembership: GroupMembership
    ) -> MembershipStatus {
        if groupMembership.isFullMember(serviceId) {
            return .normalMember
        } else if groupMembership.isInvitedMember(serviceId) {
            return .invited(invitedBy: groupMembership.addedByAci(
                forInvitedMember: serviceId
            ))
        } else if groupMembership.isRequestingMember(serviceId) {
            return .requesting
        } else {
            return .none
        }
    }
}

// MARK: -

/// Aggregates invite-related changes in which the invitee is unnamed, so we can
/// display one update rather than individual updates for each unnamed user.
private struct UnnamedInviteCounts {
    var newInviteCount: UInt = 0
    var revokedInviteCount: UInt = 0
}

// MARK: -

/// Translates "precomputed" persisted group update items to displayable update
/// items.
///
/// Historically, when a group was updated we persisted a "before" and "after"
/// group model. Then, at display-time, we would "diff" those models to find out
/// what changed.
///
/// All new group updates are now "precomputed" when we learn about an update
/// and persisted. Consequently, all new group updates should go through this
/// struct.
private struct PrecomputedGroupUpdateItemBuilder {
    private let contactsManager: Shims.ContactsManager

    init(contactsManager: Shims.ContactsManager) {
        self.contactsManager = contactsManager
    }

    func buildGroupUpdateItem(
        precomputedUpdateItem: TSInfoMessage.PersistableGroupUpdateItem,
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction
    ) -> DisplayableGroupUpdateItem {
        func expandAci(_ aci: AciUuid) -> (String, SignalServiceAddress) {
            let address = SignalServiceAddress(aci.wrappedValue)

            return (
                contactsManager.displayName(address: address, tx: tx),
                address
            )
        }

        switch precomputedUpdateItem {
        case let .sequenceOfInviteLinkRequestAndCancels(requesterAci, count, isTail):
            return sequenceOfInviteLinkRequestAndCancelsItem(
                requesterAci: requesterAci.wrappedValue,
                count: count,
                isTail: isTail,
                tx: tx
            )
        case let .invitedPniPromotedToFullMemberAci(newMember, inviter):
            if newMember.wrappedValue == localIdentifiers.aci {
                // Local user promoted.
                if let inviter {
                    let (inviterName, inviterAddress) = expandAci(inviter)
                    return .localUserAcceptedInviteFromInviter(
                        inviterName: inviterName,
                        inviterAddress: inviterAddress
                    )
                } else {
                    return .localUserAcceptedInviteFromUnknownUser
                }
            } else {
                // Another user promoted themselves.
                let (userName, userAddress) = expandAci(newMember)
                if let inviter, inviter.wrappedValue == localIdentifiers.aci {
                    return .otherUserAcceptedInviteFromLocalUser(
                        userName: userName,
                        userAddress: userAddress
                    )
                } else if let inviter {
                    let (inviterName, inviterAddress) = expandAci(inviter)
                    return .otherUserAcceptedInviteFromInviter(
                        userName: userName,
                        userAddress: userAddress,
                        inviterName: inviterName,
                        inviterAddress: inviterAddress
                    )
                } else {
                    return .otherUserAcceptedInviteFromUnknownUser(
                        userName: userName,
                        userAddress: userAddress
                    )
                }
            }
        case .genericUpdateByLocalUser:
            return .genericUpdateByLocalUser

        case .genericUpdateByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .genericUpdateByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .genericUpdateByUnknownUser:
            return .genericUpdateByUnknownUser

        case .createdByLocalUser:
            return .createdByLocalUser

        case .createdByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .createdByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .createdByUnknownUser:
            return .createdByUnknownUser

        case .inviteFriendsToNewlyCreatedGroup:
            return .inviteFriendsToNewlyCreatedGroup

        case .wasMigrated:
            return .wasMigrated

        case .nameChangedByLocalUser(let newGroupName):
            return .nameChangedByLocalUser(newGroupName: newGroupName)

        case .nameChangedByOtherUser(let updaterAci, let newGroupName):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .nameChangedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress, newGroupName: newGroupName)

        case .nameChangedByUnknownUser(let newGroupName):
            return .nameChangedByUnknownUser(newGroupName: newGroupName)

        case .nameRemovedByLocalUser:
            return .nameRemovedByLocalUser

        case .nameRemovedByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .nameRemovedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .nameRemovedByUnknownUser:
            return .nameRemovedByUnknownUser

        case .avatarChangedByLocalUser:
            return .avatarChangedByLocalUser

        case .avatarChangedByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .avatarChangedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .avatarChangedByUnknownUser:
            return .avatarChangedByUnknownUser

        case .avatarRemovedByLocalUser:
            return .avatarRemovedByLocalUser

        case .avatarRemovedByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .avatarRemovedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .avatarRemovedByUnknownUser:
            return .avatarRemovedByUnknownUser

        case .descriptionChangedByLocalUser(let newDescription):
            return .descriptionChangedByLocalUser(newDescription: newDescription)

        case let .descriptionChangedByOtherUser(updaterAci, newDescription):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .descriptionChangedByOtherUser(
                newDescription: newDescription,
                updaterName: updaterName,
                updaterAddress: updaterAddress
            )

        case .descriptionChangedByUnknownUser(let newDescription):
            return .descriptionChangedByUnknownUser(newDescription: newDescription)

        case .descriptionRemovedByLocalUser:
            return .descriptionRemovedByLocalUser

        case .descriptionRemovedByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .descriptionRemovedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .descriptionRemovedByUnknownUser:
            return .descriptionRemovedByUnknownUser

        case .membersAccessChangedByLocalUser(let newAccess):
            return .membersAccessChangedByLocalUser(newAccess: newAccess)

        case .membersAccessChangedByOtherUser(let updaterAci, let newAccess):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .membersAccessChangedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress, newAccess: newAccess)

        case .membersAccessChangedByUnknownUser(let newAccess):
            return .membersAccessChangedByUnknownUser(newAccess: newAccess)

        case .attributesAccessChangedByLocalUser(let newAccess):
            return .attributesAccessChangedByLocalUser(newAccess: newAccess)

        case .attributesAccessChangedByOtherUser(let updaterAci, let newAccess):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .attributesAccessChangedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress, newAccess: newAccess)

        case .attributesAccessChangedByUnknownUser(let newAccess):
            return .attributesAccessChangedByUnknownUser(newAccess: newAccess)

        case .announcementOnlyEnabledByLocalUser:
            return .announcementOnlyEnabledByLocalUser

        case .announcementOnlyEnabledByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .announcementOnlyEnabledByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .announcementOnlyEnabledByUnknownUser:
            return .announcementOnlyEnabledByUnknownUser

        case .announcementOnlyDisabledByLocalUser:
            return .announcementOnlyDisabledByLocalUser

        case .announcementOnlyDisabledByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .announcementOnlyDisabledByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .announcementOnlyDisabledByUnknownUser:
            return .announcementOnlyDisabledByUnknownUser

        case .localUserWasGrantedAdministratorByLocalUser:
            return .localUserWasGrantedAdministratorByLocalUser

        case .localUserWasGrantedAdministratorByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .localUserWasGrantedAdministratorByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .localUserWasGrantedAdministratorByUnknownUser:
            return .localUserWasGrantedAdministratorByUnknownUser

        case .otherUserWasGrantedAdministratorByLocalUser(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserWasGrantedAdministratorByLocalUser(userName: userName, userAddress: userAddress)

        case .otherUserWasGrantedAdministratorByOtherUser(let updaterAci, let userAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserWasGrantedAdministratorByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress, userName: userName, userAddress: userAddress)

        case .otherUserWasGrantedAdministratorByUnknownUser(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserWasGrantedAdministratorByUnknownUser(userName: userName, userAddress: userAddress)

        case .localUserWasRevokedAdministratorByLocalUser:
            return .localUserWasRevokedAdministratorByLocalUser

        case .localUserWasRevokedAdministratorByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .localUserWasRevokedAdministratorByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .localUserWasRevokedAdministratorByUnknownUser:
            return .localUserWasRevokedAdministratorByUnknownUser

        case .otherUserWasRevokedAdministratorByLocalUser(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserWasRevokedAdministratorByLocalUser(userName: userName, userAddress: userAddress)

        case .otherUserWasRevokedAdministratorByOtherUser(let updaterAci, let userAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserWasRevokedAdministratorByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress, userName: userName, userAddress: userAddress)

        case .otherUserWasRevokedAdministratorByUnknownUser(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserWasRevokedAdministratorByUnknownUser(userName: userName, userAddress: userAddress)

        case .localUserLeft:
            return .localUserLeft

        case .localUserRemoved(let removerAci):
            let (removerName, removerAddress) = expandAci(removerAci)
            return .localUserRemoved(removerName: removerName, removerAddress: removerAddress)

        case .localUserRemovedByUnknownUser:
            return .localUserRemovedByUnknownUser

        case .otherUserLeft(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserLeft(userName: userName, userAddress: userAddress)

        case .otherUserRemovedByLocalUser(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserRemovedByLocalUser(userName: userName, userAddress: userAddress)

        case .otherUserRemoved(let removerAci, let userAci):
            let (removerName, removerAddress) = expandAci(removerAci)
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserRemoved(removerName: removerName, removerAddress: removerAddress, userName: userName, userAddress: userAddress)

        case .otherUserRemovedByUnknownUser(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserRemovedByUnknownUser(
                userName: userName,
                userAddress: userAddress
            )

        case .localUserWasInvitedByLocalUser:
            return .localUserWasInvitedByLocalUser

        case .localUserWasInvitedByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .localUserWasInvitedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .localUserWasInvitedByUnknownUser:
            return .localUserWasInvitedByUnknownUser

        case .otherUserWasInvitedByLocalUser(let invitee):
            let inviteeAddress = SignalServiceAddress(invitee.wrappedValue)
            let inviteeName = contactsManager.displayName(
                address: inviteeAddress,
                tx: tx
            )
            return .otherUserWasInvitedByLocalUser(
                userName: inviteeName,
                userAddress: inviteeAddress
            )

        case .unnamedUsersWereInvitedByLocalUser(let count):
            return .unnamedUsersWereInvitedByLocalUser(count: count)

        case .unnamedUsersWereInvitedByOtherUser(let updaterAci, let count):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .unnamedUsersWereInvitedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress, count: count)

        case .unnamedUsersWereInvitedByUnknownUser(let count):
            return .unnamedUsersWereInvitedByUnknownUser(count: count)

        case .localUserAcceptedInviteFromInviter(let inviterAci):
            let (inviterName, inviterAddress) = expandAci(inviterAci)
            return .localUserAcceptedInviteFromInviter(inviterName: inviterName, inviterAddress: inviterAddress)

        case .localUserAcceptedInviteFromUnknownUser:
            return .localUserAcceptedInviteFromUnknownUser

        case .otherUserAcceptedInviteFromLocalUser(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserAcceptedInviteFromLocalUser(userName: userName, userAddress: userAddress)

        case .otherUserAcceptedInviteFromInviter(let userAci, let inviterAci):
            let (userName, userAddress) = expandAci(userAci)
            let (inviterName, inviterAddress) = expandAci(inviterAci)
            return .otherUserAcceptedInviteFromInviter(userName: userName, userAddress: userAddress, inviterName: inviterName, inviterAddress: inviterAddress)

        case .otherUserAcceptedInviteFromUnknownUser(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserAcceptedInviteFromUnknownUser(userName: userName, userAddress: userAddress)

        case .localUserJoined:
            return .localUserJoined

        case .otherUserJoined(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserJoined(userName: userName, userAddress: userAddress)

        case .localUserAddedByLocalUser:
            return .localUserAddedByLocalUser

        case .localUserAddedByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .localUserAddedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .localUserAddedByUnknownUser:
            return .localUserAddedByUnknownUser

        case .otherUserAddedByLocalUser(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserAddedByLocalUser(userName: userName, userAddress: userAddress)

        case .otherUserAddedByOtherUser(let updaterAci, let userAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserAddedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress, userName: userName, userAddress: userAddress)

        case .otherUserAddedByUnknownUser(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserAddedByUnknownUser(userName: userName, userAddress: userAddress)

        case .localUserDeclinedInviteFromInviter(let inviterAci):
            return .localUserDeclinedInviteFromInviter(
                inviterName: contactsManager.displayName(
                    address: .init(inviterAci.wrappedValue),
                    tx: tx
                ),
                inviterAddress: .init(inviterAci.wrappedValue)
            )
        case .localUserDeclinedInviteFromUnknownUser:
            return .localUserDeclinedInviteFromUnknownUser
        case .otherUserDeclinedInviteFromLocalUser(let invitee):
            return .otherUserDeclinedInviteFromLocalUser(
                userName: contactsManager.displayName(
                    address: .init(invitee.wrappedValue),
                    tx: tx
                ),
                userAddress: .init(invitee.wrappedValue)
            )
        case let .otherUserDeclinedInviteFromInviter(_, inviterAci),
            let .unnamedUserDeclinedInviteFromInviter(inviterAci):
            return .otherUserDeclinedInviteFromInviter(
                inviterName: contactsManager.displayName(
                    address: .init(inviterAci.wrappedValue),
                    tx: tx
                ),
                inviterAddress: .init(inviterAci.wrappedValue)
            )
        case .otherUserDeclinedInviteFromUnknownUser,
            .unnamedUserDeclinedInviteFromUnknownUser:
            return .otherUserDeclinedInviteFromUnknownUser
        case .localUserInviteRevoked(let revokerAci):
            return .localUserInviteRevoked(
                revokerName: contactsManager.displayName(
                    address: .init(revokerAci.wrappedValue),
                    tx: tx
                ),
                revokerAddress: .init(revokerAci.wrappedValue)
            )
        case .localUserInviteRevokedByUnknownUser:
            return .localUserInviteRevokedByUnknownUser
        case .otherUserInviteRevokedByLocalUser(let invitee):
            return .otherUserInviteRevokedByLocalUser(
                userName: contactsManager.displayName(
                    address: .init(invitee.wrappedValue),
                    tx: tx
                ),
                userAddress: .init(invitee.wrappedValue)
            )
        case .unnamedUserInvitesWereRevokedByLocalUser(let count):
            return .unnamedUserInvitesWereRevokedByLocalUser(count: count)
        case let .unnamedUserInvitesWereRevokedByOtherUser(updaterAci, count):
            return .unnamedUserInvitesWereRevokedByOtherUser(
                updaterName: contactsManager.displayName(
                    address: .init(updaterAci.wrappedValue),
                    tx: tx
                ),
                updaterAddress: .init(updaterAci.wrappedValue),
                count: count
            )
        case .unnamedUserInvitesWereRevokedByUnknownUser(let count):
            return .unnamedUserInvitesWereRevokedByUnknownUser(count: count)

        case .localUserRequestedToJoin:
            return .localUserRequestedToJoin

        case .otherUserRequestedToJoin(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserRequestedToJoin(userName: userName, userAddress: userAddress)

        case .localUserRequestApproved(let approverAci):
            let (approverName, approverAddress) = expandAci(approverAci)
            return .localUserRequestApproved(approverName: approverName, approverAddress: approverAddress)

        case .localUserRequestApprovedByUnknownUser:
            return .localUserRequestApprovedByUnknownUser

        case .otherUserRequestApprovedByLocalUser(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserRequestApprovedByLocalUser(userName: userName, userAddress: userAddress)

        case .otherUserRequestApproved(let userAci, let approverAci):
            let (userName, userAddress) = expandAci(userAci)
            let (approverName, approverAddress) = expandAci(approverAci)
            return .otherUserRequestApproved(userName: userName, userAddress: userAddress, approverName: approverName, approverAddress: approverAddress)

        case .otherUserRequestApprovedByUnknownUser(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserRequestApprovedByUnknownUser(
                userName: userName,
                userAddress: userAddress
            )

        case .localUserRequestCanceledByLocalUser:
            return .localUserRequestCanceledByLocalUser

        case .localUserRequestRejectedByUnknownUser:
            return .localUserRequestRejectedByUnknownUser

        case .otherUserRequestRejectedByLocalUser(let requesterAci):
            let (requesterName, requesterAddress) = expandAci(requesterAci)
            return .otherUserRequestRejectedByLocalUser(requesterName: requesterName, requesterAddress: requesterAddress)

        case .otherUserRequestRejectedByOtherUser(let updaterAci, let requesterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            let (requesterName, requesterAddress) = expandAci(requesterAci)
            return .otherUserRequestRejectedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress, requesterName: requesterName, requesterAddress: requesterAddress)

        case .otherUserRequestCanceledByOtherUser(let requesterAci):
            let (requesterName, requesterAddress) = expandAci(requesterAci)
            return .otherUserRequestCanceledByOtherUser(requesterName: requesterName, requesterAddress: requesterAddress)

        case .otherUserRequestRejectedByUnknownUser(let requesterAci):
            let (requesterName, requesterAddress) = expandAci(requesterAci)
            return .otherUserRequestRejectedByUnknownUser(requesterName: requesterName, requesterAddress: requesterAddress)

        case .disappearingMessagesEnabledByLocalUser(let durationMs):
            return .disappearingMessagesEnabledByLocalUser(durationMs: durationMs)

        case .disappearingMessagesEnabledByOtherUser(let updaterAci, let durationMs):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .disappearingMessagesEnabledByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress, durationMs: durationMs)

        case .disappearingMessagesEnabledByUnknownUser(let durationMs):
            return .disappearingMessagesEnabledByUnknownUser(durationMs: durationMs)

        case .disappearingMessagesDisabledByLocalUser:
            return .disappearingMessagesDisabledByLocalUser

        case .disappearingMessagesDisabledByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .disappearingMessagesDisabledByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .disappearingMessagesDisabledByUnknownUser:
            return .disappearingMessagesDisabledByUnknownUser

        case .inviteLinkResetByLocalUser:
            return .inviteLinkResetByLocalUser

        case .inviteLinkResetByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .inviteLinkResetByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .inviteLinkResetByUnknownUser:
            return .inviteLinkResetByUnknownUser

        case .inviteLinkEnabledWithoutApprovalByLocalUser:
            return .inviteLinkEnabledWithoutApprovalByLocalUser

        case .inviteLinkEnabledWithoutApprovalByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .inviteLinkEnabledWithoutApprovalByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .inviteLinkEnabledWithoutApprovalByUnknownUser:
            return .inviteLinkEnabledWithoutApprovalByUnknownUser

        case .inviteLinkEnabledWithApprovalByLocalUser:
            return .inviteLinkEnabledWithApprovalByLocalUser

        case .inviteLinkEnabledWithApprovalByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .inviteLinkEnabledWithApprovalByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .inviteLinkEnabledWithApprovalByUnknownUser:
            return .inviteLinkEnabledWithApprovalByUnknownUser

        case .inviteLinkDisabledByLocalUser:
            return .inviteLinkDisabledByLocalUser

        case .inviteLinkDisabledByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .inviteLinkDisabledByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .inviteLinkDisabledByUnknownUser:
            return .inviteLinkDisabledByUnknownUser

        case .inviteLinkApprovalDisabledByLocalUser:
            return .inviteLinkApprovalDisabledByLocalUser

        case .inviteLinkApprovalDisabledByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .inviteLinkApprovalDisabledByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .inviteLinkApprovalDisabledByUnknownUser:
            return .inviteLinkApprovalDisabledByUnknownUser

        case .inviteLinkApprovalEnabledByLocalUser:
            return .inviteLinkApprovalEnabledByLocalUser

        case .inviteLinkApprovalEnabledByOtherUser(let updaterAci):
            let (updaterName, updaterAddress) = expandAci(updaterAci)
            return .inviteLinkApprovalEnabledByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress)

        case .inviteLinkApprovalEnabledByUnknownUser:
            return .inviteLinkApprovalEnabledByUnknownUser

        case .localUserJoinedViaInviteLink:
            return .localUserJoinedViaInviteLink

        case .otherUserJoinedViaInviteLink(let userAci):
            let (userName, userAddress) = expandAci(userAci)
            return .otherUserJoinedViaInviteLink(userName: userName, userAddress: userAddress)
        }
    }

    private func sequenceOfInviteLinkRequestAndCancelsItem(
        requesterAci: Aci,
        count: UInt,
        isTail: Bool,
        tx: DBReadTransaction
    ) -> DisplayableGroupUpdateItem {
        let updaterAddress = SignalServiceAddress(requesterAci)
        let updaterName = contactsManager.displayName(address: updaterAddress, tx: tx)

        guard count > 0 else {
            // We haven't actually collapsed anything, so we should fall back to
            // the regular ol' "user requested to join".
            return .otherUserRequestedToJoin(
                userName: updaterName,
                userAddress: updaterAddress
            )
        }

        return .sequenceOfInviteLinkRequestAndCancels(
            userName: updaterName,
            userAddress: updaterAddress,
            count: count,
            isTail: isTail
        )
    }
}

// MARK: -

/// Generates displayable update items about the fact that a group was created.
///
/// Historically, when a group was updated we persisted a "before" and "after"
/// group model. Then, at display-time, we would "diff" those models to find out
/// what changed. When a group was first created it only had an "after" model,
/// which is where this struct comes into play.
///
/// All new group updates are now "precomputed" when we learn about an update
/// and persisted – including for new group creation. Consequently, this struct
/// should only deal with legacy updates, and all new updates should go through
/// ``PrecomputedGroupUpdateItemBuilder``.
private struct NewGroupUpdateItemBuilder {

    public typealias PersistableGroupUpdateItem = TSInfoMessage.PersistableGroupUpdateItem

    private let contactsManager: Shims.ContactsManager

    init(contactsManager: Shims.ContactsManager) {
        self.contactsManager = contactsManager
    }

    func buildGroupUpdateItems(
        newGroupModel: TSGroupModel,
        newDisappearingMessageToken: DisappearingMessageToken?,
        groupUpdateSource: GroupUpdateSource,
        localIdentifiers: LocalIdentifiers
    ) -> [PersistableGroupUpdateItem] {
        var items = [PersistableGroupUpdateItem]()

        // We're just learning of the group.
        let groupWasInsertedItem = groupWasInsertedItem(
            groupUpdateSource: groupUpdateSource,
            localIdentifiers: localIdentifiers,
            newGroupModel: newGroupModel,
            newGroupMembership: newGroupModel.groupMembership
        )

        groupWasInsertedItem.map { items.append($0) }

        // Skip update items for things like name, avatar, current members. Do
        // add update items for the current disappearing messages state. We can
        // use unknown attribution here – either we created the group (so it was
        // us who set the time) or someone else did (so we don't know who set
        // the timer), and unknown attribution is always safe.
        DiffingGroupUpdateItemBuilder.disappearingMessageUpdateItem(
            groupUpdateSource: groupUpdateSource,
            oldToken: nil,
            newToken: newDisappearingMessageToken,
            forceUnknownAttribution: true
        ).map { items.append($0) }

        if
            let groupWasInsertedItem,
            case .createdByLocalUser = groupWasInsertedItem
        {
            // If we just created the group, add an update item to let users
            // know about the group link.
            items.append(.inviteFriendsToNewlyCreatedGroup)
        }

        return items
    }

    private func groupWasInsertedItem(
        groupUpdateSource: GroupUpdateSource,
        localIdentifiers: LocalIdentifiers,
        newGroupModel: TSGroupModel,
        newGroupMembership: GroupMembership
    ) -> PersistableGroupUpdateItem? {
        guard let newGroupModel = newGroupModel as? TSGroupModelV2 else {
            // This is a V1 group. While we may be able to be more specific, we
            // shouldn't stress over V1 group update messages.
            return .createdByUnknownUser
        }

        let wasGroupJustCreated = newGroupModel.revision == 0
        if wasGroupJustCreated {
            switch groupUpdateSource {
            case .localUser:
                return .createdByLocalUser
            case let .aci(updaterAci):
                return .createdByOtherUser(updaterAci: updaterAci.codableUuid)
            case .rejectedInviteToPni, .legacyE164, .unknown:
                return .createdByUnknownUser
            }
        }

        switch MembershipStatus.local(
            localIdentifiers: localIdentifiers,
            groupMembership: newGroupMembership
        ) {
        case .normalMember:
            // We checked above if the group was just created, in which case
            // it'd be implicit that we were added.

            switch groupUpdateSource {
            case let .aci(updaterAci):
                return .localUserAddedByOtherUser(
                    updaterAci: updaterAci.codableUuid
                )
            default:
                if newGroupModel.didJustAddSelfViaGroupLink {
                    return .localUserJoined
                } else {
                    return .localUserAddedByUnknownUser
                }
            }
        case .invited(invitedBy: let inviterAci):
            if let inviterAci {
                return .localUserWasInvitedByOtherUser(
                    updaterAci: inviterAci.codableUuid
                )
            } else {
                return .localUserWasInvitedByUnknownUser
            }
        case .requesting:
            return .localUserRequestedToJoin
        case .none:
            owsFailDebug("Group was inserted without local membership!")
            return nil
        }
    }
}

// MARK: -

/// Generates displayable update items about the fact that a group was created.
///
/// Historically, when a group was updated we persisted a "before" and "after"
/// group model. Then, at display-time, we would "diff" those models to find out
/// what changed. This struct handles that "diffing".
///
/// All new group updates are now "precomputed" when we learn about an update
/// and persisted, and do not need display-time diffing. Consequently, this
/// struct deal with displaying legacy updates, and displaying any new updates
/// should go through ``PrecomputedGroupUpdateItemBuilder``.
///
/// - Note
/// At the time of writing, this struct's "diffing" approach is used during the
/// "precomputation" step referenced above, to maximize compatibility with
/// existing code.
///
/// - Note
/// Historically, group update items were computed using a struct that populated
/// itself with update items during initialization. Rather than refactor many,
/// many call sites to pass through the historically stored-as-properties values
/// used by that computation, we preserve that pattern here.
private struct DiffingGroupUpdateItemBuilder {
    typealias PersistableGroupUpdateItem = TSInfoMessage.PersistableGroupUpdateItem

    private let localIdentifiers: LocalIdentifiersWrapper
    private let groupUpdateSource: GroupUpdateSource
    private let isReplacingJoinRequestPlaceholder: Bool

    /// The update items, in order.
    private(set) var itemList = [PersistableGroupUpdateItem]()

    /// Create a ``GroupUpdateCopy``.
    ///
    /// - Parameter groupUpdateSource
    /// The address to whom this update should be attributed, if known.
    init(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken?,
        groupUpdateSource: GroupUpdateSource,
        localIdentifiers: LocalIdentifiers
    ) {
        self.localIdentifiers = .init(localIdentifiers: localIdentifiers)
        self.groupUpdateSource = groupUpdateSource

        if let oldGroupModelV2 = oldGroupModel as? TSGroupModelV2 {
            self.isReplacingJoinRequestPlaceholder = oldGroupModelV2.isPlaceholderModel
        } else {
            self.isReplacingJoinRequestPlaceholder = false
        }

        populate(
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            oldDisappearingMessageToken: oldDisappearingMessageToken,
            newDisappearingMessageToken: newDisappearingMessageToken,
            groupUpdateSource: groupUpdateSource
        )

        switch groupUpdateSource {
        case .unknown:
            Logger.warn("Missing updater info!")
        default:
            break
        }
    }

    fileprivate struct LocalIdentifiersWrapper {
        // Guard the actual identifiers; we don't want arbitrary unsafe
        // pni comparisons
        private let localIdentifiers: LocalIdentifiers

        init(localIdentifiers: LocalIdentifiers) {
            self.localIdentifiers = localIdentifiers
        }

        // Comparing the aci is always safe since it doesn't change.
        // Expose it freely.
        var aci: Aci { localIdentifiers.aci }

        /// Move the given service ID to the front of ``allUsersSorted``, if it
        /// is present therein.
        func moveLocalAddressToFrontOfGroupMembers(
            _ addresses: inout [SignalServiceAddress]
        ) {
            var foundAciAddress = false
            var foundPniAddress = false
            addresses.removeAll(where: {
                switch $0.serviceId?.concreteType {
                case .aci(let aci) where aci == localIdentifiers.aci:
                    foundAciAddress = true
                    return true
                case .pni(let pni) where pni == localIdentifiers.pni:
                    foundPniAddress = true
                    return true
                default:
                    return false
                }
            })
            if foundPniAddress, let pni = localIdentifiers.pni {
                addresses.insert(.init(pni), at: 0)
            }
            if foundAciAddress {
                addresses.insert(localIdentifiers.aciAddress, at: 0)
            }
        }

        func localGroupMembersOnly(_ addresses: Set<SignalServiceAddress>) -> [SignalServiceAddress] {
            return addresses.filter(localIdentifiers.contains(address:))
        }

        /// Note that this is error prone when comparing a pni since those can change.
        ///
        /// This method is used in two cases:
        /// 1. Diffing models for a new group udpate we just learned about, and are about
        ///   to persist as PersistableGroupUpdateItem on a TSInfoMessage.
        /// 2. Diffing two models we persisted in a legacy TSInfoMessage
        ///
        /// In the first case, this is "safe". Maybe our pni changed since this update was created,
        /// but this is the first time we are learning about it, so now is when we determine if the
        /// invitee was us or not.
        ///
        /// In the seceond case, this is super error prone. But historically we did NOT store whether
        /// the invitee Pni was ours (we did store whether the updater was us, but not the invitee).
        /// Not having stored it then means the best we can do is compare it now.
        func isInviteeLocalUser(_ invitee: ServiceId) -> Bool {
            return localIdentifiers.contains(serviceId: invitee)
        }
    }

    private mutating func addItem(_ item: PersistableGroupUpdateItem) {
        itemList.append(item)
    }

    // MARK: Population

    /// Populate this builder's list of update items, by diffing the provided
    /// values.
    mutating func populate(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken?,
        groupUpdateSource: GroupUpdateSource
    ) {
        if isReplacingJoinRequestPlaceholder {
            addMembershipUpdates(
                oldGroupMembership: oldGroupModel.groupMembership,
                newGroupMembership: newGroupModel.groupMembership,
                newGroupModel: newGroupModel,
                groupUpdateSource: groupUpdateSource,
                forLocalUserOnly: true
            )

            addDisappearingMessageUpdates(
                oldToken: oldDisappearingMessageToken,
                newToken: newDisappearingMessageToken
            )
        } else if wasJustMigrated(newGroupModel: newGroupModel) {
            addMigrationUpdates(
                oldGroupMembership: oldGroupModel.groupMembership,
                newGroupMembership: newGroupModel.groupMembership,
                newGroupModel: newGroupModel
            )
        } else {
            addMembershipUpdates(
                oldGroupMembership: oldGroupModel.groupMembership,
                newGroupMembership: newGroupModel.groupMembership,
                newGroupModel: newGroupModel,
                groupUpdateSource: groupUpdateSource,
                forLocalUserOnly: false
            )

            addAttributesUpdates(
                oldGroupModel: oldGroupModel,
                newGroupModel: newGroupModel
            )

            addAccessUpdates(
                oldGroupModel: oldGroupModel,
                newGroupModel: newGroupModel
            )

            addDisappearingMessageUpdates(
                oldToken: oldDisappearingMessageToken,
                newToken: newDisappearingMessageToken
            )

            addGroupInviteLinkUpdates(
                oldGroupModel: oldGroupModel,
                newGroupModel: newGroupModel
            )

            addIsAnnouncementOnlyLinkUpdates(
                oldGroupModel: oldGroupModel,
                newGroupModel: newGroupModel
            )
        }
    }

    // MARK: Attributes

    mutating func addAttributesUpdates(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel
    ) {
        let groupName = { (groupModel: TSGroupModel) -> String? in
            groupModel.groupName?.stripped.nilIfEmpty
        }

        let oldGroupName = groupName(oldGroupModel)
        let newGroupName = groupName(newGroupModel)

        if oldGroupName != newGroupName {
            if let name = newGroupName {
                switch groupUpdateSource {
                case .localUser:
                    addItem(.nameChangedByLocalUser(newGroupName: name))
                case let .aci(updaterAci):
                    addItem(.nameChangedByOtherUser(
                        updaterAci: updaterAci.codableUuid,
                        newGroupName: name
                    ))
                case .rejectedInviteToPni, .legacyE164, .unknown:
                    addItem(.nameChangedByUnknownUser(newGroupName: name))
                }
            } else {
                switch groupUpdateSource {
                case .localUser:
                    addItem(.nameRemovedByLocalUser)
                case let .aci(updaterAci):
                    addItem(.nameRemovedByOtherUser(updaterAci: updaterAci.codableUuid))
                case .rejectedInviteToPni, .legacyE164, .unknown:
                    addItem(.nameRemovedByUnknownUser)
                }
            }
        }

        if oldGroupModel.avatarHash != newGroupModel.avatarHash {
            if !newGroupModel.avatarHash.isEmptyOrNil {
                switch groupUpdateSource {
                case .localUser:
                    addItem(.avatarChangedByLocalUser)
                case let .aci(updaterAci):
                    addItem(.avatarChangedByOtherUser(
                        updaterAci: updaterAci.codableUuid
                    ))
                case .rejectedInviteToPni, .legacyE164, .unknown:
                    addItem(.avatarChangedByUnknownUser)
                }
            } else {
                switch groupUpdateSource {
                case .localUser:
                    addItem(.avatarRemovedByLocalUser)
                case let .aci(updaterAci):
                    addItem(.avatarRemovedByOtherUser(
                        updaterAci: updaterAci.codableUuid
                    ))
                case .rejectedInviteToPni, .legacyE164, .unknown:
                    addItem(.avatarRemovedByUnknownUser)
                }
            }
        }

        guard let oldGroupModel = oldGroupModel as? TSGroupModelV2,
              let newGroupModel = newGroupModel as? TSGroupModelV2 else { return }

        let groupDescription = { (groupModel: TSGroupModelV2) -> String? in
            return groupModel.descriptionText?.stripped.nilIfEmpty
        }
        let oldGroupDescription = groupDescription(oldGroupModel)
        let newGroupDescription = groupDescription(newGroupModel)
        if oldGroupDescription != newGroupDescription {
            if let newGroupDescription {
                switch groupUpdateSource {
                case .localUser:
                    addItem(.descriptionChangedByLocalUser(newDescription: newGroupDescription))
                case let .aci(updaterAci):
                    addItem(.descriptionChangedByOtherUser(
                        updaterAci: updaterAci.codableUuid,
                        newDescription: newGroupDescription
                    ))
                case .rejectedInviteToPni, .legacyE164, .unknown:
                    addItem(.descriptionChangedByUnknownUser(newDescription: newGroupDescription))
                }
            } else {
                switch groupUpdateSource {
                case .localUser:
                    addItem(.descriptionRemovedByLocalUser)
                case let .aci(updaterAci):
                    addItem(.descriptionRemovedByOtherUser(
                        updaterAci: updaterAci.codableUuid
                    ))
                case .rejectedInviteToPni, .legacyE164, .unknown:
                    addItem(.descriptionRemovedByUnknownUser)
                }
            }
        }
    }

    // MARK: Access

    mutating func addAccessUpdates(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel
    ) {
        guard let oldGroupModel = oldGroupModel as? TSGroupModelV2 else {
            return
        }
        guard let newGroupModel = newGroupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid group model.")
            return
        }

        let oldAccess = oldGroupModel.access
        let newAccess = newGroupModel.access

        if oldAccess.members != newAccess.members {
            switch groupUpdateSource {
            case .localUser:
                addItem(.membersAccessChangedByLocalUser(newAccess: newAccess.members))
            case let .aci(updaterAci):
                addItem(.membersAccessChangedByOtherUser(
                    updaterAci: updaterAci.codableUuid,
                    newAccess: newAccess.members
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.membersAccessChangedByUnknownUser(newAccess: newAccess.members))
            }
        }

        if oldAccess.attributes != newAccess.attributes {
            switch groupUpdateSource {
            case .localUser:
                addItem(.attributesAccessChangedByLocalUser(newAccess: newAccess.attributes))
            case let .aci(updaterAci):
                addItem(.attributesAccessChangedByOtherUser(
                    updaterAci: updaterAci.codableUuid,
                    newAccess: newAccess.attributes
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.attributesAccessChangedByUnknownUser(newAccess: newAccess.attributes))
            }
        }
    }

    // MARK: Membership

    mutating func addMembershipUpdates(
        oldGroupMembership: GroupMembership,
        newGroupMembership: GroupMembership,
        newGroupModel: TSGroupModel,
        groupUpdateSource: GroupUpdateSource,
        forLocalUserOnly: Bool
    ) {
        var unnamedInviteCounts = UnnamedInviteCounts()

        let allUsersUnsorted = oldGroupMembership.allMembersOfAnyKind.union(newGroupMembership.allMembersOfAnyKind)
        let allUsersSorted: [SignalServiceAddress] = {
            guard !forLocalUserOnly else {
                return localIdentifiers.localGroupMembersOnly(allUsersUnsorted)
            }
            var allUsersSorted = Array(allUsersUnsorted).stableSort()

            // If the local user has a membership update, sort it to the front.
            localIdentifiers.moveLocalAddressToFrontOfGroupMembers(&allUsersSorted)

            // If the updater has changed their membership status, ensure it appears _last_.
            // This trumps the re-ordering of the local user above.
            let updaterAddress: SignalServiceAddress?
            switch groupUpdateSource {
            case .unknown:
                updaterAddress = nil
            case .legacyE164(let e164):
                updaterAddress = .init(e164)
            case .aci(let aci):
                updaterAddress = .init(aci)
            case .rejectedInviteToPni(let pni):
                updaterAddress = .init(pni)
            case .localUser(let originalSource):
                switch originalSource {
                case .unknown, .localUser:
                    updaterAddress = nil
                case .legacyE164(let e164):
                    updaterAddress = .init(e164)
                case .aci(let aci):
                    updaterAddress = .init(aci)
                case .rejectedInviteToPni(let pni):
                    updaterAddress = .init(pni)
                }
            }
            if let updaterAddress {
                allUsersSorted = allUsersSorted.filter { $0 != updaterAddress } + [updaterAddress]
            }
            return allUsersSorted
        }()

        for address in allUsersSorted {

            let oldMembershipStatus: MembershipStatus = .of(address: address, groupMembership: oldGroupMembership)
            let newMembershipStatus: MembershipStatus = .of(address: address, groupMembership: newGroupMembership)

            switch oldMembershipStatus {
            case .normalMember:
                switch newMembershipStatus {
                case .normalMember:
                    // Membership status didn't change.
                    // Check for role changes.
                    if let userAci = address.aci {
                        addMemberRoleUpdates(
                            userAci: userAci,
                            oldGroupMembership: oldGroupMembership,
                            newGroupMembership: newGroupMembership,
                            newGroupModel: newGroupModel
                        )
                    }
                case .invited:
                    if let userAci = address.aci {
                        addUserLeftOrWasKickedOutOfGroupThenWasInvitedToTheGroup(
                            userAci: userAci
                        )
                    }
                case .requesting:
                    // This could happen if a user leaves a group, the requests to rejoin
                    // and we do not have access to the intervening revisions.
                    if let userAci = address.aci {
                        addUserRequestedToJoinGroup(requesterAci: userAci)
                    }
                case .none:
                    if let userAci = address.aci {
                        addUserLeftOrWasKickedOutOfGroup(userAci: userAci)
                    }
                }
            case .invited:
                switch newMembershipStatus {
                case .normalMember:
                    if let inviteeAci = address.aci {
                        addUserInvitedByAciAcceptedOrWasAdded(
                            inviteeAci: inviteeAci,
                            oldGroupMembership: oldGroupMembership
                        )
                    }
                case .invited:
                    // Membership status didn't change.
                    break
                case .requesting:
                    if let requesterAci = address.aci {
                        addUserRequestedToJoinGroup(requesterAci: requesterAci)
                    }
                case .none:
                    if let inviteeServiceId = address.serviceId {
                        addUserInviteWasDeclinedOrRevoked(
                            inviteeServiceId: inviteeServiceId,
                            oldGroupMembership: oldGroupMembership,
                            unnamedInviteCounts: &unnamedInviteCounts
                        )
                    }
                }
            case .requesting:
                switch newMembershipStatus {
                case .normalMember:
                    if newGroupMembership.didJoinFromAcceptedJoinRequest(forFullMember: address) {
                        if let requesterAci = address.aci {
                            addUserRequestWasApproved(
                                requesterAci: requesterAci
                            )
                        }
                    } else {
                        if let newMemberAci = address.aci {
                            addUserWasAddedToTheGroup(
                                newMember: newMemberAci,
                                newGroupModel: newGroupModel
                            )
                        }
                    }
                case .invited:
                    if let invitee = address.serviceId {
                        addUserWasInvitedToTheGroup(
                            invitee: invitee,
                            unnamedInviteCounts: &unnamedInviteCounts
                        )
                    }
                case .requesting:
                    // Membership status didn't change.
                    break
                case .none:
                    if let requesterAci = address.aci {
                        addUserRequestWasRejected(requesterAci: requesterAci)
                    }
                }
            case .none:
                switch newMembershipStatus {
                case .normalMember:
                    if
                        newGroupMembership.didJoinFromInviteLink(forFullMember: address),
                        let newMemberAci = address.aci
                    {
                        addUserJoinedFromInviteLink(newMember: newMemberAci)
                    } else if
                        newGroupMembership.didJoinFromAcceptedJoinRequest(forFullMember: address),
                        let requesterAci = address.aci
                    {
                        addUserRequestWasApproved(
                            requesterAci: requesterAci
                        )
                    } else if let newMemberAci = address.aci {
                        addUserWasAddedToTheGroup(
                            newMember: newMemberAci,
                            newGroupModel: newGroupModel
                        )
                    }
                case .invited:
                    if let invitee = address.serviceId {
                        addUserWasInvitedToTheGroup(
                            invitee: invitee,
                            unnamedInviteCounts: &unnamedInviteCounts
                        )
                    }
                case .requesting:
                    if let requesterAci = address.aci {
                        addUserRequestedToJoinGroup(requesterAci: requesterAci)
                    }
                case .none:
                    // Membership status didn't change.
                    break
                }
            }
        }

        addUnnamedUsersWereInvited(count: unnamedInviteCounts.newInviteCount)
        addUnnamedUserInvitesWereRevoked(count: unnamedInviteCounts.revokedInviteCount)

        addInvalidInviteUpdates(
            oldGroupMembership: oldGroupMembership,
            newGroupMembership: newGroupMembership
        )
    }

    /// "Invalid invites" become unnamed invites; we don't distinguish the two beyond this point.
    mutating func addInvalidInviteUpdates(
        oldGroupMembership: GroupMembership,
        newGroupMembership: GroupMembership
    ) {
        let oldInvalidInviteUserIds = Set(oldGroupMembership.invalidInviteUserIds)
        let newInvalidInviteUserIds = Set(newGroupMembership.invalidInviteUserIds)
        let addedInvalidInviteCount = newInvalidInviteUserIds.subtracting(oldInvalidInviteUserIds).count
        let removedInvalidInviteCount = oldInvalidInviteUserIds.subtracting(newInvalidInviteUserIds).count

        if addedInvalidInviteCount > 0 {
            switch groupUpdateSource {
            case .localUser:
                addItem(.unnamedUsersWereInvitedByLocalUser(count: UInt(addedInvalidInviteCount)))
            case let .aci(updaterAci):
                addItem(.unnamedUsersWereInvitedByOtherUser(
                    updaterAci: updaterAci.codableUuid,
                    count: UInt(addedInvalidInviteCount)
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.unnamedUsersWereInvitedByUnknownUser(count: UInt(addedInvalidInviteCount)))
            }
        }

        if removedInvalidInviteCount > 0 {
            switch groupUpdateSource {
            case .localUser:
                addItem(.unnamedUserInvitesWereRevokedByLocalUser(count: UInt(removedInvalidInviteCount)))
            case let .aci(updaterAci):
                addItem(.unnamedUserInvitesWereRevokedByOtherUser(
                    updaterAci: updaterAci.codableUuid,
                    count: UInt(removedInvalidInviteCount)
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.unnamedUserInvitesWereRevokedByUnknownUser(count: UInt(removedInvalidInviteCount)))
            }
        }
    }

    mutating func addMemberRoleUpdates(
        userAci: Aci,
        oldGroupMembership: GroupMembership,
        newGroupMembership: GroupMembership,
        newGroupModel: TSGroupModel
    ) {

        let oldIsAdministrator = oldGroupMembership.isFullMemberAndAdministrator(userAci)
        let newIsAdministrator = newGroupMembership.isFullMemberAndAdministrator(userAci)

        guard oldIsAdministrator != newIsAdministrator else {
            // Role didn't change.
            return
        }

        if newIsAdministrator {
            addUserWasGrantedAdministrator(
                userAci: userAci,
                newGroupModel: newGroupModel
            )
        } else {
            addUserWasRevokedAdministrator(userAci: userAci)
        }
    }

    mutating func addUserWasGrantedAdministrator(
        userAci: Aci,
        newGroupModel: TSGroupModel
    ) {

        if let newGroupModelV2 = newGroupModel as? TSGroupModelV2,
           newGroupModelV2.wasJustMigrated {
            // All v1 group members become admins when the
            // group is migrated to v2. We don't need to
            // surface this to the user.
            return
        }

        if localIdentifiers.aci == userAci {
            switch groupUpdateSource {
            case .localUser:
                owsFailDebug("Local user made themselves administrator!")
                addItem(.localUserWasGrantedAdministratorByLocalUser)
            case let .aci(updaterAci):
                addItem(.localUserWasGrantedAdministratorByOtherUser(
                    updaterAci: updaterAci.codableUuid
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.localUserWasGrantedAdministratorByUnknownUser)
            }
        } else {
            switch groupUpdateSource {
            case .localUser:
                addItem(.otherUserWasGrantedAdministratorByLocalUser(
                    userAci: userAci.codableUuid
                ))
            case let .aci(updaterAci):
                if updaterAci == userAci {
                    owsFailDebug("Remote user made themselves administrator!")
                    addItem(.otherUserWasGrantedAdministratorByUnknownUser(
                        userAci: userAci.codableUuid
                    ))
                } else {
                    addItem(.otherUserWasGrantedAdministratorByOtherUser(
                        updaterAci: updaterAci.codableUuid,
                        userAci: userAci.codableUuid
                    ))
                }
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.otherUserWasGrantedAdministratorByUnknownUser(
                    userAci: userAci.codableUuid
                ))
            }
        }
    }

    mutating func addUserWasRevokedAdministrator(
        userAci: Aci
    ) {
        if localIdentifiers.aci == userAci {
            switch groupUpdateSource {
            case .localUser:
                addItem(.localUserWasRevokedAdministratorByLocalUser)
            case let .aci(updaterAci):
                addItem(.localUserWasRevokedAdministratorByOtherUser(
                    updaterAci: updaterAci.codableUuid
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.localUserWasRevokedAdministratorByUnknownUser)
            }
        } else {
            switch groupUpdateSource {
            case .localUser:
                addItem(.otherUserWasRevokedAdministratorByLocalUser(
                    userAci: userAci.codableUuid
                ))
            case let .aci(updaterAci):
                if updaterAci == userAci {
                    addItem(.otherUserWasRevokedAdministratorByUnknownUser(
                        userAci: userAci.codableUuid
                    ))
                } else {
                    addItem(.otherUserWasRevokedAdministratorByOtherUser(
                        updaterAci: updaterAci.codableUuid,
                        userAci: userAci.codableUuid
                    ))
                }
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.otherUserWasRevokedAdministratorByUnknownUser(
                    userAci: userAci.codableUuid
                ))
            }
        }
    }

    mutating func addUserLeftOrWasKickedOutOfGroup(
        userAci: Aci
    ) {
        if localIdentifiers.aci == userAci {
            switch groupUpdateSource {
            case .localUser:
                addItem(.localUserLeft)
            case let .aci(updaterAci):
                addItem(.localUserRemoved(
                    removerAci: updaterAci.codableUuid
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.localUserRemovedByUnknownUser)
            }
        } else {
            switch groupUpdateSource {
            case .localUser:
                addItem(.otherUserRemovedByLocalUser(
                    userAci: userAci.codableUuid
                ))
            case let .aci(updaterAci):
                if updaterAci == userAci {
                    addItem(.otherUserLeft(userAci: userAci.codableUuid))
                } else {
                    addItem(.otherUserRemoved(
                        removerAci: updaterAci.codableUuid,
                        userAci: userAci.codableUuid
                    ))
                }
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.otherUserRemovedByUnknownUser(
                    userAci: userAci.codableUuid
                ))
            }
        }
    }

    mutating func addUserLeftOrWasKickedOutOfGroupThenWasInvitedToTheGroup(
        userAci: Aci
    ) {
        if localIdentifiers.aci == userAci {
            addItem(.localUserRemovedByUnknownUser)

            switch groupUpdateSource {
            case .localUser:
                owsFailDebug("User invited themselves to the group!")
                addItem(.localUserWasInvitedByLocalUser)
            case let .aci(updaterAci):
                addItem(.localUserWasInvitedByOtherUser(
                    updaterAci: updaterAci.codableUuid
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.localUserWasInvitedByUnknownUser)
            }
        } else {
            addItem(.otherUserLeft(
                userAci: userAci.codableUuid
            ))

            switch groupUpdateSource {
            case .localUser:
                addItem(.unnamedUsersWereInvitedByLocalUser(count: 1))
            case let .aci(updaterAci):
                addItem(.unnamedUsersWereInvitedByOtherUser(
                    updaterAci: updaterAci.codableUuid,
                    count: 1
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.unnamedUsersWereInvitedByUnknownUser(count: 1))
            }
        }
    }

    /// This code path does NOT handle invited Pnis accepting the invite as an aci.
    ///
    /// When a pni invite is accepted, it is necessarily the only update in the group; in those
    /// cases we short circuit in ``GroupUpdateInfoMessageInserterImpl``
    /// (see its usage of``InvitedPnisPromotionToFullMemberAcis``).
    /// We never even reach this method; we just store a ``PersistableGroupUpdateItem``
    /// (or, historically, a ``LegacyPersistableGroupUpdateItem``).
    mutating func addUserInvitedByAciAcceptedOrWasAdded(
        inviteeAci: Aci,
        oldGroupMembership: GroupMembership
    ) {
        let inviterAci = oldGroupMembership.addedByAci(forInvitedMember: inviteeAci)

        if localIdentifiers.aci == inviteeAci {
            switch groupUpdateSource {
            case .localUser:
                if let inviterAci {
                    addItem(.localUserAcceptedInviteFromInviter(
                        inviterAci: inviterAci.codableUuid
                    ))
                } else {
                    owsFailDebug("Missing inviter name!")
                    addItem(.localUserAcceptedInviteFromUnknownUser)
                }
            case let .aci(updaterAci):
                addItem(.localUserAddedByOtherUser(
                    updaterAci: updaterAci.codableUuid
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.localUserJoined)
            }
        } else {
            switch groupUpdateSource {
            case .localUser:
                addItem(.otherUserAddedByLocalUser(
                    userAci: inviteeAci.codableUuid
                ))
            case let .aci(updaterAci):
                if inviteeAci == updaterAci {
                    // The update came from the person who was invited.

                    if let inviterAci, localIdentifiers.aci == inviterAci {
                        addItem(.otherUserAcceptedInviteFromLocalUser(
                            userAci: inviteeAci.codableUuid
                        ))
                    } else if let inviterAci {
                        addItem(.otherUserAcceptedInviteFromInviter(
                            userAci: inviteeAci.codableUuid,
                            inviterAci: inviterAci.codableUuid
                        ))
                    } else {
                        owsFailDebug("Missing inviter name.")
                        addItem(.otherUserAcceptedInviteFromUnknownUser(
                            userAci: inviteeAci.codableUuid
                        ))
                    }
                } else {
                    addItem(.otherUserAddedByOtherUser(
                        updaterAci: updaterAci.codableUuid,
                        userAci: inviteeAci.codableUuid
                    ))
                }
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.otherUserJoined(
                    userAci: inviteeAci.codableUuid
                ))
            }
        }
    }

    /// An update item for the fact that the given invited address declined or
    /// had their invite revoked.
    /// - Returns
    /// An update item, if one could be created. If `nil` is returned, inspect
    /// `unnamedInviteCounts` to see if an unnamed invite was affected.
    mutating func addUserInviteWasDeclinedOrRevoked(
        inviteeServiceId: ServiceId,
        oldGroupMembership: GroupMembership,
        unnamedInviteCounts: inout UnnamedInviteCounts
    ) {
        let inviterAci = oldGroupMembership.addedByAci(forInvitedMember: inviteeServiceId)

        if localIdentifiers.isInviteeLocalUser(inviteeServiceId) {
            switch groupUpdateSource {
            case .localUser:
                if let inviterAci {
                    addItem(.localUserDeclinedInviteFromInviter(
                        inviterAci: inviterAci.codableUuid
                    ))
                } else {
                    owsFailDebug("Missing inviter name!")
                    addItem( .localUserDeclinedInviteFromUnknownUser)
                }
            case let .aci(updaterAci):
                addItem(.localUserInviteRevoked(
                    revokerAci: updaterAci.codableUuid
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.localUserInviteRevokedByUnknownUser)
            }
        } else {

            func addItemForOtherUser(_ updaterServiceId: ServiceId) {
                if inviteeServiceId == updaterServiceId {
                    if let inviterAci, localIdentifiers.aci == inviterAci {
                        addItem(.otherUserDeclinedInviteFromLocalUser(
                            invitee: inviteeServiceId.codableUppercaseString
                        ))
                    } else if let inviterAci {
                        addItem(.otherUserDeclinedInviteFromInviter(
                            invitee: inviteeServiceId.codableUppercaseString,
                            inviterAci: inviterAci.codableUuid
                        ))
                    } else {
                        addItem(.otherUserDeclinedInviteFromUnknownUser(
                            invitee: inviteeServiceId.codableUppercaseString
                        ))
                    }
                } else {
                    unnamedInviteCounts.revokedInviteCount += 1
                }
            }

            switch groupUpdateSource {
            case .localUser:
                addItem(.otherUserInviteRevokedByLocalUser(
                    invitee: inviteeServiceId.codableUppercaseString
                ))
            case .aci(let updaterAci):
                addItemForOtherUser(updaterAci)
            case .rejectedInviteToPni(let updaterPni):
                addItemForOtherUser(updaterPni)
            case .legacyE164, .unknown:
                unnamedInviteCounts.revokedInviteCount += 1
            }
        }
    }

    mutating func addUserWasAddedToTheGroup(
        newMember: Aci,
        newGroupModel: TSGroupModel
    ) {
        if newGroupModel.didJustAddSelfViaGroupLinkV2 {
            addItem(.localUserJoined)
        } else if newMember == localIdentifiers.aci {
            switch groupUpdateSource {
            case .localUser:
                owsFailDebug("User added themselves to the group and was updater - should not be possible.")
                addItem(.localUserAddedByLocalUser)
            case let .aci(updaterAci):
                addItem(.localUserAddedByOtherUser(
                    updaterAci: updaterAci.codableUuid
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.localUserAddedByUnknownUser)
            }
        } else {
            switch groupUpdateSource {
            case .localUser:
                addItem(.otherUserAddedByLocalUser(
                    userAci: newMember.codableUuid
                ))
            case let .aci(updaterAci):
                if updaterAci == newMember {
                    owsFailDebug("Remote user added themselves to the group!")

                    addItem(.otherUserAddedByUnknownUser(
                        userAci: newMember.codableUuid
                    ))
                } else {
                    addItem(.otherUserAddedByOtherUser(
                        updaterAci: updaterAci.codableUuid,
                        userAci: newMember.codableUuid
                    ))
                }
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.otherUserAddedByUnknownUser(
                    userAci: newMember.codableUuid
                ))
            }
        }
    }

    mutating func addUserJoinedFromInviteLink(
        newMember: Aci
    ) {
        if localIdentifiers.aci == newMember {
            switch groupUpdateSource {
            case .localUser:
                addItem(.localUserJoinedViaInviteLink)
            case .aci, .rejectedInviteToPni, .legacyE164:
                owsFailDebug("A user should never join the group via invite link unless they are the updater.")
                addItem(.localUserJoined)
            case .unknown:
                addItem(.localUserJoined)
            }
        } else {
            switch groupUpdateSource {
            case .aci(let updaterAci) where updaterAci == newMember:
                addItem(.otherUserJoinedViaInviteLink(
                    userAci: newMember.codableUuid
                ))
            default:
                owsFailDebug("If user joined via group link, they should be the updater!")
                addItem(.otherUserAddedByUnknownUser(
                    userAci: newMember.codableUuid
                ))
            }
        }
    }

    mutating func addUserWasInvitedToTheGroup(
        invitee: ServiceId,
        unnamedInviteCounts: inout UnnamedInviteCounts
    ) {
        if localIdentifiers.isInviteeLocalUser(invitee) {
            switch groupUpdateSource {
            case .localUser:
                owsFailDebug("User invited themselves to the group!")

                addItem(.localUserWasInvitedByLocalUser)
            case let .aci(updaterAci):
                addItem(.localUserWasInvitedByOtherUser(
                    updaterAci: updaterAci.codableUuid
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.localUserWasInvitedByUnknownUser)
            }
        } else {
            switch groupUpdateSource {
            case .localUser:
                addItem(.otherUserWasInvitedByLocalUser(
                    inviteeServiceId: invitee.codableUppercaseString
                ))
            default:
                unnamedInviteCounts.newInviteCount += 1
            }
        }
    }

    mutating func addUnnamedUsersWereInvited(count: UInt) {
        guard count > 0 else {
            return
        }

        switch groupUpdateSource {
        case .localUser:
            owsFailDebug("Unexpected updater - if local user is inviter, should not be unnamed.")
            addItem(.unnamedUsersWereInvitedByLocalUser(count: count))
        case let .aci(updaterAci):
            addItem(.unnamedUsersWereInvitedByOtherUser(
                updaterAci: updaterAci.codableUuid,
                count: count
            ))
        case .rejectedInviteToPni, .legacyE164, .unknown:
            addItem(.unnamedUsersWereInvitedByUnknownUser(count: count))
        }
    }

    mutating func addUnnamedUserInvitesWereRevoked(count: UInt) {
        guard count > 0 else {
            return
        }

        switch groupUpdateSource {
        case .localUser:
            owsFailDebug("When local user is updater, should have named invites!")
            addItem(.unnamedUserInvitesWereRevokedByLocalUser(count: count))
        case let .aci(updaterAci):
            addItem(.unnamedUserInvitesWereRevokedByOtherUser(
                updaterAci: updaterAci.codableUuid,
                count: count
            ))
        case .rejectedInviteToPni, .legacyE164, .unknown:
            addItem(.unnamedUserInvitesWereRevokedByUnknownUser(count: count))
        }
    }

    // MARK: Requesting Members

    mutating func addUserRequestedToJoinGroup(
        requesterAci: Aci
    ) {
        if localIdentifiers.aci == requesterAci {
            addItem(.localUserRequestedToJoin)
        } else {
            addItem(.otherUserRequestedToJoin(
                userAci: requesterAci.codableUuid
            ))
        }
    }

    mutating func addUserRequestWasApproved(
        requesterAci: Aci
    ) {
        if localIdentifiers.aci == requesterAci {
            switch groupUpdateSource {
            case .localUser:
                // This could happen if the user requested to join a group
                // and became a requesting member, then tried to join the
                // group again and was added because the group stopped
                // requiring approval in the interim.
                owsFailDebug("User added themselves to the group and was updater - should not be possible.")
                addItem(.localUserAddedByLocalUser)
            case .aci(let updaterAci):
                addItem(.localUserRequestApproved(
                    approverAci: updaterAci.codableUuid
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.localUserRequestApprovedByUnknownUser)
            }
        } else {
            switch groupUpdateSource {
            case .localUser:
                addItem(.otherUserRequestApprovedByLocalUser(
                    userAci: requesterAci.codableUuid
                ))
            case .aci(let updaterAci):
                addItem(.otherUserRequestApproved(
                    userAci: requesterAci.codableUuid,
                    approverAci: updaterAci.codableUuid
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.otherUserRequestApprovedByUnknownUser(
                    userAci: requesterAci.codableUuid
                ))
            }
        }
    }

    mutating func addUserRequestWasRejected(
        requesterAci: Aci
    ) {
        if localIdentifiers.aci == requesterAci {
            switch groupUpdateSource {
            case .localUser:
                addItem(.localUserRequestCanceledByLocalUser)
            case .aci, .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.localUserRequestRejectedByUnknownUser)
            }
        } else {
            switch groupUpdateSource {
            case .localUser:
                addItem(.otherUserRequestRejectedByLocalUser(
                    requesterAci: requesterAci.codableUuid
                ))
            case let .aci(updaterAci):
                if updaterAci == requesterAci {
                    addItem(.otherUserRequestCanceledByOtherUser(
                        requesterAci: requesterAci.codableUuid
                    ))
                } else {
                    addItem(.otherUserRequestRejectedByOtherUser(
                        updaterAci: updaterAci.codableUuid,
                        requesterAci: requesterAci.codableUuid
                    ))
                }
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.otherUserRequestRejectedByUnknownUser(
                    requesterAci: requesterAci.codableUuid
                ))
            }
        }
    }

    // MARK: Disappearing Messages

    /// Add disappearing message timer updates to the item list.
    ///
    /// - Important
    /// This method checks for other updates that have already been added. Use
    /// caution when reorganizing any calls to this method.
    mutating func addDisappearingMessageUpdates(
        oldToken: DisappearingMessageToken?,
        newToken: DisappearingMessageToken?
    ) {
        // If this update represents us joining the group, we want to make
        // sure we use "unknown" attribution for whatever the disappearing
        // message timer is set to. Since we just joined, we can't know who
        // set the timer.
        let localUserJustJoined = itemList.contains { updateItem in
            switch updateItem {
            case
                    .localUserJoined,
                    .localUserJoinedViaInviteLink,
                    .localUserRequestApproved,
                    .localUserRequestApprovedByUnknownUser:
                return true
            default:
                return false
            }
        }

        Self.disappearingMessageUpdateItem(
            groupUpdateSource: groupUpdateSource,
            oldToken: oldToken,
            newToken: newToken,
            forceUnknownAttribution: localUserJustJoined
        ).map {
            addItem($0)
        }
    }

    static func disappearingMessageUpdateItem(
        groupUpdateSource: GroupUpdateSource,
        oldToken: DisappearingMessageToken?,
        newToken: DisappearingMessageToken?,
        forceUnknownAttribution: Bool
    ) -> PersistableGroupUpdateItem? {
        guard let newToken else {
            // This info message was created before we embedded DM state.
            return nil
        }

        // This might be zero if DMs are not enabled.
        let durationMs = UInt64(newToken.durationSeconds) * 1000

        if forceUnknownAttribution, newToken.isEnabled {
            return .disappearingMessagesEnabledByUnknownUser(durationMs: durationMs)
        }

        if let oldToken, newToken == oldToken {
            // No change to disappearing message configuration occurred.
            return nil
        }

        if newToken.isEnabled && durationMs > 0 {
            switch groupUpdateSource {
            case .localUser:
                return .disappearingMessagesEnabledByLocalUser(durationMs: durationMs)
            case let .aci(updaterAci):
                return .disappearingMessagesEnabledByOtherUser(
                    updaterAci: updaterAci.codableUuid,
                    durationMs: durationMs
                )
            case .rejectedInviteToPni, .legacyE164, .unknown:
                return .disappearingMessagesEnabledByUnknownUser(durationMs: durationMs)
            }
        } else {
            switch groupUpdateSource {
            case .localUser:
                return .disappearingMessagesDisabledByLocalUser
            case let .aci(updaterAci):
                return .disappearingMessagesDisabledByOtherUser(
                    updaterAci: updaterAci.codableUuid
                )
            case .rejectedInviteToPni, .legacyE164, .unknown:
                return .disappearingMessagesDisabledByUnknownUser
            }
        }
    }

    // MARK: Group Invite Links

    mutating func addGroupInviteLinkUpdates(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel
    ) {
        guard let oldGroupModel = oldGroupModel as? TSGroupModelV2 else {
            return
        }
        guard let newGroupModel = newGroupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid group model.")
            return
        }
        let oldGroupInviteLinkMode = oldGroupModel.groupInviteLinkMode
        let newGroupInviteLinkMode = newGroupModel.groupInviteLinkMode

        guard oldGroupInviteLinkMode != newGroupInviteLinkMode else {
            if
                let oldInviteLinkPassword = oldGroupModel.inviteLinkPassword,
                let newInviteLinkPassword = newGroupModel.inviteLinkPassword,
                oldInviteLinkPassword != newInviteLinkPassword
            {
                switch groupUpdateSource {
                case .localUser:
                    addItem(.inviteLinkResetByLocalUser)
                case let .aci(updaterAci):
                    addItem(.inviteLinkResetByOtherUser(
                        updaterAci: updaterAci.codableUuid
                    ))
                case .rejectedInviteToPni, .legacyE164, .unknown:
                    addItem(.inviteLinkResetByUnknownUser)
                }
            }

            return
        }

        switch oldGroupInviteLinkMode {
        case .disabled:
            switch newGroupInviteLinkMode {
            case .disabled:
                owsFailDebug("State did not change.")
            case .enabledWithoutApproval:
                switch groupUpdateSource {
                case .localUser:
                    addItem(.inviteLinkEnabledWithoutApprovalByLocalUser)
                case let .aci(updaterAci):
                    addItem(.inviteLinkEnabledWithoutApprovalByOtherUser(
                        updaterAci: updaterAci.codableUuid
                    ))
                case .rejectedInviteToPni, .legacyE164, .unknown:
                    addItem(.inviteLinkEnabledWithoutApprovalByUnknownUser)
                }
            case .enabledWithApproval:
                switch groupUpdateSource {
                case .localUser:
                    addItem(.inviteLinkEnabledWithApprovalByLocalUser)
                case let .aci(updaterAci):
                    addItem(.inviteLinkEnabledWithApprovalByOtherUser(
                        updaterAci: updaterAci.codableUuid
                    ))
                case .rejectedInviteToPni, .legacyE164, .unknown:
                    addItem(.inviteLinkEnabledWithApprovalByUnknownUser)
                }
            }
        case .enabledWithoutApproval, .enabledWithApproval:
            switch newGroupInviteLinkMode {
            case .disabled:
                switch groupUpdateSource {
                case .localUser:
                    addItem(.inviteLinkDisabledByLocalUser)
                case let .aci(updaterAci):
                    addItem(.inviteLinkDisabledByOtherUser(
                        updaterAci: updaterAci.codableUuid
                    ))
                case .rejectedInviteToPni, .legacyE164, .unknown:
                    addItem(.inviteLinkDisabledByUnknownUser)
                }
            case .enabledWithoutApproval:
                switch groupUpdateSource {
                case .localUser:
                    addItem(.inviteLinkApprovalDisabledByLocalUser)
                case let .aci(updaterAci):
                    addItem(.inviteLinkApprovalDisabledByOtherUser(
                        updaterAci: updaterAci.codableUuid
                    ))
                case .rejectedInviteToPni, .legacyE164, .unknown:
                    addItem(.inviteLinkApprovalDisabledByUnknownUser)
                }
            case .enabledWithApproval:
                switch groupUpdateSource {
                case .localUser:
                    addItem(.inviteLinkApprovalEnabledByLocalUser)
                case let .aci(updaterAci):
                    addItem(.inviteLinkApprovalEnabledByOtherUser(
                        updaterAci: updaterAci.codableUuid
                    ))
                case .rejectedInviteToPni, .legacyE164, .unknown:
                    addItem(.inviteLinkApprovalEnabledByUnknownUser)
                }
            }
        }
    }

    // MARK: Announcement-Only Groups

    mutating func addIsAnnouncementOnlyLinkUpdates(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel
    ) {
        guard let oldGroupModel = oldGroupModel as? TSGroupModelV2 else {
            return
        }
        guard let newGroupModel = newGroupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid group model.")
            return
        }
        let oldIsAnnouncementsOnly = oldGroupModel.isAnnouncementsOnly
        let newIsAnnouncementsOnly = newGroupModel.isAnnouncementsOnly

        guard oldIsAnnouncementsOnly != newIsAnnouncementsOnly else {
            return
        }

        if newIsAnnouncementsOnly {
            switch groupUpdateSource {
            case .localUser:
                addItem(.announcementOnlyEnabledByLocalUser)
            case let .aci(aci):
                addItem(.announcementOnlyEnabledByOtherUser(
                    updaterAci: aci.codableUuid
                ))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.announcementOnlyEnabledByUnknownUser)
            }
        } else {
            switch groupUpdateSource {
            case .localUser:
                addItem(.announcementOnlyDisabledByLocalUser)
            case let .aci(aci):
                addItem(.announcementOnlyEnabledByOtherUser(updaterAci: aci.codableUuid))
            case .rejectedInviteToPni, .legacyE164, .unknown:
                addItem(.announcementOnlyDisabledByUnknownUser)
            }
        }
    }

    // MARK: Migration

    private func wasJustMigrated(newGroupModel: TSGroupModel) -> Bool {
        guard let newGroupModelV2 = newGroupModel as? TSGroupModelV2,
              newGroupModelV2.wasJustMigrated else {
            return false
        }
        return true
    }

    mutating func addMigrationUpdates(
        oldGroupMembership: GroupMembership,
        newGroupMembership: GroupMembership,
        newGroupModel: TSGroupModel
    ) {
        owsAssertDebug(wasJustMigrated(newGroupModel: newGroupModel))
        addItem(.wasMigrated)
    }
}

// MARK: -

private extension LocalIdentifiers {
    func isLocalUser(address: SignalServiceAddress?) -> Bool {
        guard let address else { return false }
        return contains(address: address)
    }
}

// MARK: - Dependencies

internal typealias Shims = GroupUpdateItemBuilderImpl.Shims
private typealias IsLocalUserBlock = (SignalServiceAddress) -> Bool

extension GroupUpdateItemBuilderImpl {
    enum Shims {
        typealias ContactsManager = _GroupUpdateCopy_ContactsManager_Shim
    }

    enum Wrappers {
        typealias ContactsManager = _GroupUpdateCopy_ContactsManager_Wrapper
    }
}

protocol _GroupUpdateCopy_ContactsManager_Shim {
    func displayName(address: SignalServiceAddress, tx: DBReadTransaction) -> String
}

class _GroupUpdateCopy_ContactsManager_Wrapper: _GroupUpdateCopy_ContactsManager_Shim {
    private let contactsManager: ContactsManagerProtocol

    init(_ contactsManager: ContactsManagerProtocol) {
        self.contactsManager = contactsManager
    }

    func displayName(address: SignalServiceAddress, tx: DBReadTransaction) -> String {
        return contactsManager.displayName(for: address, transaction: SDSDB.shimOnlyBridge(tx))
    }
}
