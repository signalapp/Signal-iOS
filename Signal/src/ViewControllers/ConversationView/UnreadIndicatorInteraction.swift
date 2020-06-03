//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSUnreadIndicatorInteraction)
public class UnreadIndicatorInteraction: TSInteraction {

    @objc
    public static let UnreadIndicatorInteractionId = "UnreadIndicatorInteractionId"

    @objc
    public override func isDynamicInteraction() -> Bool {
        return true
    }

    @objc
    public override func interactionType() -> OWSInteractionType {
        return .unreadIndicator
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

    public let shouldShowDate: Bool

    @objc
    public init(thread: TSThread, timestamp: UInt64, receivedAtTimestamp: UInt64, shouldShowDate: Bool) {
        self.shouldShowDate = shouldShowDate
        super.init(uniqueId: UnreadIndicatorInteraction.UnreadIndicatorInteractionId,
                   timestamp: timestamp,
                   receivedAtTimestamp: receivedAtTimestamp,
                   thread: thread)
    }

    public override var shouldBeSaved: Bool {
        return false
    }

    @objc
    public override func anyWillInsert(with transaction: SDSAnyWriteTransaction) {
        owsFailDebug("The transient interaction should not be saved in the database.")
    }
}
