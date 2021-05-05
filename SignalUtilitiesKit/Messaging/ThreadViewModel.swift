//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ThreadViewModel: NSObject {
    @objc public let hasUnreadMessages: Bool
    @objc public let lastMessageDate: Date
    @objc public let isGroupThread: Bool
    @objc public let threadRecord: TSThread
    @objc public let unreadCount: UInt
    @objc public let contactSessionID: String?
    @objc public let name: String
    @objc public let isMuted: Bool

    var isContactThread: Bool {
        return !isGroupThread
    }

    @objc public let lastMessageText: String?
    @objc public let lastMessageForInbox: TSInteraction?

    @objc
    public init(thread: TSThread, transaction: YapDatabaseReadTransaction) {
        self.threadRecord = thread

        self.isGroupThread = thread.isGroupThread()
        self.name = thread.name()
        self.isMuted = thread.isMuted
        self.lastMessageText = thread.lastMessageText(transaction: transaction)
        let lastInteraction = thread.lastInteractionForInbox(transaction: transaction)
        self.lastMessageForInbox = lastInteraction
        self.lastMessageDate = lastInteraction?.dateForUI() ?? thread.creationDate

        if let contactThread = thread as? TSContactThread {
            self.contactSessionID = contactThread.contactSessionID()
        } else {
            self.contactSessionID = nil
        }

        self.unreadCount = thread.unreadMessageCount(transaction: transaction)
        self.hasUnreadMessages = unreadCount > 0
    }

    @objc
    override public func isEqual(_ object: Any?) -> Bool {
        guard let otherThread = object as? ThreadViewModel else {
            return super.isEqual(object)
        }

        return threadRecord.isEqual(otherThread.threadRecord)
    }
}
