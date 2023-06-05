//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

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
