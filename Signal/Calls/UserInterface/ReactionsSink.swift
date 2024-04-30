//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

class ReactionsSink {
    private let reactionReceivers: [ReactionReceiver]

    init(reactionReceivers: [ReactionReceiver]) {
        self.reactionReceivers = reactionReceivers
    }

    func addReactions(reactions: [Reaction]) {
        self.reactionReceivers.forEach { receiver in
            receiver.addReactions(reactions: reactions)
        }
    }
}

// MARK: ReactionReceiver

protocol ReactionReceiver: AnyObject {
    func addReactions(reactions: [Reaction])
}
