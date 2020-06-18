//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class NewGroupState {

    var groupSeed = NewGroupSeed()

    var recipientSet = OrderedSet<PickedRecipient>()

    var groupName: String?

    var avatarData: Data?

    func deriveNewGroupSeedForRetry() {
        groupSeed = groupSeed.deriveNewGroupSeedForRetry
    }

    var hasUnsavedChanges: Bool {
        return !recipientSet.isEmpty && groupName == nil && avatarData == nil
    }
}
