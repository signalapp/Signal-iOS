//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSThreadDetailsInteraction)
public class ThreadDetailsInteraction: TSInteraction {
    @objc
    public static let ThreadDetailsId = "ThreadDetails"

    @objc
    public override func isDynamicInteraction() -> Bool {
        return true
    }

    @objc
    public override func interactionType() -> OWSInteractionType {
        return .threadDetails
    }

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        notImplemented()
    }

    @objc public let thread: TSThread

    @objc
    public init(thread: TSThread, timestamp: UInt64) {
        // We keep the thread in memory here so we don't have to query it later
        self.thread = thread
        super.init(uniqueId: ThreadDetailsInteraction.ThreadDetailsId, timestamp: timestamp, in: thread)
    }

    public override var shouldBeSaved: Bool {
        return false
    }

    @objc
    public override func anyWillInsert(with transaction: SDSAnyWriteTransaction) {
        owsFailDebug("The transient interaction should not be saved in the database.")
    }
}
