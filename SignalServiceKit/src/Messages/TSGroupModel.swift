//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension TSGroupModel {
    var allPendingMembers: Set<SignalServiceAddress> {
        guard let groupsV2PendingMemberRoles = self.groupsV2PendingMemberRoles else {
            return Set()
        }
        return Set(groupsV2PendingMemberRoles.keys.map {
            SignalServiceAddress(uuid: $0)
        })
    }
}

// MARK: -

public extension TSGroupModel {
    var groupMembership: GroupMembership {
        var nonAdminMembers = Set<SignalServiceAddress>()
        var administrators = Set<SignalServiceAddress>()
        for member in groupMembers {
            switch role(forGroupsV2Member: member) {
            case .administrator:
                administrators.insert(member)
            default:
                nonAdminMembers.insert(member)
            }
        }

        var pendingNonAdminMembers = Set<SignalServiceAddress>()
        var pendingAdministrators = Set<SignalServiceAddress>()
        for member in allPendingMembers {
            switch self.role(forGroupsV2PendingMember: member) {
            case .administrator:
                pendingAdministrators.insert(member)
            default:
                pendingNonAdminMembers.insert(member)
            }
        }

        return GroupMembership(nonAdminMembers: nonAdminMembers,
                               administrators: administrators,
                               pendingNonAdminMembers: pendingNonAdminMembers,
                               pendingAdministrators: pendingAdministrators)
    }
}
