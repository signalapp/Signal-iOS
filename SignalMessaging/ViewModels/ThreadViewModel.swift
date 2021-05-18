//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ThreadViewModel: NSObject {
    @objc public let hasUnreadMessages: Bool
    @objc public let isGroupThread: Bool
    @objc public let threadRecord: TSThread
    @objc public let unreadCount: UInt
    @objc public let contactAddress: SignalServiceAddress?
    @objc public let name: String
    @objc public let associatedData: ThreadAssociatedData
    @objc public let hasPendingMessageRequest: Bool
    @objc public let disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration
    @objc public let groupCallInProgress: Bool
    @objc public let hasWallpaper: Bool

    @objc
    public var isArchived: Bool { associatedData.isArchived }

    @objc
    public var isMuted: Bool { associatedData.isMuted }

    @objc
    public var mutedUntilTimestamp: UInt64 { associatedData.mutedUntilTimestamp }

    @objc
    public var mutedUntilDate: Date? { associatedData.mutedUntilDate }

    @objc
    public var isMarkedUnread: Bool { associatedData.isMarkedUnread }

    public let chatColor: ChatColor

    public var isContactThread: Bool {
        return !isGroupThread
    }

    @objc
    public var isLocalUserFullMemberOfThread: Bool {
        threadRecord.isLocalUserFullMemberOfThread
    }

    @objc
    public let lastMessageForInbox: TSInteraction?

    // This property is only set if forConversationList is true.
    @objc
    public let conversationListInfo: ConversationListInfo?

    @objc
    public init(thread: TSThread, forConversationList: Bool, transaction: SDSAnyReadTransaction) {
        self.threadRecord = thread
        self.disappearingMessagesConfiguration = thread.disappearingMessagesConfiguration(with: transaction)

        self.isGroupThread = thread.isGroupThread
        self.name = Self.contactsManager.displayName(for: thread, transaction: transaction)

        let associatedData = ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction)
        self.associatedData = associatedData

        self.chatColor = ChatColors.chatColorForRendering(thread: thread, transaction: transaction)

        if let contactThread = thread as? TSContactThread {
            self.contactAddress = contactThread.contactAddress
        } else {
            self.contactAddress = nil
        }

        let unreadCount = InteractionFinder(threadUniqueId: thread.uniqueId).unreadCount(transaction: transaction.unwrapGrdbRead)
        self.unreadCount = unreadCount
        self.hasUnreadMessages = associatedData.isMarkedUnread || unreadCount > 0
        self.hasPendingMessageRequest = thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead)

        self.groupCallInProgress = GRDBInteractionFinder.unendedCallsForGroupThread(thread, transaction: transaction)
            .filter { $0.joinedMemberAddresses.count > 0 }
            .count > 0

        self.lastMessageForInbox = thread.lastInteractionForInbox(transaction: transaction)

        if forConversationList {
            conversationListInfo = ConversationListInfo(thread: thread,
                                                        lastMessageForInbox: lastMessageForInbox,
                                                        transaction: transaction)
        } else {
            conversationListInfo = nil
        }

        self.hasWallpaper = Wallpaper.exists(for: thread, transaction: transaction)
    }

    @objc
    override public func isEqual(_ object: Any?) -> Bool {
        guard let otherThread = object as? ThreadViewModel else {
            return super.isEqual(object)
        }

        return threadRecord.isEqual(otherThread.threadRecord)
    }
}

// MARK: -

@objc
public class ConversationListInfo: NSObject {

    @objc
    public let draftText: String?
    @objc
    public let hasVoiceMemoDraft: Bool
    @objc
    public let lastMessageText: String
    @objc
    public let lastMessageDate: Date?
    @objc
    public let lastMessageSenderName: String?
    @objc
    public let addedToGroupByName: String?

    @objc
    public init(thread: TSThread,
                lastMessageForInbox: TSInteraction?,
                transaction: SDSAnyReadTransaction) {

        if let previewable = lastMessageForInbox as? OWSPreviewText {
            self.lastMessageText = previewable.previewText(transaction: transaction).filterStringForDisplay()
        } else {
            self.lastMessageText = ""
        }

        self.lastMessageDate = lastMessageForInbox?.receivedAtDate()

        if let draftMessageBody = thread.currentDraft(with: transaction) {
            self.draftText = draftMessageBody.plaintextBody(transaction: transaction.unwrapGrdbRead)
        } else {
            self.draftText = nil
        }

        self.hasVoiceMemoDraft = VoiceMessageModel.hasDraft(for: thread, transaction: transaction)

        if let groupThread = thread as? TSGroupThread, let addedByAddress = groupThread.groupModel.addedByAddress {
            self.addedToGroupByName = Self.contactsManager.shortDisplayName(for: addedByAddress, transaction: transaction)
        } else {
            self.addedToGroupByName = nil
        }
        var lastMessageSenderName: String?
        if !lastMessageText.isEmpty,
           let groupThread = thread as? TSGroupThread {
            if let incomingMessage = lastMessageForInbox as? TSIncomingMessage {
                lastMessageSenderName = Self.contactsManagerImpl.shortestDisplayName(
                    forGroupMember: incomingMessage.authorAddress,
                    inGroup: groupThread.groupModel,
                    transaction: transaction
                )
            } else if lastMessageForInbox is TSOutgoingMessage {
                lastMessageSenderName = NSLocalizedString("GROUP_MEMBER_LOCAL_USER",
                                                          comment: "Label indicating the local user.")
            }
        }
        self.lastMessageSenderName = lastMessageSenderName
    }
}
