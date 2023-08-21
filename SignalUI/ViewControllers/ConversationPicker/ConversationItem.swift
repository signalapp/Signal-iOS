//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
    var isStory: Bool { get }
    var disappearingMessagesConfig: OWSDisappearingMessagesConfiguration? { get }

    func getExistingThread(transaction: SDSAnyReadTransaction) -> TSThread?
    func getOrCreateThread(transaction: SDSAnyWriteTransaction) -> TSThread?

    /// If true, attachments will be segmented into chunks shorter than
    /// `StoryMessage.videoAttachmentDurationLimit` and limited in quality.
    var limitsVideoAttachmentLengthForStories: Bool { get }

    /// If non-nill, tooltip text that will be shown when attempting to send a video to this
    /// conversation that exceeds the story video attachment duration.
    /// Should be set if `limitsVideoAttachmentLengthForStories` is true.
    var videoAttachmentStoryLengthTooltipString: String? { get }
}

extension ConversationItem {
    public var titleWithSneakyTransaction: String { SDSDatabaseStorage.shared.read { title(transaction: $0) } }

    public var videoAttachmentDurationLimit: TimeInterval? {
        return limitsVideoAttachmentLengthForStories ? StoryMessage.videoAttachmentDurationLimit : nil
    }

    public var videoAttachmentStoryLengthTooltipString: String? {
        if limitsVideoAttachmentLengthForStories {
            owsFailDebug("Should set if limitsVideoAttachmentLengthForStories is true.")
        }
        return nil
    }
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

    var limitsVideoAttachmentLengthForStories: Bool { return unwrapped.limitsVideoAttachmentLengthForStories }

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

    var isStory: Bool { return false }

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

    init(
        address: SignalServiceAddress,
        isBlocked: Bool,
        disappearingMessagesConfig: OWSDisappearingMessagesConfiguration?,
        contactName: String,
        comparableName: String
    ) {
        owsAssertBeta(
            !isBlocked,
            "Should never get here with a blocked contact!"
        )

        self.address = address
        self.isBlocked = isBlocked
        self.disappearingMessagesConfig = disappearingMessagesConfig
        self.contactName = contactName
        self.comparableName = comparableName
    }
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

    var isStory: Bool { return false }

    var limitsVideoAttachmentLengthForStories: Bool { return false }

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

    init(
        groupThreadId: String,
        isBlocked: Bool,
        disappearingMessagesConfig: OWSDisappearingMessagesConfiguration?
    ) {
        owsAssertBeta(
            !isBlocked,
            "Should never get here with a blocked group!"
        )

        self.groupThreadId = groupThreadId
        self.isBlocked = isBlocked
        self.disappearingMessagesConfig = disappearingMessagesConfig
    }

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

    public var isStory: Bool { return false }

    public var limitsVideoAttachmentLengthForStories: Bool { return false }

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

    public var threadId: String {
        switch backingItem {
        case .groupStory(let item): return item.groupThreadId
        case .privateStory(let item): return item.storyThreadId
        }
    }

    public let backingItem: ItemType
    var unwrapped: ConversationItem {
        switch backingItem {
        case .groupStory(let item): return item
        case .privateStory(let item): return item
        }
    }

    public var storyState: StoryContextViewState?

    public static func allItems(
        includeImplicitGroupThreads: Bool,
        excludeHiddenContexts: Bool,
        prioritizeThreadsCreatedAfter: Date? = nil,
        blockingManager: BlockingManager,
        transaction: SDSAnyReadTransaction
    ) -> [StoryConversationItem] {
        func sortTime(
            for associatedData: StoryContextAssociatedData?,
            thread: TSThread
        ) -> UInt64 {
            if
                let thread = thread as? TSGroupThread,
                associatedData?.lastReceivedTimestamp ?? 0 > thread.lastSentStoryTimestamp?.uint64Value ?? 0
            {
                return associatedData?.lastReceivedTimestamp ?? 0
            }

            return thread.lastSentStoryTimestamp?.uint64Value ?? 0
        }

        let threads = ThreadFinder().storyThreads(
            includeImplicitGroupThreads: includeImplicitGroupThreads,
            transaction: transaction
        )

        return buildItems(
            from: threads,
            excludeHiddenContexts: excludeHiddenContexts,
            blockingManager: blockingManager,
            transaction: transaction,
            sortingBy: { lhs, rhs in
                if (lhs.0 as? TSPrivateStoryThread)?.isMyStory == true { return true }
                if (rhs.0 as? TSPrivateStoryThread)?.isMyStory == true { return false }
                if let priorityDateThreshold = prioritizeThreadsCreatedAfter {
                    let lhsCreatedAfterThreshold = lhs.0.creationDate?.isAfter(priorityDateThreshold) ?? false
                    let rhsCreatedAfterThreshold = rhs.0.creationDate?.isAfter(priorityDateThreshold) ?? false
                    if lhsCreatedAfterThreshold != rhsCreatedAfterThreshold {
                        return lhsCreatedAfterThreshold
                    }
                }
                return sortTime(for: lhs.1, thread: lhs.0) > sortTime(for: rhs.1, thread: rhs.0)
            }
        )
    }

    public static func buildItems(
        from threads: [TSThread],
        excludeHiddenContexts: Bool,
        blockingManager: BlockingManager,
        transaction: SDSAnyReadTransaction,
        sortingBy areInIncreasingOrderFunc: (((TSThread, StoryContextAssociatedData?), (TSThread, StoryContextAssociatedData?)) -> Bool)? = nil
    ) -> [Self] {
        let outgoingStories = StoryFinder
            .outgoingStories(transaction: transaction)
            .reduce(
                into: (privateStoryThreadUniqueIDs: Set<String>(), groupIDs: Set<Data>())
            ) { partialResult, story in
                if let groupID = story.groupId {
                    partialResult.groupIDs.insert(groupID)
                    return
                }

                switch story.manifest {
                case .incoming:
                    break
                case .outgoing(recipientStates: let recipientStates):
                    partialResult.privateStoryThreadUniqueIDs.formUnion(
                        recipientStates.values.lazy
                            .flatMap(\.contexts)
                            .map(\.uuidString)
                    )
                }
            }

        var threadsAndAssociatedData = threads
            .compactMap { (thread: TSThread) -> (TSThread, StoryContextAssociatedData?)? in
                let associatedData = StoryFinder.associatedData(for: thread, transaction: transaction)
                if excludeHiddenContexts, associatedData?.isHidden ?? false {
                    return nil
                }
                return (thread, associatedData)
            }

        if let areInIncreasingOrderFunc {
            threadsAndAssociatedData.sort(by: areInIncreasingOrderFunc)
        }

        return threadsAndAssociatedData
            .compactMap { thread, associatedData -> Self? in
                let isThreadBlocked = blockingManager.isThreadBlocked(
                    thread,
                    transaction: transaction
                )

                if isThreadBlocked {
                    return nil
                }

                // Associated data tracks view state for incoming stories.
                // It does not track our own outgoing stories, so we need
                // to check that separately.
                lazy var threadHasOutgoingStories: Bool = {
                    if let groupThread = thread as? TSGroupThread {
                        if outgoingStories.groupIDs.contains(groupThread.groupId) {
                            return true
                        }
                    } else {
                        if outgoingStories.privateStoryThreadUniqueIDs.contains(thread.uniqueId) {
                            return true
                        }
                    }
                    return false
                }()

                let storyState: StoryContextViewState

                switch (associatedData?.hasUnviewedStories, associatedData?.hasUnexpiredStories) {
                case (true, _):
                    // There is an unviewed thread
                    storyState = .unviewed
                case (_, true),
                    (_, _) where threadHasOutgoingStories:
                    // There are unexpired or outgoing stories
                    storyState = .viewed
                default:
                    // There are no stories
                    storyState = .noStories
                }

                return .from(
                    thread: thread,
                    storyState: storyState,
                    isBlocked: isThreadBlocked
                )
            }
    }

    private static func from(
        thread: TSThread,
        storyState: StoryContextViewState?,
        isBlocked: Bool
    ) -> Self? {
        let backingItem: StoryConversationItem.ItemType? = {
            if let groupThread = thread as? TSGroupThread {
                guard groupThread.isLocalUserFullMember else {
                    return nil
                }
                return .groupStory(GroupConversationItem(
                    groupThreadId: groupThread.uniqueId,
                    isBlocked: isBlocked,
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
        }()
        guard let backingItem = backingItem else {
            return nil
        }
        return .init(backingItem: backingItem, storyState: storyState)
    }
}

// MARK: -

extension StoryConversationItem: ConversationItem {
    public var outgoingMessageClass: TSOutgoingMessage.Type { OutgoingStoryMessage.self }

    public var limitsVideoAttachmentLengthForStories: Bool { return true }

    public var videoAttachmentStoryLengthTooltipString: String? {
        return StoryMessage.videoSegmentationTooltip
    }

    public var messageRecipient: MessageRecipient {
        unwrapped.messageRecipient
    }

    public var isMyStory: Bool {
        switch backingItem {
        case .groupStory:
            return false
        case .privateStory(let item):
            return item.isMyStory
        }
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
                guard StoryManager.hasSetMyStoriesPrivacy(transaction: transaction) else {
                    return OWSLocalizedString(
                        "MY_STORY_PICKER_UNSET_PRIVACY_SUBTITLE",
                        comment: "Subtitle shown on my story in the conversation picker when sending a story for the first time with unset my story privacy settings.")
                }
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
                        return String.localizedStringWithFormat(format, thread.addresses.count)
                    }
                case .explicit:
                    let format = OWSLocalizedString(
                        "MY_STORY_VIEWERS_ONLY_%d",
                        tableName: "PluralAware",
                        comment: "Format string representing the viewer count for 'My Story' when accessible to only an explicit list of viewers. Embeds {{ number of viewers }}.")
                    return String.localizedStringWithFormat(format, recipientCount)
                case .default, .disabled:
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

    public var isStory: Bool { return true }

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

    public var limitsVideoAttachmentLengthForStories: Bool { return true }

    public var videoAttachmentStoryLengthTooltipString: String? {
        return StoryMessage.videoSegmentationTooltip
    }

    public var isBlocked: Bool { false }

    public var isStory: Bool { return true }

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
        UIImage(named: "custom-story-\(Theme.isDarkThemeEnabled ? "dark" : "light")-36")
    }

    public func getExistingThread(transaction: SDSAnyReadTransaction) -> TSThread? {
        TSPrivateStoryThread.anyFetchPrivateStoryThread(uniqueId: storyThreadId, transaction: transaction)
    }

    public func getOrCreateThread(transaction: SDSAnyWriteTransaction) -> TSThread? {
        getExistingThread(transaction: transaction)
    }
}
