//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public class UnreadIndicatorInteraction: TSInteraction {

    override public var isDynamicInteraction: Bool {
        true
    }

    override public var interactionType: OWSInteractionType {
        .unreadIndicator
    }

    @available(*, unavailable, message: "use other constructor instead.")
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public init(thread: TSThread, timestamp: UInt64, receivedAtTimestamp: UInt64) {
        // Include timestamp in uniqueId to ensure invariant that
        // interactions don't move in the chat history ordering.
        super.init(
            customUniqueId: "UnreadIndicator_\(timestamp)",
            timestamp: timestamp,
            receivedAtTimestamp: receivedAtTimestamp,
            thread: thread,
        )
    }

    override public var shouldBeSaved: Bool {
        return false
    }

    override public func anyWillInsert(with transaction: DBWriteTransaction) {
        owsFailDebug("The transient interaction should not be saved in the database.")
    }
}
