//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public class TypingIndicatorInteraction: TSInteraction {
    public static let TypingIndicatorId = "TypingIndicator"

    override public var isDynamicInteraction: Bool {
        true
    }

    override public var interactionType: OWSInteractionType {
        .typingIndicator
    }

    @available(*, unavailable, message: "use other constructor instead.")
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public let address: SignalServiceAddress

    public init(thread: TSThread, timestamp: UInt64, address: SignalServiceAddress) {
        self.address = address

        super.init(
            customUniqueId: TypingIndicatorInteraction.TypingIndicatorId,
            timestamp: timestamp,
            receivedAtTimestamp: 0,
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
