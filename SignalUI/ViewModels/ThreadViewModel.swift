//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public class ThreadViewModel: NSObject {
    public let hasUnreadMessages: Bool
    public let isGroupThread: Bool
    public let threadRecord: TSThread
    public let unreadCount: UInt
    public let contactAddress: SignalServiceAddress?
    public let name: String
    public let shortName: String?
    public let associatedData: ThreadAssociatedData
    public let hasPendingMessageRequest: Bool
    public let disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration
    public let groupCallInProgress: Bool
    public let hasWallpaper: Bool
    public let isWallpaperPhoto: Bool
    public let isBlocked: Bool

    public var isArchived: Bool { associatedData.isArchived }
    public var isMuted: Bool { associatedData.isMuted }
    public var mutedUntilTimestamp: UInt64 { associatedData.mutedUntilTimestamp }
    public var mutedUntilDate: Date? { associatedData.mutedUntilDate }
    public var isMarkedUnread: Bool { associatedData.isMarkedUnread }

    public let chatColor: ChatColor

    public var isContactThread: Bool {
        return !isGroupThread
    }

    public var isLocalUserFullMemberOfThread: Bool {
        threadRecord.isLocalUserFullMemberOfThread
    }

    public let lastMessageForInbox: TSInteraction?

    // This property is only populated if forChatList is true.
    public let chatListInfo: ChatListInfo?

    public init(thread: TSThread, forChatList: Bool, transaction: SDSAnyReadTransaction) {
        self.threadRecord = thread
        self.disappearingMessagesConfiguration = thread.disappearingMessagesConfiguration(with: transaction)

        self.isGroupThread = thread.isGroupThread
        self.name = Self.contactsManager.displayName(for: thread, transaction: transaction)

        let associatedData = ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction)
        self.associatedData = associatedData

        self.chatColor = ChatColors.chatColorForRendering(thread: thread, transaction: transaction)

        if let contactThread = thread as? TSContactThread {
            self.contactAddress = contactThread.contactAddress
            self.shortName = Self.contactsManager.shortDisplayName(
                for: contactThread.contactAddress,
                transaction: transaction
            )
        } else {
            self.contactAddress = nil
            self.shortName = nil
        }

        let unreadCount = InteractionFinder(threadUniqueId: thread.uniqueId).unreadCount(transaction: transaction.unwrapGrdbRead)
        self.unreadCount = unreadCount
        self.hasUnreadMessages = associatedData.isMarkedUnread || unreadCount > 0
        self.hasPendingMessageRequest = thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead)

        self.groupCallInProgress = GRDBInteractionFinder.unendedCallsForGroupThread(thread, transaction: transaction)
            .filter { $0.joinedMemberAddresses.count > 0 }
            .count > 0

        self.lastMessageForInbox = thread.lastInteractionForInbox(transaction: transaction)

        if forChatList {
            chatListInfo = ChatListInfo(thread: thread,
                                        lastMessageForInbox: lastMessageForInbox,
                                        hasPendingMessageRequest: hasPendingMessageRequest,
                                        transaction: transaction)
        } else {
            chatListInfo = nil
        }

        if let wallpaper = Wallpaper.wallpaperForRendering(for: thread, transaction: transaction) {
            self.hasWallpaper = true
            if case .photo = wallpaper {
                self.isWallpaperPhoto = true
            } else {
                self.isWallpaperPhoto = false
            }
        } else {
            self.hasWallpaper = false
            self.isWallpaperPhoto = false
        }

        isBlocked = Self.blockingManager.isThreadBlocked(thread, transaction: transaction)
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

public class ChatListInfo: Dependencies {

    public let lastMessageDate: Date?
    public let snippet: CLVSnippet

    public init(thread: TSThread,
                lastMessageForInbox: TSInteraction?,
                hasPendingMessageRequest: Bool,
                transaction: SDSAnyReadTransaction) {

        self.lastMessageDate = lastMessageForInbox?.timestampDate

        self.snippet = Self.buildCLVSnippet(thread: thread,
                                           hasPendingMessageRequest: hasPendingMessageRequest,
                                           lastMessageForInbox: lastMessageForInbox,
                                           transaction: transaction)
    }

    private static func buildCLVSnippet(
        thread: TSThread,
        hasPendingMessageRequest: Bool,
        lastMessageForInbox: TSInteraction?,
        transaction: SDSAnyReadTransaction
    ) -> CLVSnippet {

        let isBlocked = blockingManager.isThreadBlocked(thread, transaction: transaction)

        func loadDraftText() -> HydratedMessageBody? {
            guard let draftMessageBody = thread.currentDraft(shouldFetchLatest: false,
                                                             transaction: transaction) else {
                return nil
            }
            return draftMessageBody
                .hydrating(
                    mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: transaction.asV2Read)
                )
        }
        func hasVoiceMemoDraft() -> Bool {
            VoiceMessageInterruptedDraftStore.hasDraft(for: thread, transaction: transaction)
        }
        func loadLastMessageText() -> HydratedMessageBody? {
            if let previewable = lastMessageForInbox as? OWSPreviewText {
                return HydratedMessageBody.fromPlaintextWithoutRanges(
                    previewable.previewText(transaction: transaction).filterStringForDisplay()
                )
            } else if let tsMessage = lastMessageForInbox as? TSMessage {
                return tsMessage.conversationListPreviewText(transaction)
            } else {
                return nil
            }
        }
        func loadLastMessageSenderName() -> String? {
            guard let groupThread = thread as? TSGroupThread else {
                return nil
            }
            if let incomingMessage = lastMessageForInbox as? TSIncomingMessage {
                return Self.contactsManagerImpl.shortestDisplayName(
                    forGroupMember: incomingMessage.authorAddress,
                    inGroup: groupThread.groupModel,
                    transaction: transaction
                )
            } else if lastMessageForInbox is TSOutgoingMessage {
                return CommonStrings.you
            } else {
                return nil
            }
        }
        func loadAddedToGroupByName() -> String? {
            guard let groupThread = thread as? TSGroupThread,
                  let addedByAddress = groupThread.groupModel.addedByAddress else {
                return nil
            }
            return Self.contactsManager.shortDisplayName(for: addedByAddress, transaction: transaction)
        }

        if isBlocked {
            return .blocked
        } else if hasPendingMessageRequest {
            return .pendingMessageRequest(addedToGroupByName: loadAddedToGroupByName())
        } else if let draftText = loadDraftText()?.nilIfEmpty {
            return .draft(draftText: draftText)
        } else if hasVoiceMemoDraft() {
            return .voiceMemoDraft
        } else if let lastMessageText = loadLastMessageText()?.nilIfEmpty {
            if let senderName = loadLastMessageSenderName()?.nilIfEmpty {
                return .groupSnippet(lastMessageText: lastMessageText, senderName: senderName)
            } else {
                return .contactSnippet(lastMessageText: lastMessageText)
            }
        } else {
            return .none
        }
    }
}

// MARK: -

public enum CLVSnippet {
    case blocked
    case pendingMessageRequest(addedToGroupByName: String?)
    case draft(draftText: HydratedMessageBody)
    case voiceMemoDraft
    case contactSnippet(lastMessageText: HydratedMessageBody)
    case groupSnippet(lastMessageText: HydratedMessageBody, senderName: String)
    case none
}
