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
    @objc public let contactIdentifier: String?
    @objc public let name: String
    @objc public let isMuted: Bool
    var isContactThread: Bool {
        return !isGroupThread
    }

    @objc public let lastMessageText: String?

    @objc
    public init(thread: TSThread, transaction: YapDatabaseReadTransaction) {
        self.threadRecord = thread
        self.lastMessageDate = thread.lastMessageDate()
        self.isGroupThread = thread.isGroupThread()
        self.name = thread.name()
        self.isMuted = thread.isMuted
        self.lastMessageText = thread.lastMessageText(transaction: transaction)

        if let contactThread = thread as? TSContactThread {
            self.contactIdentifier = contactThread.contactIdentifier()
        } else {
            self.contactIdentifier = nil
        }

        self.unreadCount = thread.unreadMessageCount(transaction: transaction)
        self.hasUnreadMessages = unreadCount > 0
    }
}
