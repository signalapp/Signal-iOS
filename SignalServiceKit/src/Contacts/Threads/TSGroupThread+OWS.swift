//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension TSGroupThread {
    var isLocalUserInGroup: Bool {
        guard let localAddress = TSAccountManager.localAddress else {
            return false
        }
        return groupModel.groupMembership.isNonPendingMember(localAddress)
    }

    var isLocalUserPendingOrNonPendingMember: Bool {
        guard let localAddress = TSAccountManager.localAddress else {
            return false
        }
        return groupModel.groupMembership.isPendingOrNonPendingMember(localAddress)
    }

    var isLocalUserPendingMember: Bool {
        guard let localAddress = TSAccountManager.localAddress else {
            return false
        }
        return groupModel.groupMembership.isPending(localAddress)
    }
}
