//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

extension ConversationViewController {
    func didTapSystemMessageItem(_ item: CVTextLabel.Item) {
        AssertIsOnMainThread()

        guard case .referencedUser(let referencedUserItem) = item else {
            owsFailDebug("Should only have referenced user items in system messages, but tapped \(item.description)")
            return
        }

        let address = referencedUserItem.address

        owsAssertDebug(
            !address.isLocalAddress,
            "We should never have ourselves as a referenced user in a system message"
        )

        showMemberActionSheet(forAddress: address, withHapticFeedback: true)
    }
}
