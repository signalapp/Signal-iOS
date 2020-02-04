//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension TSGroupModel {
    // GroupsV2 TODO: Remove?
    var pendingMembers: Set<SignalServiceAddress> {
        return groupMembership.pendingMembers
    }

    // GroupsV2 TODO: Remove?
    var allPendingAndNonPendingMembers: Set<SignalServiceAddress> {
        return groupMembership.allUsers
    }
}
