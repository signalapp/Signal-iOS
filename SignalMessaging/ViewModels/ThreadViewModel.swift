//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
    @objc public let hasPendingMessageRequest: Bool
    @objc public let addedToGroupByName: String?
    @objc public let disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration
    @objc public let groupCallInProgress: Bool

    public var isContactThread: Bool {
        return !isGroupThread
    }

    @objc
    public var isLocalUserFullMemberOfThread: Bool {
        threadRecord.isLocalUserFullMemberOfThread
    }

    @objc public let draftText: String?
    @objc public let lastMessageText: String?
    @objc public let lastMessageForInbox: TSInteraction?

    @objc
    public init(thread: TSThread, transaction: SDSAnyReadTransaction) {
        self.threadRecord = thread
        self.disappearingMessagesConfiguration = thread.disappearingMessagesConfiguration(with: transaction)

        self.isGroupThread = thread.isGroupThread
        self.name = Environment.shared.contactsManager.displayName(for: thread, transaction: transaction)

        self.isMuted = thread.isMuted
        let lastInteraction = thread.lastInteractionForInbox(transaction: transaction)
        self.lastMessageForInbox = lastInteraction

        if let previewable = lastInteraction as? OWSPreviewText {
            self.lastMessageText = previewable.previewText(transaction: transaction)
        } else {
            self.lastMessageText = ""
        }

        self.lastMessageDate = lastInteraction?.receivedAtDate()

        if let contactThread = thread as? TSContactThread {
            self.contactAddress = contactThread.contactAddress
        } else {
            self.contactAddress = nil
        }

        let unreadCount = InteractionFinder(threadUniqueId: thread.uniqueId).unreadCount(transaction: transaction.unwrapGrdbRead)
        self.unreadCount = unreadCount
        self.hasUnreadMessages = thread.isMarkedUnread || unreadCount > 0
        self.hasPendingMessageRequest = thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead)

        if let groupThread = thread as? TSGroupThread, let addedByAddress = groupThread.groupModel.addedByAddress {
            self.addedToGroupByName = Environment.shared.contactsManager.shortDisplayName(for: addedByAddress, transaction: transaction)
        } else {
            self.addedToGroupByName = nil
        }

        if let draftMessageBody = thread.currentDraft(with: transaction) {
            self.draftText = draftMessageBody.plaintextBody(transaction: transaction.unwrapGrdbRead)
        } else {
            self.draftText = nil
        }

        self.groupCallInProgress = GRDBInteractionFinder.unendedCallsForGroupThread(thread, transaction: transaction)
            .filter { $0.joinedMemberAddresses.count > 0 }
            .count > 0
    }

    @objc
    override public func isEqual(_ object: Any?) -> Bool {
        guard let otherThread = object as? ThreadViewModel else {
            return super.isEqual(object)
        }

        return threadRecord.isEqual(otherThread.threadRecord)
    }
}
