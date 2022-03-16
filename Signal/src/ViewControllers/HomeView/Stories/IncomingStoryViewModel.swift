//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

struct IncomingStoryViewModel: Dependencies {
    let context: StoryContext

    let messages: [StoryMessage]
    let hasUnviewedMessages: Bool
    enum Attachment {
        case file(TSAttachment)
        case text(TextAttachment)
        case missing
    }
    let latestMessageAttachment: Attachment
    let latestMessageHasReplies: Bool
    let latestMessageName: String
    let latestMessageTimestamp: UInt64

    let latestMessageAvatarDataSource: ConversationAvatarDataSource

    init(messages: [StoryMessage], transaction: SDSAnyReadTransaction) throws {
        let sortedFilteredMessages = messages.lazy.filter { $0.direction == .incoming }.sorted { $0.timestamp < $1.timestamp }
        self.messages = sortedFilteredMessages
        self.hasUnviewedMessages = sortedFilteredMessages.contains { message in
            switch message.manifest {
            case .incoming(_, let viewedTimestamp):
                return viewedTimestamp == nil
            case .outgoing:
                owsFailDebug("Unexpected message type")
                return false
            }
        }

        guard let latestMessage = sortedFilteredMessages.last else {
            throw OWSAssertionError("At least one message is required.")
        }

        self.context = latestMessage.context

        if let groupId = latestMessage.groupId {
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Missing group thread for group story")
            }
            let authorShortName = Self.contactsManager.shortDisplayName(
                for: latestMessage.authorAddress,
                transaction: transaction
            )
            let nameFormat = NSLocalizedString(
                "GROUP_STORY_NAME_FORMAT",
                comment: "Name for a group story on the stories list. Embeds {author's name}, {group name}")
            latestMessageName = String(format: nameFormat, authorShortName, groupThread.groupNameOrDefault)
            latestMessageAvatarDataSource = .thread(groupThread)
        } else {
            latestMessageName = Self.contactsManager.displayName(
                for: latestMessage.authorAddress,
                transaction: transaction
            )
            latestMessageAvatarDataSource = .address(latestMessage.authorAddress)
        }

        switch latestMessage.attachment {
        case .file(let attachmentId):
            guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) else {
                owsFailDebug("Unexpectedly missing attachment for story")
                latestMessageAttachment = .missing
                break
            }
            latestMessageAttachment = .file(attachment)
        case .text(let attachment):
            latestMessageAttachment = .text(attachment)
        }

        latestMessageHasReplies = false // TODO: replies
        latestMessageTimestamp = latestMessage.timestamp
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
        case .none:
            owsFailDebug("Unexpected StoryContext for batch update")
            return "none"
        }
    }
    public var logSafeDescription: String { batchUpdateId }
}
