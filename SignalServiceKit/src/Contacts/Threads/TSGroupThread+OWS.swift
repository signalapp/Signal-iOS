//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension TSGroupThread {
    var groupMembership: GroupMembership {
        groupModel.groupMembership
    }

    var isLocalUserMemberOfAnyKind: Bool {
        groupMembership.isLocalUserMemberOfAnyKind
    }

    var isLocalUserFullMember: Bool {
        groupMembership.isLocalUserFullMember
    }

    var isLocalUserInvitedMember: Bool {
        groupMembership.isLocalUserInvitedMember
    }

    var isLocalUserRequestingMember: Bool {
        groupMembership.isLocalUserRequestingMember
    }

    var isLocalUserFullOrInvitedMember: Bool {
        groupMembership.isLocalUserFullOrInvitedMember
    }

    var isLocalUserFullMemberAndAdministrator: Bool {
        groupMembership.isLocalUserFullMemberAndAdministrator
    }
}

// MARK: -

@objc
public extension TSThread {
    var isLocalUserFullMemberOfThread: Bool {
        guard let groupThread = self as? TSGroupThread else {
            return true
        }
        return groupThread.groupMembership.isLocalUserFullMember
    }
}
