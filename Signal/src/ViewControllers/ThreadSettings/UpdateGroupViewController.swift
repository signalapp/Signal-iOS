//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension UpdateGroupViewController {

    // MARK: - Dependencies

    private static var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
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
            for address in v1Members {
                if !oldGroupMembership.allUsers.contains(address) {
                    groupMembershipBuilder.add(address, isAdministrator: false, isPending: false)
                }
            }
            for address in oldGroupMembership.allUsers {
                if !v1Members.contains(address) {
                    groupMembershipBuilder.remove(address)
                }
            }
            groupMembership = groupMembershipBuilder.build()
        }

        let groupAccess = GroupAccess.forV1

        guard let localAddress = UpdateGroupViewController.tsAccountManager.localAddress else {
            return failure(OWSAssertionError("Missing localAddress."))
        }

        GroupManager.updateExistingGroup(groupId: groupId,
                                         name: newTitle,
                                         avatarData: newAvatarData,
                                         groupMembership: groupMembership,
                                         groupAccess: groupAccess,
                                         shouldSendMessage: true,
                                         groupUpdateSourceAddress: localAddress)
        .done(on: .global()) { groupThread in
            success(groupThread)
        }.catch(on: .global()) { (error) in
            owsFailDebug("Could not update group: \(error)")

            failure(error)
        }.retainUntilComplete()
    }
}
