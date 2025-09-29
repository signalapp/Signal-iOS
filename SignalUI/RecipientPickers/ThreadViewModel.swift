//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

final public class ThreadViewModel: NSObject {
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
    public let isBlocked: Bool
    public let isPinned: Bool

    public var isArchived: Bool { associatedData.isArchived }
    public var isMuted: Bool { associatedData.isMuted }
    public var mutedUntilTimestamp: UInt64 { associatedData.mutedUntilTimestamp }
    public var mutedUntilDate: Date? { associatedData.mutedUntilDate }
    public var isMarkedUnread: Bool { associatedData.isMarkedUnread }

    public var threadUniqueId: String {
        return threadRecord.uniqueId
    }

    public var isContactThread: Bool {
        return !isGroupThread
    }

    public var isLocalUserFullMemberOfThread: Bool {
        threadRecord.isLocalUserFullMemberOfThread
    }

    public let lastMessageForInbox: TSInteraction?

    // This property is only populated if forChatList is true.
    public let chatListInfo: ChatListInfo?

    /// Instantiate a view model for the thread with the given uniqueId.
    /// - Important
    /// Crashes if the corresponding thread does not exist.
    public convenience init(threadUniqueId: String, forChatList: Bool, transaction tx: DBReadTransaction) {
        guard let thread = DependenciesBridge.shared.threadStore.fetchThread(
            uniqueId: threadUniqueId,
            tx: tx
        ) else {
            owsFail("Unexpectedly missing thread for unique ID!")
        }

        self.init(thread: thread, forChatList: forChatList, transaction: tx)
    }

    public init(thread: TSThread, forChatList: Bool, transaction: DBReadTransaction) {
        self.threadRecord = thread

        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        self.disappearingMessagesConfiguration = dmConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: transaction)

        self.isGroupThread = thread.isGroupThread

        let threadDisplayName = SSKEnvironment.shared.contactManagerRef.displayName(for: thread, tx: transaction)
        self.name = threadDisplayName?.resolvedValue() ?? ""

        if case .contactThread(let displayName) = threadDisplayName {
            self.shortName = displayName.resolvedValue(useShortNameIfAvailable: true)
        } else {
            self.shortName = nil
        }

        let associatedData = ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction)
        self.associatedData = associatedData

        if let contactThread = thread as? TSContactThread {
            self.contactAddress = contactThread.contactAddress
        } else {
            self.contactAddress = nil
        }

        let unreadCount = InteractionFinder(threadUniqueId: thread.uniqueId).unreadCount(transaction: transaction)
        self.unreadCount = unreadCount
        self.hasUnreadMessages = associatedData.isMarkedUnread || unreadCount > 0
        self.hasPendingMessageRequest = thread.hasPendingMessageRequest(transaction: transaction)

        self.lastMessageForInbox = thread.lastInteractionForInbox(transaction: transaction)

        if forChatList {
            chatListInfo = ChatListInfo(
                thread: thread,
                lastMessageForInbox: lastMessageForInbox,
                hasPendingMessageRequest: hasPendingMessageRequest,
                transaction: transaction
            )
        } else {
            chatListInfo = nil
        }

        isBlocked = SSKEnvironment.shared.blockingManagerRef.isThreadBlocked(thread, transaction: transaction)
        isPinned = DependenciesBridge.shared.pinnedThreadStore.isThreadPinned(thread, tx: transaction)
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let otherThread = object as? ThreadViewModel else {
            return super.isEqual(object)
        }

        return threadRecord.isEqual(otherThread.threadRecord)
    }
}

// MARK: -

final public class ChatListInfo {

    public let lastMessageDate: Date?
    public let lastMessageOutgoingStatus: MessageReceiptStatus?
    public let snippet: CLVSnippet

    public init(
        thread: TSThread,
        lastMessageForInbox: TSInteraction?,
        hasPendingMessageRequest: Bool,
        transaction: DBReadTransaction
    ) {

        self.lastMessageDate = lastMessageForInbox?.timestampDate
        self.lastMessageOutgoingStatus = { () -> MessageReceiptStatus? in
            guard let outgoingMessage = lastMessageForInbox as? TSOutgoingMessage else {
                return nil
            }
            if
                let paymentMessage = outgoingMessage as? OWSPaymentMessage,
                let receiptData = paymentMessage.paymentNotification?.mcReceiptData,
                let paymentModel = PaymentFinder.paymentModels(
                    forMcReceiptData: receiptData,
                    transaction: transaction
                ).first
            {
                return MessageRecipientStatusUtils.recipientStatus(
                    outgoingMessage: outgoingMessage,
                    paymentModel: paymentModel
                )
            } else {
                return MessageRecipientStatusUtils.recipientStatus(
                    outgoingMessage: outgoingMessage,
                    transaction: transaction
                )
            }
        }()

        self.snippet = Self.buildCLVSnippet(
            thread: thread,
            hasPendingMessageRequest: hasPendingMessageRequest,
            lastMessageForInbox: lastMessageForInbox,
            transaction: transaction
        )
    }

    private static func buildCLVSnippet(
        thread: TSThread,
        hasPendingMessageRequest: Bool,
        lastMessageForInbox: TSInteraction?,
        transaction: DBReadTransaction
    ) -> CLVSnippet {

        let isBlocked = SSKEnvironment.shared.blockingManagerRef.isThreadBlocked(thread, transaction: transaction)

        func loadDraftText() -> HydratedMessageBody? {
            guard let draftMessageBody = thread.currentDraft(shouldFetchLatest: false,
                                                             transaction: transaction) else {
                return nil
            }
            return draftMessageBody
                .hydrating(
                    mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: transaction)
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
                return SSKEnvironment.shared.contactManagerImplRef.shortestDisplayName(
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
            guard
                let groupThread = thread as? TSGroupThread,
                let addedByAddress = groupThread.groupModel.addedByAddress
            else {
                return nil
            }
            return SSKEnvironment.shared.contactManagerRef.displayName(for: addedByAddress, tx: transaction).resolvedValue(useShortNameIfAvailable: true)
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
