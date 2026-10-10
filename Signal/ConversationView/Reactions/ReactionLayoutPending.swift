//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// UI-only flags for reaction height reflow + entrance/exit. Not protocol/DB state.
enum ReactionLayoutPending {
    static let localEntrances = AtomicSet<String>(lock: .init())
    static let exits = AtomicSet<String>(lock: .init())
    static let remoteEntrances = AtomicSet<String>(lock: .init())

    static func hasPending(for messageId: String) -> Bool {
        localEntrances.contains(messageId)
            || exits.contains(messageId)
            || remoteEntrances.contains(messageId)
    }

    static func markLocal(messageId: String, isRemoving: Bool) {
        if isRemoving {
            exits.insert(messageId)
            localEntrances.remove(messageId)
            remoteEntrances.remove(messageId)
        } else {
            localEntrances.insert(messageId)
            exits.remove(messageId)
            remoteEntrances.remove(messageId)
        }
    }
}
