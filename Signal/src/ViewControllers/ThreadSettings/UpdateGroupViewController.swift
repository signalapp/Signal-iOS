//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension UpdateGroupViewController {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    func updateGroupThread(oldGroupModel: TSGroupModel,
                           newTitle: String?,
                           newAvatarData: Data?,
                           v1Members: Set<SignalServiceAddress>,
                           success: @escaping (TSGroupThread) -> Void,
                           failure: @escaping (Error) -> Void) {

        let groupId = oldGroupModel.groupId
        // GroupsV2 TODO: handle membership, access, etc. in this view.
        let groupMembership: GroupMembership
        switch oldGroupModel.groupsVersion {
        case .V1:
            groupMembership = GroupMembership(v1Members: v1Members)
        case .V2:
            // GroupsV2 TODO: This is a temporary implementation until we
            // rewrite groups v2 to be aware of roles.  For now, new users
            // will _not_ be added as administrators.
            let oldGroupMembership = oldGroupModel.groupMembership
            var groupMembershipBuilder = oldGroupMembership.asBuilder
            databaseStorage.read { transaction in
                for address in v1Members {
                    guard GroupManager.doesUserSupportGroupsV2(address: address, transaction: transaction) else {
                        owsFailDebug("Invalid address: \(address)")
                        continue
                    }
                    if !oldGroupMembership.allUsers.contains(address) {
                        groupMembershipBuilder.addNonPendingMember(address, role: .normal)
                    }
                }
            }
            // GroupsV2 TODO: Remove members, change roles, etc. when
            // UI supports pending members, kicking members, etc..
            groupMembership = groupMembershipBuilder.build()
        }

        let groupAccess = GroupAccess.forV1
        let groupsVersion = oldGroupModel.groupsVersion

        guard let localAddress = tsAccountManager.localAddress else {
            return failure(OWSAssertionError("Missing localAddress."))
        }

        // GroupsV2 TODO: Skip change where the user didn't change anything.

        // dmConfiguration: nil means don't change disappearing messages configuration.
        GroupManager.updateExistingGroup(groupId: groupId,
                                         name: newTitle,
                                         avatarData: newAvatarData,
                                         groupMembership: groupMembership,
                                         groupAccess: groupAccess,
                                         groupsVersion: groupsVersion,
                                         dmConfiguration: nil,
                                         groupUpdateSourceAddress: localAddress)
        .done(on: .global()) { groupThread in
            success(groupThread)
        }.catch(on: .global()) { (error) in
            switch error {
            case GroupsV2Error.redundantChange:
                // GroupsV2 TODO: Treat this as a success.

                owsFailDebug("Could not update group: \(error)")

                failure(error)
            default:
                owsFailDebug("Could not update group: \(error)")

                failure(error)
            }
        }.retainUntilComplete()
    }
}
