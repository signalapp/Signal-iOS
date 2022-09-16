//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMessaging

public enum MessageRecipient: Equatable {
    case contact(_ address: SignalServiceAddress)
    case group(_ groupThreadId: String)
    case privateStory(_ storyThreadId: String, isMyStory: Bool)
}

// MARK: -

public protocol ConversationItem {
    var messageRecipient: MessageRecipient { get }

    func title(transaction: SDSAnyReadTransaction) -> String

    var outgoingMessageClass: TSOutgoingMessage.Type { get }

    var image: UIImage? { get }
    var isBlocked: Bool { get }
    var disappearingMessagesConfig: OWSDisappearingMessagesConfiguration? { get }

    func getExistingThread(transaction: SDSAnyReadTransaction) -> TSThread?
    func getOrCreateThread(transaction: SDSAnyWriteTransaction) -> TSThread?
}

extension ConversationItem {
    public var titleWithSneakyTransaction: String { SDSDatabaseStorage.shared.read { title(transaction: $0) } }
}

// MARK: -

struct RecentConversationItem {
    enum ItemType {
        case contact(_ item: ContactConversationItem)
        case group(_ item: GroupConversationItem)
    }

    let backingItem: ItemType
    var unwrapped: ConversationItem {
        switch backingItem {
        case .contact(let contactItem):
            return contactItem
        case .group(let groupItem):
            return groupItem
        }
    }
}

// MARK: -

extension RecentConversationItem: ConversationItem {
    var outgoingMessageClass: TSOutgoingMessage.Type { unwrapped.outgoingMessageClass }

    var messageRecipient: MessageRecipient {
        return unwrapped.messageRecipient
    }

    func title(transaction: SDSAnyReadTransaction) -> String {
        return unwrapped.title(transaction: transaction)
    }

    var image: UIImage? {
        return unwrapped.image
    }

    var isBlocked: Bool {
        return unwrapped.isBlocked
    }

    var disappearingMessagesConfig: OWSDisappearingMessagesConfiguration? {
        return unwrapped.disappearingMessagesConfig
    }

    func getExistingThread(transaction: SDSAnyReadTransaction) -> TSThread? {
        return unwrapped.getExistingThread(transaction: transaction)
    }

    func getOrCreateThread(transaction: SDSAnyWriteTransaction) -> TSThread? {
        return unwrapped.getOrCreateThread(transaction: transaction)
    }
}

// MARK: -

struct ContactConversationItem: Dependencies {
    let address: SignalServiceAddress
    let isBlocked: Bool
    let disappearingMessagesConfig: OWSDisappearingMessagesConfiguration?
    let contactName: String
    let comparableName: String
}

// MARK: -

extension ContactConversationItem: Comparable {
    public static func < (lhs: ContactConversationItem, rhs: ContactConversationItem) -> Bool {
        return lhs.comparableName < rhs.comparableName
    }
}

// MARK: -

extension ContactConversationItem: ConversationItem {
    var outgoingMessageClass: TSOutgoingMessage.Type { TSOutgoingMessage.self }

    var messageRecipient: MessageRecipient {
        .contact(address)
    }

    func title(transaction: SDSAnyReadTransaction) -> String {
        guard !address.isLocalAddress else {
            return MessageStrings.noteToSelf
        }

        return contactName
    }

    var image: UIImage? {
        databaseStorage.read { transaction in
            self.contactsManagerImpl.avatarImage(forAddress: self.address,
                                                 shouldValidate: true,
                                                 transaction: transaction)
        }
    }

    func getExistingThread(transaction: SDSAnyReadTransaction) -> TSThread? {
        return TSContactThread.getWithContactAddress(address, transaction: transaction)
    }

    func getOrCreateThread(transaction: SDSAnyWriteTransaction) -> TSThread? {
        return TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction)
    }
}

// MARK: -

public struct GroupConversationItem: Dependencies {
    public let groupThreadId: String
    public let isBlocked: Bool
    public let disappearingMessagesConfig: OWSDisappearingMessagesConfiguration?

    // We don't want to keep this in memory, because the group model
    // can be very large.
    public var groupThread: TSGroupThread? {
        databaseStorage.read { transaction in
            return TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId, transaction: transaction)
        }
    }

    public var groupModel: TSGroupModel? {
        groupThread?.groupModel
    }
}

// MARK: -

extension GroupConversationItem: ConversationItem {
    public var outgoingMessageClass: TSOutgoingMessage.Type { TSOutgoingMessage.self }

    public var messageRecipient: MessageRecipient {
        .group(groupThreadId)
    }

    public func title(transaction: SDSAnyReadTransaction) -> String {
        guard let groupThread = getExistingThread(transaction: transaction) as? TSGroupThread else {
            return TSGroupThread.defaultGroupName
        }
        return groupThread.groupNameOrDefault
    }

    public var image: UIImage? {
        guard let groupThread = groupThread else { return nil }
        return databaseStorage.read { transaction in
            Self.avatarBuilder.avatarImage(forGroupThread: groupThread,
                                           diameterPoints: AvatarBuilder.standardAvatarSizePoints,
                                           transaction: transaction)
        }
    }

    public func getExistingThread(transaction: SDSAnyReadTransaction) -> TSThread? {
        return TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId, transaction: transaction)
    }

    public func getOrCreateThread(transaction: SDSAnyWriteTransaction) -> TSThread? {
        return getExistingThread(transaction: transaction)
    }
}

// MARK: -

public struct StoryConversationItem {
    public enum ItemType {
        case groupStory(_ item: GroupConversationItem)
        case privateStory(_ item: PrivateStoryConversationItem)
    }

    public let backingItem: ItemType
    var unwrapped: ConversationItem {
        switch backingItem {
        case .groupStory(let item): return item
        case .privateStory(let item): return item
        }
    }

    public static func allItems(transaction: SDSAnyReadTransaction) -> [StoryConversationItem] {
        AnyThreadFinder().storyThreads(transaction: transaction)
            .lazy
            .sorted { lhs, rhs in
                if (lhs as? TSPrivateStoryThread)?.isMyStory == true { return true }
                if (rhs as? TSPrivateStoryThread)?.isMyStory == true { return false }
                return (lhs.lastSentStoryTimestamp?.uint64Value ?? 0) > (rhs.lastSentStoryTimestamp?.uint64Value ?? 0)
            }
            .compactMap { thread -> StoryConversationItem.ItemType? in
                if let groupThread = thread as? TSGroupThread {
                    guard groupThread.isLocalUserFullMember else {
                        return nil
                    }
                    return .groupStory(GroupConversationItem(
                        groupThreadId: groupThread.uniqueId,
                        isBlocked: false,
                        disappearingMessagesConfig: nil
                    ))
                } else if let privateStoryThread = thread as? TSPrivateStoryThread {
                    return .privateStory(PrivateStoryConversationItem(
                        storyThreadId: privateStoryThread.uniqueId,
                        isMyStory: privateStoryThread.isMyStory
                    ))
                } else {
                    owsFailDebug("Unexpected story thread type \(type(of: thread))")
                    return nil
                }
            }.map { .init(backingItem: $0) }
    }
}

// MARK: -

extension StoryConversationItem: ConversationItem {
    public var outgoingMessageClass: TSOutgoingMessage.Type { OutgoingStoryMessage.self }

    public var messageRecipient: MessageRecipient {
        unwrapped.messageRecipient
    }

    public func title(transaction: SDSAnyReadTransaction) -> String {
        unwrapped.title(transaction: transaction)
    }

    public func subtitle(transaction: SDSAnyReadTransaction) -> String? {
        guard let thread = getExistingThread(transaction: transaction) else {
            owsFailDebug("Unexpectedly missing story thread")
            return nil
        }
        let recipientCount = thread.recipientAddresses(with: transaction).count

        switch backingItem {
        case .privateStory(let item):
            if item.isMyStory {
                switch thread.storyViewMode {
                case .blockList:
                    guard let thread = thread as? TSPrivateStoryThread else {
                        owsFailDebug("Unexpected thread type")
                        return ""
                    }
                    if thread.addresses.isEmpty {
                        let format = OWSLocalizedString(
                            "MY_STORY_VIEWERS_ALL_CONNECTIONS_%d",
                            tableName: "PluralAware",
                            comment: "Format string representing the viewer count for 'My Story' when accessible to all signal connections. Embeds {{ number of viewers }}.")
                        return String.localizedStringWithFormat(format, recipientCount)
                    } else {
                        let format = OWSLocalizedString(
                            "MY_STORY_VIEWERS_ALL_CONNECTIONS_EXCLUDING_%d",
                            tableName: "PluralAware",
                            comment: "Format string representing the excluded viewer count for 'My Story' when accessible to all signal connections. Embeds {{ number of excluded viewers }}.")
                        return String.localizedStringWithFormat(format, recipientCount)
                    }
                case .explicit:
                    let format = OWSLocalizedString(
                        "MY_STORY_VIEWERS_ONLY_%d",
                        tableName: "PluralAware",
                        comment: "Format string representing the viewer count for 'My Story' when accessible to only an explicit list of viewers. Embeds {{ number of viewers }}.")
                    return String.localizedStringWithFormat(format, recipientCount)
                case .none:
                    owsFailDebug("Unexpected view mode for my story")
                    return ""
                }
            } else {
                let format = OWSLocalizedString(
                    "PRIVATE_STORY_VIEWERS_%d",
                    tableName: "PluralAware",
                    comment: "Format string representing the viewer count for a custom story list. Embeds {{ number of viewers }}.")
                return String.localizedStringWithFormat(format, recipientCount)
            }
        case .groupStory:
            let format = OWSLocalizedString(
                "GROUP_STORY_VIEWERS_%d",
                tableName: "PluralAware",
                comment: "Format string representing the viewer count for a group story list. Embeds {{ number of viewers }}.")
            return String.localizedStringWithFormat(format, recipientCount)
        }
    }

    public var image: UIImage? {
        unwrapped.image
    }

    public var isBlocked: Bool {
        unwrapped.isBlocked
    }

    public var disappearingMessagesConfig: OWSDisappearingMessagesConfiguration? {
        unwrapped.disappearingMessagesConfig
    }

    public func getExistingThread(transaction: SDSAnyReadTransaction) -> TSThread? {
        unwrapped.getExistingThread(transaction: transaction)
    }

    public func getOrCreateThread(transaction: SDSAnyWriteTransaction) -> TSThread? {
        unwrapped.getOrCreateThread(transaction: transaction)
    }
}

// MARK: -

public struct PrivateStoryConversationItem: Dependencies {
    let storyThreadId: String
    public let isMyStory: Bool

    public var storyThread: TSPrivateStoryThread? {
        databaseStorage.read { transaction in
            return TSPrivateStoryThread.anyFetchPrivateStoryThread(uniqueId: storyThreadId, transaction: transaction)
        }
    }
}

// MARK: -

extension PrivateStoryConversationItem: ConversationItem {
    public var outgoingMessageClass: TSOutgoingMessage.Type { OutgoingStoryMessage.self }

    public var isBlocked: Bool { false }

    public var disappearingMessagesConfig: OWSDisappearingMessagesConfiguration? { nil }

    public var messageRecipient: MessageRecipient { .privateStory(storyThreadId, isMyStory: isMyStory) }

    public func title(transaction: SDSAnyReadTransaction) -> String {
        guard let storyThread = getExistingThread(transaction: transaction) as? TSPrivateStoryThread else {
            owsFailDebug("Missing story thread")
            return ""
        }
        return storyThread.name
    }

    public var image: UIImage? {
        UIImage(named: "private-story-\(Theme.isDarkThemeEnabled ? "dark" : "light")-36")
    }

    public func getExistingThread(transaction: SDSAnyReadTransaction) -> TSThread? {
        TSPrivateStoryThread.anyFetchPrivateStoryThread(uniqueId: storyThreadId, transaction: transaction)
    }

    public func getOrCreateThread(transaction: SDSAnyWriteTransaction) -> TSThread? {
        getExistingThread(transaction: transaction)
    }
}
