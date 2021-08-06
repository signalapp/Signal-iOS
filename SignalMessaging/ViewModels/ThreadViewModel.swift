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

    // This property is only populated if forHomeView is true.
    public let homeViewInfo: HomeViewInfo?

    @objc
    public init(thread: TSThread, forHomeView: Bool, transaction: SDSAnyReadTransaction) {
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

        if forHomeView {
            homeViewInfo = HomeViewInfo(thread: thread,
                                        lastMessageForInbox: lastMessageForInbox,
                                        hasPendingMessageRequest: hasPendingMessageRequest,
                                        transaction: transaction)
        } else {
            homeViewInfo = nil
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

public class HomeViewInfo: Dependencies {

    public let lastMessageDate: Date?
    public let isBlocked: Bool
    public let snippet: HVSnippet

    @objc
    public init(thread: TSThread,
                lastMessageForInbox: TSInteraction?,
                hasPendingMessageRequest: Bool,
                transaction: SDSAnyReadTransaction) {

        self.isBlocked = Self.blockingManager.isThreadBlocked(thread)

        self.lastMessageDate = lastMessageForInbox?.timestampDate()

        self.snippet = Self.buildHVSnippet(thread: thread,
                                           isBlocked: isBlocked,
                                           hasPendingMessageRequest: hasPendingMessageRequest,
                                           lastMessageForInbox: lastMessageForInbox,
                                           transaction: transaction)
    }

    private static func buildHVSnippet(thread: TSThread,
                                       isBlocked: Bool,
                                       hasPendingMessageRequest: Bool,
                                       lastMessageForInbox: TSInteraction?,
                                       transaction: SDSAnyReadTransaction) -> HVSnippet {

        func loadDraftText() -> String? {
            guard let draftMessageBody = thread.currentDraft(shouldFetchLatest: false,
                                                             transaction: transaction) else {
                return nil
            }
            return draftMessageBody.plaintextBody(transaction: transaction.unwrapGrdbRead)
        }
        func hasVoiceMemoDraft() -> Bool {
            VoiceMessageModel.hasDraft(for: thread, transaction: transaction)
        }
        func loadLastMessageText() -> String? {
            guard let previewable = lastMessageForInbox as? OWSPreviewText else {
                return nil
            }
            return previewable.previewText(transaction: transaction).filterStringForDisplay()
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
                return NSLocalizedString("GROUP_MEMBER_LOCAL_USER",
                                         comment: "Label indicating the local user.")
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

public enum HVSnippet {
    case blocked
    case pendingMessageRequest(addedToGroupByName: String?)
    case draft(draftText: String)
    case voiceMemoDraft
    case contactSnippet(lastMessageText: String)
    case groupSnippet(lastMessageText: String, senderName: String)
    case none
}
