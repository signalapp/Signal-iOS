//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ThreadViewModel: NSObject {
    @objc public let hasUnreadMessages: Bool
    @objc public let lastMessageDate: Date?
    @objc public let isGroupThread: Bool
    @objc public let threadRecord: TSThread
    @objc public let unreadCount: UInt
    @objc public let contactAddress: SignalServiceAddress?
    @objc public let name: String
    @objc public let isMuted: Bool

    var isContactThread: Bool {
        return !isGroupThread
    }

    @objc public let lastMessageText: String?
    @objc public let lastMessageForInbox: TSInteraction?

    @objc
    public init(thread: TSThread, transaction: SDSAnyReadTransaction) {
        self.threadRecord = thread

        self.isGroupThread = thread.isGroupThread()
        self.name = thread.name()
        self.isMuted = thread.isMuted
        self.lastMessageText = thread.lastMessageText(transaction: transaction)
        let lastInteraction = thread.lastInteractionForInbox(transaction: transaction)
        self.lastMessageForInbox = lastInteraction
        self.lastMessageDate = lastInteraction?.receivedAtDate()

        if let contactThread = thread as? TSContactThread {
            self.contactAddress = contactThread.contactAddress
        } else {
            self.contactAddress = nil
        }

        if let threadUniqueId = thread.uniqueId,
            let unreadCount = try? InteractionFinder(threadUniqueId: threadUniqueId).unreadCount(transaction: transaction) {
            self.unreadCount = unreadCount
        } else {
            owsFailDebug("unreadCount was unexpectedly nil")
            self.unreadCount = 0
        }
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
