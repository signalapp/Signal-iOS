//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSTypingIndicatorInteraction)
public class TypingIndicatorInteraction: TSInteraction {
    @objc
    public static let TypingIndicatorId = "TypingIndicator"

    @objc
    public override func isDynamicInteraction() -> Bool {
        return true
    }

    @objc
    public override func interactionType() -> OWSInteractionType {
        return .typingIndicator
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

    @objc
    public let address: SignalServiceAddress

    @objc
    public init(thread: TSThread, timestamp: UInt64, address: SignalServiceAddress) {
        self.address = address

        super.init(uniqueId: TypingIndicatorInteraction.TypingIndicatorId,
            timestamp: timestamp, thread: thread)
    }

    public override var shouldBeSaved: Bool {
        return false
    }

    @objc
    public override func anyWillInsert(with transaction: SDSAnyWriteTransaction) {
        owsFailDebug("The transient interaction should not be saved in the database.")
    }
}
