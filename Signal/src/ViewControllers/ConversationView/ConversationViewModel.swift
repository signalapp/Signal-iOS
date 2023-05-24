//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ConversationViewModel {
    let groupCallInProgress: Bool

    static func load(for thread: TSThread, tx: SDSAnyReadTransaction) -> ConversationViewModel {
        let groupCallInProgress = GRDBInteractionFinder.unendedCallsForGroupThread(thread, transaction: tx)
            .filter { $0.joinedMemberAddresses.count > 0 }
            .count > 0

        return ConversationViewModel(
            groupCallInProgress: groupCallInProgress
        )
    }

    init(groupCallInProgress: Bool) {
        self.groupCallInProgress = groupCallInProgress
    }
}
