//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSThreadDetailsInteraction)
public class ThreadDetailsInteraction: TSInteraction {

    public override var isDynamicInteraction: Bool {
        true
    }

    public override var interactionType: OWSInteractionType {
        .threadDetails
    }

    @available(*, unavailable, message: "use other constructor instead.")
    public required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable, message: "use other constructor instead.")
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        fatalError("init(dictionary:) has not been implemented")
    }

    public init(thread: TSThread, timestamp: UInt64) {
        // Include timestamp in uniqueId to ensure invariant that
        // interactions don't move in the chat history ordering.
        super.init(uniqueId: "ThreadDetails_\(timestamp)",
                   timestamp: timestamp,
                   thread: thread)
    }

    public override var shouldBeSaved: Bool {
        return false
    }

    public override func anyWillInsert(with transaction: SDSAnyWriteTransaction) {
        owsFailDebug("The transient interaction should not be saved in the database.")
    }
}
