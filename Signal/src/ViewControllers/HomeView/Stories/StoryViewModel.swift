//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

struct StoryViewModel: Dependencies {
    let context: StoryContext

    let messages: [StoryMessage]
    let hasUnviewedMessages: Bool

    let latestMessageAttachment: StoryThumbnailView.Attachment
    let hasReplies: Bool
    let latestMessageName: String
    let latestMessageTimestamp: UInt64
    let latestMessageViewedTimestamp: UInt64?

    let latestMessageAvatarDataSource: ConversationAvatarDataSource

    var isSystemStory: Bool {
        return messages.first?.authorAddress.isSystemStoryAddress ?? false
    }

    init(messages: [StoryMessage], transaction: SDSAnyReadTransaction) throws {
        let sortedFilteredMessages = messages.lazy.sorted { $0.timestamp < $1.timestamp }
        self.messages = sortedFilteredMessages
        self.hasUnviewedMessages = sortedFilteredMessages.contains { $0.localUserViewedTimestamp == nil }

        guard let latestMessage = sortedFilteredMessages.last else {
            throw OWSAssertionError("At least one message is required.")
        }

        self.context = latestMessage.context
        self.hasReplies = InteractionFinder.hasReplies(for: sortedFilteredMessages, transaction: transaction)

        latestMessageName = StoryAuthorUtil.authorDisplayName(
            for: latestMessage,
            contactsManager: Self.contactsManager,
            transaction: transaction
        )
        latestMessageAvatarDataSource = try StoryAuthorUtil.contextAvatarDataSource(for: latestMessage, transaction: transaction)
        latestMessageAttachment = .from(latestMessage.attachment, transaction: transaction)
        latestMessageTimestamp = latestMessage.timestamp
        latestMessageViewedTimestamp = latestMessage.localUserViewedTimestamp
    }

    func copy(updatedMessages: [StoryMessage], deletedMessageRowIds: [Int64], transaction: SDSAnyReadTransaction) throws -> Self? {
        var newMessages = updatedMessages
        var messages: [StoryMessage] = self.messages.lazy
            .filter { oldMessage in
                guard let oldMessageId = oldMessage.id else { return true }
                return !deletedMessageRowIds.contains(oldMessageId)
            }
            .map { oldMessage in
                if let idx = newMessages.firstIndex(where: { $0.uniqueId == oldMessage.uniqueId }) {
                    return newMessages.remove(at: idx)
                } else {
                    return oldMessage
                }
            }
        messages.append(contentsOf: newMessages)
        guard !messages.isEmpty else { return nil }
        return try .init(messages: messages, transaction: transaction)
    }
}

extension StoryContext: BatchUpdateValue {
    public var batchUpdateId: String {
        switch self {
        case .groupId(let data):
            return data.hexadecimalString
        case .authorUuid(let uuid):
            return uuid.uuidString
        case .privateStory(let uniqueId):
            return uniqueId
        case .none:
            owsFailDebug("Unexpected StoryContext for batch update")
            return "none"
        }
    }
    public var logSafeDescription: String { batchUpdateId }
}
