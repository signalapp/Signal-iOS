//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public protocol DisplayableGroupUpdateItemBuilder {
    /// Build a list of group updates using the given precomputed, persisted
    /// update items.
    ///
    /// - Important
    /// If there are precomputed update items available, this method should be
    /// preferred over all others.
    func displayableUpdateItemsForPrecomputed(
        precomputedUpdateItems: [TSInfoMessage.PersistableGroupUpdateItem],
        oldGroupModel: TSGroupModel?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSourceAddress: SignalServiceAddress?,
        updaterKnownToBeLocalUser: Bool,
        tx: DBReadTransaction
    ) -> [DisplayableGroupUpdateItem]

    /// Build group update items for a just-inserted group.
    ///
    /// - Note
    /// You should use this method if there are neither precomputed update items
    /// nor an "old group model" available.
    func displayableUpdateItemsForNewGroup(
        newGroupModel: TSGroupModel,
        newDisappearingMessageToken: DisappearingMessageToken?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSourceAddress: SignalServiceAddress?,
        updaterKnownToBeLocalUser: Bool,
        tx: DBReadTransaction
    ) -> [DisplayableGroupUpdateItem]

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
        groupUpdateSourceAddress: SignalServiceAddress?,
        updaterKnownToBeLocalUser: Bool,
        tx: DBReadTransaction
    ) -> [DisplayableGroupUpdateItem]

    /// Get a default group update item, if the models required to build more
    /// specific group updates are not available.
    func defaultDisplayableUpdateItem(
        groupUpdateSourceAddress: SignalServiceAddress?,
        localIdentifiers: LocalIdentifiers?,
        tx: DBReadTransaction
    ) -> DisplayableGroupUpdateItem
}

public struct DisplayableGroupUpdateItemBuilderImpl: DisplayableGroupUpdateItemBuilder {
    private let contactsManager: Shims.ContactsManager

    init(contactsManager: Shims.ContactsManager) {
        self.contactsManager = contactsManager
    }

    public func displayableUpdateItemsForNewGroup(
        newGroupModel: TSGroupModel,
        newDisappearingMessageToken: DisappearingMessageToken?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSourceAddress: SignalServiceAddress?,
        updaterKnownToBeLocalUser: Bool,
        tx: DBReadTransaction
    ) -> [DisplayableGroupUpdateItem] {
        let updater: Updater = .build(
            localIdentifiers: localIdentifiers,
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            updaterKnownToBeLocalUser: updaterKnownToBeLocalUser,
            contactsManager: contactsManager,
            tx: tx
        )

        let items = NewGroupUpdateItemBuilder(
            contactsManager: contactsManager
        ).buildGroupUpdateItems(
            newGroupModel: newGroupModel,
            newDisappearingMessageToken: newDisappearingMessageToken,
            updater: updater,
            localIdentifiers: localIdentifiers,
            tx: tx
        )

        return validateUpdateItemsNotEmpty(
            tentativeUpdateItems: items,
            updater: updater
        )
    }

    public func displayableUpdateItemsForPrecomputed(
        precomputedUpdateItems: [TSInfoMessage.PersistableGroupUpdateItem],
        oldGroupModel: TSGroupModel?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSourceAddress: SignalServiceAddress?,
        updaterKnownToBeLocalUser: Bool,
        tx: DBReadTransaction
    ) -> [DisplayableGroupUpdateItem] {
        let updater: Updater = .build(
            localIdentifiers: localIdentifiers,
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            updaterKnownToBeLocalUser: updaterKnownToBeLocalUser,
            contactsManager: contactsManager,
            tx: tx
        )

        let items = PrecomputedGroupUpdateItemBuilder(
            contactsManager: contactsManager
        ).buildGroupUpdateItems(
            precomputedUpdateItems: precomputedUpdateItems,
            oldGroupMembership: oldGroupModel?.groupMembership,
            updater: updater,
            localIdentifiers: localIdentifiers,
            tx: tx
        )

        return validateUpdateItemsNotEmpty(
            tentativeUpdateItems: items,
            updater: updater
        )
    }

    public func displayableUpdateItemsByDiffingModels(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken?,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSourceAddress: SignalServiceAddress?,
        updaterKnownToBeLocalUser: Bool,
        tx: DBReadTransaction
    ) -> [DisplayableGroupUpdateItem] {
        let updater: Updater = .build(
            localIdentifiers: localIdentifiers,
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            updaterKnownToBeLocalUser: updaterKnownToBeLocalUser,
            contactsManager: contactsManager,
            tx: tx
        )

        let items = DiffingGroupUpdateItemBuilder(
            oldGroupModel: oldGroupModel,
            newGroupModel: newGroupModel,
            oldDisappearingMessageToken: oldDisappearingMessageToken,
            newDisappearingMessageToken: newDisappearingMessageToken,
            updater: updater,
            localIdentifiers: localIdentifiers,
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            contactsManager: contactsManager,
            tx: tx
        ).itemList

        return validateUpdateItemsNotEmpty(
            tentativeUpdateItems: items,
            updater: updater
        )
    }

    public func defaultDisplayableUpdateItem(
        groupUpdateSourceAddress: SignalServiceAddress?,
        localIdentifiers: LocalIdentifiers?,
        tx: DBReadTransaction
    ) -> DisplayableGroupUpdateItem {
        return DefaultGroupUpdateItemBuilder().buildGroupUpdateItem(
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            localIdentifiers: localIdentifiers,
            contactsManager: contactsManager,
            tx: tx
        )
    }

    private func validateUpdateItemsNotEmpty(
        tentativeUpdateItems: [DisplayableGroupUpdateItem],
        updater: Updater,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) -> [DisplayableGroupUpdateItem] {
        guard tentativeUpdateItems.isEmpty else {
            return tentativeUpdateItems
        }

        owsFailDebug("Empty group update!", file: file, function: function, line: line)

        switch updater {
        case .localUser:
            return [.genericUpdateByLocalUser]
        case let .otherUser(updaterName, updaterAddress):
            return [.genericUpdateByOtherUser(
                updaterName: updaterName,
                updaterAddress: updaterAddress
            )]
        case .unknown:
            return [.genericUpdateByUnknownUser]
        }
    }
}

// MARK: -

private enum Updater {
    case localUser
    case otherUser(updaterName: String, updaterAddress: SignalServiceAddress)
    case unknown

    /// Determine who this update should be attributed to.
    ///
    /// - Parameter updaterKnownToBeLocalUser
    /// Whether we know ahead of time that the updater is the local user.
    static func build(
        localIdentifiers: LocalIdentifiers?,
        groupUpdateSourceAddress: SignalServiceAddress?,
        updaterKnownToBeLocalUser: Bool,
        contactsManager: Shims.ContactsManager,
        tx: DBReadTransaction
    ) -> Updater {
        if updaterKnownToBeLocalUser {
            return .localUser
        }

        guard let updaterAddress = groupUpdateSourceAddress else {
            return .unknown
        }

        if let localIdentifiers, localIdentifiers.contains(address: updaterAddress) {
            return .localUser
        }

        return .otherUser(
            updaterName: contactsManager.displayName(address: updaterAddress, tx: tx),
            updaterAddress: updaterAddress
        )
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

private struct PrecomputedGroupUpdateItemBuilder {
    private let contactsManager: Shims.ContactsManager

    init(contactsManager: Shims.ContactsManager) {
        self.contactsManager = contactsManager
    }

    func buildGroupUpdateItems(
        precomputedUpdateItems: [TSInfoMessage.PersistableGroupUpdateItem],
        oldGroupMembership: GroupMembership?,
        updater: Updater,
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction
    ) -> [DisplayableGroupUpdateItem] {
        return precomputedUpdateItems.compactMap { persistableGroupUpdateItem -> DisplayableGroupUpdateItem? in
            switch persistableGroupUpdateItem {
            case let .sequenceOfInviteLinkRequestAndCancels(count, isTail):
                return sequenceOfInviteLinkRequestAndCancelsItem(
                    updater: updater,
                    count: count,
                    isTail: isTail
                )
            case let .invitedPniPromotedToFullMemberAci(pni, aci):
                let invitedPniAddress = SignalServiceAddress(pni.wrappedValue)
                let fullMemberAciAddress = SignalServiceAddress(aci.wrappedValue)

                return DiffingGroupUpdateItemBuilder.userInviteWasAcceptedItem(
                    invitedAsAddress: invitedPniAddress,
                    acceptedAsAddress: fullMemberAciAddress,
                    oldGroupMembership: oldGroupMembership,
                    updater: updater,
                    isLocalUserBlock: { localIdentifiers.isLocalUser(address: $0) },
                    contactsManager: contactsManager,
                    tx: tx
                )
            case let .inviteRemoved(invitee, wasLocalUser):
                var unnamedInviteCounts = UnnamedInviteCounts()

                if let item = DiffingGroupUpdateItemBuilder.userInviteWasDeclinedOrRevokedItem(
                    inviteeAddress: SignalServiceAddress(invitee.wrappedValue),
                    inviteeKnownToBeLocalUser: wasLocalUser,
                    oldGroupMembership: oldGroupMembership,
                    unnamedInviteCounts: &unnamedInviteCounts,
                    updater: updater,
                    isLocalUserBlock: { localIdentifiers.isLocalUser(address: $0) },
                    contactsManager: contactsManager,
                    tx: tx
                ) {
                    return item
                } else {
                    return DiffingGroupUpdateItemBuilder.unnamedUserInvitesWereRevokedItem(
                        count: unnamedInviteCounts.revokedInviteCount,
                        updater: updater
                    )
                }
            }
        }
    }

    private func sequenceOfInviteLinkRequestAndCancelsItem(
        updater: Updater,
        count: UInt,
        isTail: Bool
    ) -> DisplayableGroupUpdateItem? {
        let updaterName: String
        let updaterAddress: SignalServiceAddress
        switch updater {
        case .localUser:
            owsFailDebug("How did we create one of these for the local user? That should never happen!")
            return nil
        case .unknown:
            owsFailDebug("How did we create one of these for an unknown user? That should never happen!")
            return nil
        case let .otherUser(updaterNameParam, updaterAddressParam):
            updaterName = updaterNameParam
            updaterAddress = updaterAddressParam
        }

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

private struct NewGroupUpdateItemBuilder {
    private let contactsManager: Shims.ContactsManager

    init(contactsManager: Shims.ContactsManager) {
        self.contactsManager = contactsManager
    }

    func buildGroupUpdateItems(
        newGroupModel: TSGroupModel,
        newDisappearingMessageToken: DisappearingMessageToken?,
        updater: Updater,
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction
    ) -> [DisplayableGroupUpdateItem] {
        var items = [DisplayableGroupUpdateItem]()

        // We're just learning of the group.
        let groupWasInsertedItem = groupWasInsertedItem(
            updater: updater,
            localIdentifiers: localIdentifiers,
            newGroupModel: newGroupModel,
            newGroupMembership: newGroupModel.groupMembership,
            tx: tx
        )

        groupWasInsertedItem.map { items.append($0) }

        // Skip update items for things like name, avatar, current members. Do
        // add update items for the current disappearing messages state. We can
        // use unknown attribution here – either we created the group (so it was
        // us who set the time) or someone else did (so we don't know who set
        // the timer), and unknown attribution is always safe.
        DiffingGroupUpdateItemBuilder.disappearingMessageUpdateItem(
            updater: updater,
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
        updater: Updater,
        localIdentifiers: LocalIdentifiers,
        newGroupModel: TSGroupModel,
        newGroupMembership: GroupMembership,
        tx: DBReadTransaction
    ) -> DisplayableGroupUpdateItem? {
        guard let newGroupModel = newGroupModel as? TSGroupModelV2 else {
            // This is a V1 group. While we may be able to be more specific, we
            // shouldn't stress over V1 group update messages.
            return .createdByUnknownUser
        }

        let wasGroupJustCreated = newGroupModel.revision == 0
        if wasGroupJustCreated {
            switch updater {
            case .localUser:
                return .createdByLocalUser
            case let .otherUser(updaterName, updaterAddress):
                return .createdByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                )
            case .unknown:
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

            switch updater {
            case let .otherUser(updaterName, updaterAddress):
                return .localUserAddedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
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
                let inviterAddress = SignalServiceAddress(inviterAci)

                return .localUserWasInvitedByOtherUser(
                    updaterName: contactsManager.displayName(address: inviterAddress, tx: tx),
                    updaterAddress: inviterAddress
                )
            } else {
                return .localUserWasInvitedByUnknownUser
            }
        case .requesting:
            return DiffingGroupUpdateItemBuilder.userRequestedToJoinUpdateItem(
                address: localIdentifiers.aciAddress,
                isLocalUserBlock: { localIdentifiers.isLocalUser(address: $0) },
                contactsManager: contactsManager,
                tx: tx
            )
        case .none:
            owsFailDebug("Group was inserted without local membership!")
            return nil
        }
    }
}

// MARK: -

/// This type populates itself, on initialization, with items representing the
/// updates made to a group. These updates are determined by "diffing" the old
/// and new group states, alongside information such as who the "updater" was.
///
/// The returned updates map to user-presentable localized strings.
///
/// - Note:
/// Historically, group update items were computed using a struct that populated
/// itself with update items during initialization. Rather than refactor many,
/// many call sites to pass through the historically stored-as-properties values
/// used by that computation, we preserve that pattern here and wrap it in a
/// protocolized type above.
private struct DiffingGroupUpdateItemBuilder {
    private let contactsManager: Shims.ContactsManager

    private let localIdentifiers: LocalIdentifiers
    private let updater: Updater
    private let isReplacingJoinRequestPlaceholder: Bool

    /// The update items, in order.
    private(set) var itemList = [DisplayableGroupUpdateItem]()

    /// Create a ``GroupUpdateCopy``.
    ///
    /// - Parameter groupUpdateSourceAddress
    /// The address to whom this update should be attributed, if known.
    /// - Parameter updaterKnownToBeLocalUser
    /// Whether we know, ahead of time, that this update should be attributed to
    /// the local user. Necessary if we cannot reliably determine attribution
    /// via ``groupUpdateSourceAddress`` alone. For example, the update address
    /// may refer to a PNI that has moved to another owner.
    init(
        oldGroupModel: TSGroupModel,
        newGroupModel: TSGroupModel,
        oldDisappearingMessageToken: DisappearingMessageToken?,
        newDisappearingMessageToken: DisappearingMessageToken?,
        updater: Updater,
        localIdentifiers: LocalIdentifiers,
        groupUpdateSourceAddress: SignalServiceAddress?,
        contactsManager: Shims.ContactsManager,
        tx: DBReadTransaction
    ) {
        self.contactsManager = contactsManager

        self.localIdentifiers = localIdentifiers
        self.updater = updater

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
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            tx: tx
        )

        switch updater {
        case .unknown:
            Logger.warn("Missing updater info!")
        default:
            break
        }
    }

    /// Returns whether the given address matches the local user's ACI or PNI.
    private func isLocalUser(address: SignalServiceAddress?) -> Bool {
        return localIdentifiers.isLocalUser(address: address)
    }

    /// Returns whether the local user is contained in the given addresses.
    private func isLocalUser(inAddresses addresses: any Sequence<SignalServiceAddress>) -> Bool {
        return addresses.contains { isLocalUser(address: $0) }
    }

    private mutating func addItem(_ item: DisplayableGroupUpdateItem) {
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
        groupUpdateSourceAddress: SignalServiceAddress?,
        tx: DBReadTransaction
    ) {
        if isReplacingJoinRequestPlaceholder {
            addMembershipUpdates(
                oldGroupMembership: oldGroupModel.groupMembership,
                newGroupMembership: newGroupModel.groupMembership,
                newGroupModel: newGroupModel,
                groupUpdateSourceAddress: groupUpdateSourceAddress,
                forLocalUserOnly: true,
                tx: tx
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
                groupUpdateSourceAddress: groupUpdateSourceAddress,
                forLocalUserOnly: false,
                tx: tx
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
                switch updater {
                case .localUser:
                    addItem(.nameChangedByLocalUser(newGroupName: name))
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.nameChangedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress,
                        newGroupName: name
                    ))
                case .unknown:
                    addItem(.nameChangedByUnknownUser(newGroupName: name))
                }
            } else {
                switch updater {
                case .localUser:
                    addItem(.nameRemovedByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.nameRemovedByOtherUser(updaterName: updaterName, updaterAddress: updaterAddress))
                case .unknown:
                    addItem(.nameRemovedByUnknownUser)
                }
            }
        }

        if oldGroupModel.avatarHash != newGroupModel.avatarHash {
            if !newGroupModel.avatarHash.isEmptyOrNil {
                switch updater {
                case .localUser:
                    addItem(.avatarChangedByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.avatarChangedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.avatarChangedByUnknownUser)
                }
            } else {
                switch updater {
                case .localUser:
                    addItem(.avatarRemovedByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.avatarRemovedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
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
                switch updater {
                case .localUser:
                    addItem(.descriptionChangedByLocalUser(newDescription: newGroupDescription))
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.descriptionChangedByOtherUser(
                        newDescription: newGroupDescription,
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.descriptionChangedByUnknownUser(newDescription: newGroupDescription))
                }
            } else {
                switch updater {
                case .localUser:
                    addItem(.descriptionRemovedByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.descriptionRemovedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
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
            switch updater {
            case .localUser:
                addItem(.membersAccessChangedByLocalUser(newAccess: newAccess.members))
            case let .otherUser(updaterName, updaterAddress):
                addItem(.membersAccessChangedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress,
                    newAccess: newAccess.members
                ))
            case .unknown:
                addItem(.membersAccessChangedByUnknownUser(newAccess: newAccess.members))
            }
        }

        if oldAccess.attributes != newAccess.attributes {
            switch updater {
            case .localUser:
                addItem(.attributesAccessChangedByLocalUser(newAccess: newAccess.attributes))
            case let .otherUser(updaterName, updaterAddress):
                addItem(.attributesAccessChangedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress,
                    newAccess: newAccess.attributes
                ))
            case .unknown:
                addItem(.attributesAccessChangedByUnknownUser(newAccess: newAccess.attributes))
            }
        }
    }

    // MARK: Membership

    mutating func addMembershipUpdates(
        oldGroupMembership: GroupMembership,
        newGroupMembership: GroupMembership,
        newGroupModel: TSGroupModel,
        groupUpdateSourceAddress: SignalServiceAddress?,
        forLocalUserOnly: Bool,
        tx: DBReadTransaction
    ) {
        var unnamedInviteCounts = UnnamedInviteCounts()

        let allUsersUnsorted = oldGroupMembership.allMembersOfAnyKind.union(newGroupMembership.allMembersOfAnyKind)
        var allUsersSorted = Array(allUsersUnsorted).stableSort()

        /// Move the given service ID to the front of ``allUsersSorted``, if it
        /// is present therein.
        func moveServiceIdToFront(_ serviceId: ServiceId?) {
            guard let address = serviceId.map({ SignalServiceAddress($0) }) else { return }

            if allUsersSorted.contains(address) {
                allUsersSorted = [address] + allUsersSorted.filter { $0 != address }
            }
        }

        // If the local user has a membership update, sort it to the front.
        moveServiceIdToFront(localIdentifiers.pni)
        moveServiceIdToFront(localIdentifiers.aci)

        // If the updater has changed their membership status, ensure it appears _last_.
        // This trumps the re-ordering of the local user above.
        if let updaterAddress = groupUpdateSourceAddress {
            allUsersSorted = allUsersSorted.filter { $0 != updaterAddress } + [updaterAddress]
        }

        for address in allUsersSorted {
            if forLocalUserOnly, !isLocalUser(address: address) {
                continue
            }

            let oldMembershipStatus: MembershipStatus = .of(address: address, groupMembership: oldGroupMembership)
            let newMembershipStatus: MembershipStatus = .of(address: address, groupMembership: newGroupMembership)

            switch oldMembershipStatus {
            case .normalMember:
                switch newMembershipStatus {
                case .normalMember:
                    // Membership status didn't change.
                    // Check for role changes.
                    addMemberRoleUpdates(
                        address: address,
                        oldGroupMembership: oldGroupMembership,
                        newGroupMembership: newGroupMembership,
                        newGroupModel: newGroupModel,
                        tx: tx
                    )
                case .invited:
                    addUserLeftOrWasKickedOutOfGroupThenWasInvitedToTheGroup(address: address, tx: tx)
                case .requesting:
                    // This could happen if a user leaves a group, the requests to rejoin
                    // and we do have access to the intervening revisions.
                    addUserRequestedToJoinGroup(address: address, tx: tx)
                case .none:
                    addUserLeftOrWasKickedOutOfGroup(address: address, tx: tx)
                }
            case .invited:
                switch newMembershipStatus {
                case .normalMember:
                    let wasInviteAccepted: Bool = {
                        switch updater {
                        case .localUser:
                            return isLocalUser(address: address)
                        case .otherUser(_, let updaterAddress):
                            return updaterAddress == address
                        case .unknown:
                            return false
                        }
                    }()

                    if wasInviteAccepted {
                        addUserInviteWasAccepted(
                            invitedAsAddress: address,
                            acceptedAsAddress: address,
                            oldGroupMembership: oldGroupMembership,
                            tx: tx
                        )
                    } else {
                        addUserWasAddedToTheGroup(
                            address: address,
                            newGroupModel: newGroupModel,
                            tx: tx
                        )
                    }
                case .invited:
                    // Membership status didn't change.
                    break
                case .requesting:
                    addUserRequestedToJoinGroup(address: address, tx: tx)
                case .none:
                    addUserInviteWasDeclinedOrRevoked(
                        inviteeAddress: address,
                        inviteeKnownToBeLocalUser: false,
                        oldGroupMembership: oldGroupMembership,
                        unnamedInviteCounts: &unnamedInviteCounts,
                        tx: tx
                    )
                }
            case .requesting:
                switch newMembershipStatus {
                case .normalMember:
                    if newGroupMembership.didJoinFromAcceptedJoinRequest(forFullMember: address) {
                        addUserRequestWasApproved(
                            address: address,
                            oldGroupMembership: oldGroupMembership,
                            tx: tx
                        )
                    } else {
                        addUserWasAddedToTheGroup(
                            address: address,
                            newGroupModel: newGroupModel,
                            tx: tx
                        )
                    }
                case .invited:
                    addUserWasInvitedToTheGroup(
                        address: address,
                        unnamedInviteCounts: &unnamedInviteCounts,
                        tx: tx
                    )
                case .requesting:
                    // Membership status didn't change.
                    break
                case .none:
                    addUserRequestWasRejected(address: address, tx: tx)
                }
            case .none:
                switch newMembershipStatus {
                case .normalMember:
                    if newGroupMembership.didJoinFromInviteLink(forFullMember: address) {
                        addUserJoinedFromInviteLink(address: address, tx: tx)
                    } else if newGroupMembership.didJoinFromAcceptedJoinRequest(forFullMember: address) {
                        addUserRequestWasApproved(
                            address: address,
                            oldGroupMembership: oldGroupMembership,
                            tx: tx
                        )
                    } else {
                        addUserWasAddedToTheGroup(
                            address: address,
                            newGroupModel: newGroupModel,
                            tx: tx
                        )
                    }
                case .invited:
                    addUserWasInvitedToTheGroup(
                        address: address,
                        unnamedInviteCounts: &unnamedInviteCounts,
                        tx: tx
                    )
                case .requesting:
                    addUserRequestedToJoinGroup(address: address, tx: tx)
                case .none:
                    // Membership status didn't change.
                    break
                }
            }
        }

        addUnnamedUsersWereInvited(count: unnamedInviteCounts.newInviteCount)
        addUnnamedUserInvitesWereRevoked(count: unnamedInviteCounts.revokedInviteCount)

        addInvalidInviteUpdates(oldGroupMembership: oldGroupMembership,
                                newGroupMembership: newGroupMembership)
    }

    mutating func addInvalidInviteUpdates(oldGroupMembership: GroupMembership,
                                          newGroupMembership: GroupMembership) {
        let oldInvalidInviteUserIds = Set(oldGroupMembership.invalidInviteUserIds)
        let newInvalidInviteUserIds = Set(newGroupMembership.invalidInviteUserIds)
        let addedInvalidInviteCount = newInvalidInviteUserIds.subtracting(oldInvalidInviteUserIds).count
        let removedInvalidInviteCount = oldInvalidInviteUserIds.subtracting(newInvalidInviteUserIds).count

        if addedInvalidInviteCount > 0 {
            switch updater {
            case .localUser:
                addItem(.invalidInvitesAddedByLocalUser(count: addedInvalidInviteCount))
            case let .otherUser(updaterName, updaterAddress):
                addItem(.invalidInvitesAddedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress,
                    count: addedInvalidInviteCount
                ))
            case .unknown:
                addItem(.invalidInvitesAddedByUnknownUser(count: addedInvalidInviteCount))
            }
        }

        if removedInvalidInviteCount > 0 {
            switch updater {
            case .localUser:
                addItem(.invalidInvitesRemovedByLocalUser(count: removedInvalidInviteCount))
            case let .otherUser(updaterName, updaterAddress):
                addItem(.invalidInvitesRemovedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress,
                    count: removedInvalidInviteCount
                ))
            case .unknown:
                addItem(.invalidInvitesRemovedByUnknownUser(count: removedInvalidInviteCount))
            }
        }
    }

    mutating func addMemberRoleUpdates(
        address: SignalServiceAddress,
        oldGroupMembership: GroupMembership,
        newGroupMembership: GroupMembership,
        newGroupModel: TSGroupModel,
        tx: DBReadTransaction
    ) {

        let oldIsAdministrator = oldGroupMembership.isFullMemberAndAdministrator(address)
        let newIsAdministrator = newGroupMembership.isFullMemberAndAdministrator(address)

        guard oldIsAdministrator != newIsAdministrator else {
            // Role didn't change.
            return
        }

        if newIsAdministrator {
            addUserWasGrantedAdministrator(address: address, newGroupModel: newGroupModel, tx: tx)
        } else {
            addUserWasRevokedAdministrator(address: address, tx: tx)
        }
    }

    mutating func addUserWasGrantedAdministrator(
        address userAddress: SignalServiceAddress,
        newGroupModel: TSGroupModel,
        tx: DBReadTransaction
    ) {

        if let newGroupModelV2 = newGroupModel as? TSGroupModelV2,
           newGroupModelV2.wasJustMigrated {
            // All v1 group members become admins when the
            // group is migrated to v2. We don't need to
            // surface this to the user.
            return
        }

        if isLocalUser(address: userAddress) {
            switch updater {
            case .localUser:
                owsFailDebug("Local user made themselves administrator!")
                addItem(.localUserWasGrantedAdministratorByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserWasGrantedAdministratorByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserWasGrantedAdministratorByUnknownUser)
            }
        } else {
            let userName = self.contactsManager.displayName(address: userAddress, tx: tx)

            switch updater {
            case .localUser:
                addItem(.otherUserWasGrantedAdministratorByLocalUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            case let .otherUser(updaterName, updaterAddress):
                if updaterAddress == userAddress {
                    owsFailDebug("Remote user made themselves administrator!")
                    addItem(.otherUserWasGrantedAdministratorByUnknownUser(
                        userName: userName,
                        userAddress: userAddress
                    ))
                } else {
                    addItem(.otherUserWasGrantedAdministratorByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress,
                        userName: userName,
                        userAddress: userAddress
                    ))
                }
            case .unknown:
                addItem(.otherUserWasGrantedAdministratorByUnknownUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            }
        }
    }

    mutating func addUserWasRevokedAdministrator(
        address userAddress: SignalServiceAddress,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: userAddress) {
            switch updater {
            case .localUser:
                addItem(.localUserWasRevokedAdministratorByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserWasRevokedAdministratorByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserWasRevokedAdministratorByUnknownUser)
            }
        } else {
            let userName = contactsManager.displayName(address: userAddress, tx: tx)

            switch updater {
            case .localUser:
                addItem(.otherUserWasRevokedAdministratorByLocalUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            case let .otherUser(updaterName, updaterAddress):
                if updaterAddress == userAddress {
                    addItem(.otherUserWasRevokedAdministratorByUnknownUser(
                        userName: userName,
                        userAddress: userAddress
                    ))
                } else {
                    addItem(.otherUserWasRevokedAdministratorByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress,
                        userName: userName,
                        userAddress: userAddress
                    ))
                }
            case .unknown:
                addItem(.otherUserWasRevokedAdministratorByUnknownUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            }
        }
    }

    mutating func addUserLeftOrWasKickedOutOfGroup(
        address userAddress: SignalServiceAddress,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: userAddress) {
            switch updater {
            case .localUser:
                addItem(.localUserLeft)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserRemoved(
                    removerName: updaterName,
                    removerAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserRemovedByUnknownUser)
            }
        } else {
            let userName = contactsManager.displayName(address: userAddress, tx: tx)

            switch updater {
            case .localUser:
                addItem(.otherUserRemovedByLocalUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            case let .otherUser(updaterName, updaterAddress):
                if updaterAddress == userAddress {
                    addItem(.otherUserLeft(userName: userName, userAddress: userAddress))
                } else {
                    addItem(.otherUserRemoved(
                        removerName: updaterName,
                        removerAddress: updaterAddress,
                        userName: userName,
                        userAddress: userAddress
                    ))
                }
            case .unknown:
                addItem(.otherUserRemovedByUnknownUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            }
        }
    }

    mutating func addUserLeftOrWasKickedOutOfGroupThenWasInvitedToTheGroup(
        address userAddress: SignalServiceAddress,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: userAddress) {
            addItem(.localUserRemovedByUnknownUser)

            switch updater {
            case .localUser:
                owsFailDebug("User invited themselves to the group!")
                addItem(.localUserWasInvitedByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserWasInvitedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserWasInvitedByUnknownUser)
            }
        } else {
            addItem(.otherUserLeft(
                userName: contactsManager.displayName(address: userAddress, tx: tx),
                userAddress: userAddress
            ))

            switch updater {
            case .localUser:
                addItem(.unnamedUsersWereInvitedByLocalUser(count: 1))
            case let .otherUser(updaterName, updaterAddress):
                addItem(.unnamedUsersWereInvitedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress,
                    count: 1
                ))
            case .unknown:
                addItem(.unnamedUsersWereInvitedByUnknownUser(count: 1))
            }
        }
    }

    mutating func addUserInviteWasAccepted(
        invitedAsAddress: SignalServiceAddress,
        acceptedAsAddress: SignalServiceAddress,
        oldGroupMembership: GroupMembership,
        tx: DBReadTransaction
    ) {
        addItem(Self.userInviteWasAcceptedItem(
            invitedAsAddress: invitedAsAddress,
            acceptedAsAddress: acceptedAsAddress,
            oldGroupMembership: oldGroupMembership,
            updater: updater,
            isLocalUserBlock: { isLocalUser(address: $0) },
            contactsManager: contactsManager,
            tx: tx
        ))
    }

    static func userInviteWasAcceptedItem(
        invitedAsAddress: SignalServiceAddress,
        acceptedAsAddress: SignalServiceAddress,
        oldGroupMembership: GroupMembership?,
        updater: Updater,
        isLocalUserBlock: IsLocalUserBlock,
        contactsManager: Shims.ContactsManager,
        tx: DBReadTransaction
    ) -> DisplayableGroupUpdateItem {
        var inviterName: String?
        var inviterAddress: SignalServiceAddress?

        if let inviterAci = oldGroupMembership?.addedByAci(forInvitedMember: invitedAsAddress) {
            inviterAddress = SignalServiceAddress(inviterAci)
            inviterName = contactsManager.displayName(address: SignalServiceAddress(inviterAci), tx: tx)
        }

        if isLocalUserBlock(acceptedAsAddress) {
            switch updater {
            case .localUser:
                if let inviterName, let inviterAddress {
                    return .localUserAcceptedInviteFromInviter(
                        inviterName: inviterName,
                        inviterAddress: inviterAddress
                    )
                } else {
                    owsFailDebug("Missing inviter name!")
                    return .localUserAcceptedInviteFromUnknownUser
                }
            case let .otherUser(updaterName, updaterAddress):
                return .localUserAddedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                )
            case .unknown:
                return .localUserJoined
            }
        } else {
            let acceptedAsName = contactsManager.displayName(address: acceptedAsAddress, tx: tx)

            switch updater {
            case .localUser:
                return .otherUserAddedByLocalUser(
                    userName: acceptedAsName,
                    userAddress: acceptedAsAddress
                )
            case let .otherUser(updaterName, updaterAddress):
                if invitedAsAddress == updaterAddress || acceptedAsAddress == updaterAddress {
                    // The update came from the person who was invited.

                    if isLocalUserBlock(invitedAsAddress) {
                        return .otherUserAcceptedInviteFromLocalUser(
                            userName: acceptedAsName,
                            userAddress: acceptedAsAddress
                        )
                    } else if let inviterName, let inviterAddress {
                        return .otherUserAcceptedInviteFromInviter(
                            userName: acceptedAsName,
                            userAddress: acceptedAsAddress,
                            inviterName: inviterName,
                            inviterAddress: inviterAddress
                        )
                    } else {
                        owsFailDebug("Missing inviter name.")
                        return .otherUserAcceptedInviteFromUnknownUser(
                            userName: acceptedAsName,
                            userAddress: acceptedAsAddress
                        )
                    }
                } else {
                    return .otherUserAddedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress,
                        userName: acceptedAsName,
                        userAddress: acceptedAsAddress
                    )
                }
            case .unknown:
                return .otherUserJoined(
                    userName: acceptedAsName,
                    userAddress: acceptedAsAddress
                )
            }
        }
    }

    mutating func addUserInviteWasDeclinedOrRevoked(
        inviteeAddress: SignalServiceAddress,
        inviteeKnownToBeLocalUser: Bool,
        oldGroupMembership: GroupMembership,
        unnamedInviteCounts: inout UnnamedInviteCounts,
        tx: DBReadTransaction
    ) {
        Self.userInviteWasDeclinedOrRevokedItem(
            inviteeAddress: inviteeAddress,
            inviteeKnownToBeLocalUser: inviteeKnownToBeLocalUser,
            oldGroupMembership: oldGroupMembership,
            unnamedInviteCounts: &unnamedInviteCounts,
            updater: updater,
            isLocalUserBlock: { isLocalUser(address: $0) },
            contactsManager: contactsManager,
            tx: tx
        ).map {
            addItem($0)
        }
    }

    /// An update item for the fact that the given invited address declined or
    /// had their invite revoked.
    /// - Parameter inviteeKnownToBeLocalUser
    /// Whether we know ahead of time that the invitee was the local user.
    /// - Returns
    /// An update item, if one could be created. If `nil` is returned, inspect
    /// `unnamedInviteCounts` to see if an unnamed invite was affected.
    static func userInviteWasDeclinedOrRevokedItem(
        inviteeAddress: SignalServiceAddress,
        inviteeKnownToBeLocalUser: Bool,
        oldGroupMembership: GroupMembership?,
        unnamedInviteCounts: inout UnnamedInviteCounts,
        updater: Updater,
        isLocalUserBlock: IsLocalUserBlock,
        contactsManager: Shims.ContactsManager,
        tx: DBReadTransaction
    ) -> DisplayableGroupUpdateItem? {
        var inviterName: String?
        var inviterAddress: SignalServiceAddress?
        if let inviterAci = oldGroupMembership?.addedByAci(forInvitedMember: inviteeAddress) {
            inviterAddress = SignalServiceAddress(inviterAci)
            inviterName = contactsManager.displayName(address: SignalServiceAddress(inviterAci), tx: tx)
        }

        if inviteeKnownToBeLocalUser || isLocalUserBlock(inviteeAddress) {
            switch updater {
            case .localUser:
                if let inviterName, let inviterAddress {
                    return .localUserDeclinedInviteFromInviter(
                        inviterName: inviterName,
                        inviterAddress: inviterAddress
                    )
                } else {
                    owsFailDebug("Missing inviter name!")
                    return .localUserDeclinedInviteFromUnknownUser
                }
            case let .otherUser(updaterName, updaterAddress):
                return .localUserInviteRevoked(
                    revokerName: updaterName,
                    revokerAddress: updaterAddress
                )
            case .unknown:
                return .localUserInviteRevokedByUnknownUser
            }
        } else {
            // PNI TODO: If someone declines an invitation we sent to their PNI, or if we revoke their invitation, this won't find their name.
            let inviteeName = contactsManager.displayName(address: inviteeAddress, tx: tx)

            switch updater {
            case .localUser:
                return .otherUserInviteRevokedByLocalUser(
                    userName: inviteeName,
                    userAddress: inviteeAddress
                )
            case .otherUser(_, let updaterAddress):
                if inviteeAddress == updaterAddress {
                    if let inviterAddress, isLocalUserBlock(inviterAddress) {
                        return .otherUserDeclinedInviteFromLocalUser(
                            userName: inviteeName,
                            userAddress: inviteeAddress
                        )
                    } else if let inviterName, let inviterAddress {
                        return .otherUserDeclinedInviteFromInviter(
                            inviterName: inviterName,
                            inviterAddress: inviterAddress
                        )
                    } else {
                        return .otherUserDeclinedInviteFromUnknownUser
                    }
                } else {
                    unnamedInviteCounts.revokedInviteCount += 1
                    return nil
                }
            case .unknown:
                unnamedInviteCounts.revokedInviteCount += 1
                return nil
            }
        }
    }

    mutating func addUserWasAddedToTheGroup(
        address userAddress: SignalServiceAddress,
        newGroupModel: TSGroupModel,
        tx: DBReadTransaction
    ) {
        if newGroupModel.didJustAddSelfViaGroupLinkV2 {
            addItem(.localUserJoined)
        } else if isLocalUser(address: userAddress) {
            switch updater {
            case .localUser:
                owsFailDebug("User added themselves to the group and was updater - should not be possible.")
                addItem(.localUserAddedByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserAddedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserAddedByUnknownUser)
            }
        } else {
            let userName = contactsManager.displayName(address: userAddress, tx: tx)

            switch updater {
            case .localUser:
                addItem(.otherUserAddedByLocalUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            case let .otherUser(updaterName, updaterAddress):
                if updaterAddress == userAddress {
                    owsFailDebug("Remote user added themselves to the group!")

                    addItem(.otherUserAddedByUnknownUser(
                        userName: userName,
                        userAddress: userAddress
                    ))
                } else {
                    addItem(.otherUserAddedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress,
                        userName: userName,
                        userAddress: userAddress
                    ))
                }
            case .unknown:
                addItem(.otherUserAddedByUnknownUser(
                    userName: userName,
                    userAddress: userAddress
                ))
            }
        }
    }

    mutating func addUserJoinedFromInviteLink(
        address: SignalServiceAddress,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: address) {
            switch updater {
            case .localUser:
                addItem(.localUserJoinedViaInviteLink)
            case .otherUser:
                owsFailDebug("A user should never join the group via invite link unless they are the updater.")
                addItem(.localUserJoined)
            case .unknown:
                addItem(.localUserJoined)
            }
        } else {
            let userName = contactsManager.displayName(address: address, tx: tx)

            switch updater {
            case .otherUser(let updaterName, let updaterAddress) where updaterAddress == address:
                addItem(.otherUserJoinedViaInviteLink(
                    userName: updaterName,
                    userAddress: updaterAddress
                ))
            default:
                owsFailDebug("If user joined via group link, they should be the updater!")
                addItem(.otherUserAddedByUnknownUser(
                    userName: userName,
                    userAddress: address
                ))
            }
        }
    }

    mutating func addUserWasInvitedToTheGroup(
        address userAddress: SignalServiceAddress,
        unnamedInviteCounts: inout UnnamedInviteCounts,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: userAddress) {
            switch updater {
            case .localUser:
                owsFailDebug("User invited themselves to the group!")

                addItem(.localUserWasInvitedByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.localUserWasInvitedByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserWasInvitedByUnknownUser)
            }
        } else {
            switch updater {
            case .localUser:
                addItem(.otherUserWasInvitedByLocalUser(
                    userName: contactsManager.displayName(address: userAddress, tx: tx),
                    userAddress: userAddress
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

        switch updater {
        case .localUser:
            owsFailDebug("Unexpected updater - if local user is inviter, should not be unnamed.")
            addItem(.unnamedUsersWereInvitedByLocalUser(count: count))
        case let .otherUser(updaterName, updaterAddress):
            addItem(.unnamedUsersWereInvitedByOtherUser(
                updaterName: updaterName,
                updaterAddress: updaterAddress,
                count: count
            ))
        case .unknown:
            addItem(.unnamedUsersWereInvitedByUnknownUser(count: count))
        }
    }

    mutating func addUnnamedUserInvitesWereRevoked(count: UInt) {
        Self.unnamedUserInvitesWereRevokedItem(
            count: count,
            updater: updater
        ).map {
            addItem($0)
        }
    }

    static func unnamedUserInvitesWereRevokedItem(
        count: UInt,
        updater: Updater
    ) -> DisplayableGroupUpdateItem? {
        guard count > 0 else {
            return nil
        }

        switch updater {
        case .localUser:
            owsFailDebug("When local user is updater, should have named invites!")
            return .unnamedUserInvitesWereRevokedByLocalUser(count: count)
        case let .otherUser(updaterName, updaterAddress):
            return .unnamedUserInvitesWereRevokedByOtherUser(
                updaterName: updaterName,
                updaterAddress: updaterAddress,
                count: count
            )
        case .unknown:
            return .unnamedUserInvitesWereRevokedByUnknownUser(count: count)
        }
    }

    // MARK: Requesting Members

    mutating func addUserRequestedToJoinGroup(
        address requesterAddress: SignalServiceAddress,
        tx: DBReadTransaction
    ) {
        addItem(Self.userRequestedToJoinUpdateItem(
            address: requesterAddress,
            isLocalUserBlock: { isLocalUser(address: $0) },
            contactsManager: contactsManager,
            tx: tx
        ))
    }

    static func userRequestedToJoinUpdateItem(
        address requesterAddress: SignalServiceAddress,
        isLocalUserBlock: IsLocalUserBlock,
        contactsManager: Shims.ContactsManager,
        tx: DBReadTransaction
    ) -> DisplayableGroupUpdateItem {
        if isLocalUserBlock(requesterAddress) {
            return .localUserRequestedToJoin
        } else {
            return .otherUserRequestedToJoin(
                userName: contactsManager.displayName(address: requesterAddress, tx: tx),
                userAddress: requesterAddress
            )
        }
    }

    mutating func addUserRequestWasApproved(
        address requesterAddress: SignalServiceAddress,
        oldGroupMembership: GroupMembership,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: requesterAddress) {
            switch updater {
            case .localUser:
                // This could happen if the user requested to join a group
                // and became a requesting member, then tried to join the
                // group again and was added because the group stopped
                // requiring approval in the interim.
                owsFailDebug("User added themselves to the group and was updater - should not be possible.")
                addItem(.localUserAddedByLocalUser)
            case .otherUser(let updaterName, let updaterAddress):
                addItem(.localUserRequestApproved(
                    approverName: updaterName,
                    approverAddress: updaterAddress
                ))
            case .unknown:
                addItem(.localUserRequestApprovedByUnknownUser)
            }
        } else {
            let requesterName = contactsManager.displayName(address: requesterAddress, tx: tx)

            switch updater {
            case .localUser:
                addItem(.otherUserRequestApprovedByLocalUser(
                    userName: requesterName,
                    userAddress: requesterAddress
                ))
            case .otherUser(let updaterName, let updaterAddress):
                addItem(.otherUserRequestApproved(
                    userName: requesterName,
                    userAddress: requesterAddress,
                    approverName: updaterName,
                    approverAddress: updaterAddress
                ))
            case .unknown:
                addItem(.otherUserRequestApprovedByUnknownUser(
                    userName: requesterName,
                    userAddress: requesterAddress
                ))
            }
        }
    }

    mutating func addUserRequestWasRejected(
        address requesterAddress: SignalServiceAddress,
        tx: DBReadTransaction
    ) {
        if isLocalUser(address: requesterAddress) {
            switch updater {
            case .localUser:
                addItem(.localUserRequestCanceledByLocalUser)
            case .otherUser, .unknown:
                addItem(.localUserRequestRejectedByUnknownUser)
            }
        } else {
            switch updater {
            case .localUser:
                addItem(.otherUserRequestRejectedByLocalUser(
                    requesterName: contactsManager.displayName(address: requesterAddress, tx: tx),
                    requesterAddress: requesterAddress
                ))
            case let .otherUser(updaterName, updaterAddress):
                if updaterAddress == requesterAddress {
                    addItem(.otherUserRequestCanceledByOtherUser(
                        requesterName: contactsManager.displayName(address: requesterAddress, tx: tx),
                        requesterAddress: requesterAddress
                    ))
                } else {
                    addItem(.otherUserRequestRejectedByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress,
                        requesterName: contactsManager.displayName(address: requesterAddress, tx: tx),
                        requesterAddress: requesterAddress
                    ))
                }
            case .unknown:
                addItem(.otherUserRequestRejectedByUnknownUser(
                    requesterName: contactsManager.displayName(address: requesterAddress, tx: tx),
                    requesterAddress: requesterAddress
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
            updater: updater,
            oldToken: oldToken,
            newToken: newToken,
            forceUnknownAttribution: localUserJustJoined
        ).map {
            addItem($0)
        }
    }

    static func disappearingMessageUpdateItem(
        updater: Updater,
        oldToken: DisappearingMessageToken?,
        newToken: DisappearingMessageToken?,
        forceUnknownAttribution: Bool
    ) -> DisplayableGroupUpdateItem? {
        guard let newToken else {
            // This info message was created before we embedded DM state.
            return nil
        }

        // This might be zero if DMs are not enabled.
        let durationMs = UInt64(newToken.durationSeconds) * 1000

        if forceUnknownAttribution, newToken.isEnabled {
            return .disappearingMessagesEnabledByUnknownUser(durationMs: durationMs)
        }

        guard let oldToken else {
            if newToken.isEnabled {
                switch updater {
                case .localUser:
                    return .disappearingMessagesUpdatedNoOldTokenByLocalUser(
                        durationMs: durationMs
                    )
                case .otherUser, .unknown:
                    return .disappearingMessagesUpdatedNoOldTokenByUnknownUser(
                        durationMs: durationMs
                    )
                }
            }

            return nil
        }

        guard newToken != oldToken else {
            // No change to disappearing message configuration occurred.
            return nil
        }

        if newToken.isEnabled {
            switch updater {
            case .localUser:
                return .disappearingMessagesEnabledByLocalUser(durationMs: durationMs)
            case let .otherUser(updaterName, updaterAddress):
                return .disappearingMessagesEnabledByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress,
                    durationMs: durationMs
                )
            case .unknown:
                return .disappearingMessagesEnabledByUnknownUser(durationMs: durationMs)
            }
        } else {
            switch updater {
            case .localUser:
                return .disappearingMessagesDisabledByLocalUser
            case let .otherUser(updaterName, updaterAddress):
                return .disappearingMessagesDisabledByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                )
            case .unknown:
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
                switch updater {
                case .localUser:
                    addItem(.inviteLinkResetByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.inviteLinkResetByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
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
                switch updater {
                case .localUser:
                    addItem(.inviteLinkEnabledWithoutApprovalByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.inviteLinkEnabledWithoutApprovalByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.inviteLinkEnabledWithoutApprovalByUnknownUser)
                }
            case .enabledWithApproval:
                switch updater {
                case .localUser:
                    addItem(.inviteLinkEnabledWithApprovalByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.inviteLinkEnabledWithApprovalByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.inviteLinkEnabledWithApprovalByUnknownUser)
                }
            }
        case .enabledWithoutApproval, .enabledWithApproval:
            switch newGroupInviteLinkMode {
            case .disabled:
                switch updater {
                case .localUser:
                    addItem(.inviteLinkDisabledByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.inviteLinkDisabledByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.inviteLinkDisabledByUnknownUser)
                }
            case .enabledWithoutApproval:
                switch updater {
                case .localUser:
                    addItem(.inviteLinkApprovalDisabledByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.inviteLinkApprovalDisabledByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
                    addItem(.inviteLinkApprovalDisabledByUnknownUser)
                }
            case .enabledWithApproval:
                switch updater {
                case .localUser:
                    addItem(.inviteLinkApprovalEnabledByLocalUser)
                case let .otherUser(updaterName, updaterAddress):
                    addItem(.inviteLinkApprovalEnabledByOtherUser(
                        updaterName: updaterName,
                        updaterAddress: updaterAddress
                    ))
                case .unknown:
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
            switch updater {
            case .localUser:
                addItem(.announcementOnlyEnabledByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.announcementOnlyEnabledByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
                addItem(.announcementOnlyEnabledByUnknownUser)
            }
        } else {
            switch updater {
            case .localUser:
                addItem(.announcementOnlyDisabledByLocalUser)
            case let .otherUser(updaterName, updaterAddress):
                addItem(.announcementOnlyDisabledByOtherUser(
                    updaterName: updaterName,
                    updaterAddress: updaterAddress
                ))
            case .unknown:
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

private struct DefaultGroupUpdateItemBuilder {
    init() {}

    func buildGroupUpdateItem(
        groupUpdateSourceAddress: SignalServiceAddress?,
        localIdentifiers: LocalIdentifiers?,
        contactsManager: Shims.ContactsManager,
        tx: DBReadTransaction
    ) -> DisplayableGroupUpdateItem {
        let updater: Updater = .build(
            localIdentifiers: localIdentifiers,
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            updaterKnownToBeLocalUser: false,
            contactsManager: contactsManager,
            tx: tx
        )

        switch updater {
        case .localUser:
            return .genericUpdateByLocalUser
        case let .otherUser(updaterName, updaterAddress):
            return .genericUpdateByOtherUser(
                updaterName: updaterName,
                updaterAddress: updaterAddress
            )
        case .unknown:
            return .genericUpdateByUnknownUser
        }
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

private typealias Shims = DisplayableGroupUpdateItemBuilderImpl.Shims
private typealias IsLocalUserBlock = (SignalServiceAddress) -> Bool

extension DisplayableGroupUpdateItemBuilderImpl {
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
