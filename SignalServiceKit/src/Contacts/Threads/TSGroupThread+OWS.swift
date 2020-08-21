//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension TSGroupThread {
    var isLocalUserMemberOfAnyKind: Bool {
        guard let localAddress = TSAccountManager.localAddress else {
            return false
        }
        return groupModel.groupMembership.isMemberOfAnyKind(localAddress)
    }

    var isLocalUserFullMemberOfGroup: Bool {
        guard let localAddress = TSAccountManager.localAddress else {
            return false
        }
        return groupModel.groupMembership.isFullMember(localAddress)
    }

    var isLocalUserInvitedMember: Bool {
        guard let localAddress = TSAccountManager.localAddress else {
            return false
        }
        return groupModel.groupMembership.isInvitedMember(localAddress)
    }

    var isLocalUserRequestingMember: Bool {
        guard let localAddress = TSAccountManager.localAddress else {
            return false
        }
        return groupModel.groupMembership.isRequestingMember(localAddress)
    }

    var isLocalUserFullOrInvitedMemberOfGroup: Bool {
        guard let localAddress = TSAccountManager.localAddress else {
            return false
        }
        return (groupModel.groupMembership.isFullMember(localAddress) ||
            groupModel.groupMembership.isInvitedMember(localAddress))
    }
}
