//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ThreadViewModel: NSObject {
    let hasUnreadMessages: Bool
    let lastMessageDate: Date
    let isGroupThread: Bool
    let threadRecord: TSThread
    let unreadCount: UInt
    let contactIdentifier: String?
    let name: String
    let isMuted: Bool
    var isContactThread: Bool {
        return !isGroupThread
    }

    let lastMessageText: String?

    init(thread: TSThread, transaction: YapDatabaseReadTransaction) {
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
