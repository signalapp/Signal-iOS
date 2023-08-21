//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import Foundation
import SignalServiceKit
import SignalMessaging

public typealias MessageSortKey = UInt64

public struct ConversationSortKey: Comparable {
    let isContactThread: Bool
    let creationDate: Date?
    let lastInteractionRowId: UInt64

    // MARK: Comparable

    public static func < (lhs: ConversationSortKey, rhs: ConversationSortKey) -> Bool {
        // always show matching contact results first
        if lhs.isContactThread, !rhs.isContactThread {
            return false
        } else if !lhs.isContactThread, rhs.isContactThread {
            return true
        }

        if lhs.lastInteractionRowId != rhs.lastInteractionRowId {
            return lhs.lastInteractionRowId < rhs.lastInteractionRowId
        }
        let longAgo = Date(timeIntervalSince1970: 0)
        let lhsDate = lhs.creationDate ?? longAgo
        let rhsDate = rhs.creationDate ?? longAgo
        return lhsDate < rhsDate
    }
}

// MARK: -

public class ConversationSearchResult<SortKey>: Comparable where SortKey: Comparable {
    public let thread: ThreadViewModel

    public let messageId: String?
    public let messageDate: Date?

    public let snippet: CVTextValue?

    private let sortKey: SortKey

    init(thread: ThreadViewModel, sortKey: SortKey, messageId: String? = nil, messageDate: Date? = nil, snippet: CVTextValue? = nil) {
        self.thread = thread
        self.sortKey = sortKey
        self.messageId = messageId
        self.messageDate = messageDate
        self.snippet = snippet
    }

    // MARK: Comparable

    public static func < (lhs: ConversationSearchResult, rhs: ConversationSearchResult) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    // MARK: Equatable

    public static func == (lhs: ConversationSearchResult, rhs: ConversationSearchResult) -> Bool {
        return lhs.thread.threadRecord.uniqueId == rhs.thread.threadRecord.uniqueId &&
            lhs.messageId == rhs.messageId
    }
}

// MARK: -

public class ContactSearchResult: Comparable, Dependencies {

    public let signalAccount: SignalAccount
    private let comparableName: String

    public var recipientAddress: SignalServiceAddress {
        return signalAccount.recipientAddress
    }

    init(signalAccount: SignalAccount, transaction: SDSAnyReadTransaction) {
        self.signalAccount = signalAccount
        self.comparableName = Self.contactsManager.comparableName(for: signalAccount, transaction: transaction)
    }

    // MARK: Comparable

    public static func < (lhs: ContactSearchResult, rhs: ContactSearchResult) -> Bool {
        var comparisonResult = lhs.comparableName.caseInsensitiveCompare(rhs.comparableName)

        if comparisonResult == .orderedSame {
            comparisonResult = lhs.recipientAddress.stringForDisplay.compare(rhs.recipientAddress.stringForDisplay)
        }

        return comparisonResult == .orderedAscending
    }

    // MARK: Equatable

    public static func == (lhs: ContactSearchResult, rhs: ContactSearchResult) -> Bool {
        return lhs.recipientAddress == rhs.recipientAddress
    }
}

// MARK: -

/// Can represent either a group thread with stories, or a private story thread.
public class StorySearchResult: Comparable {

    public let thread: TSThread

    private let sortKey: ConversationSortKey

    init(thread: TSThread, sortKey: ConversationSortKey) {
        self.thread = thread
        self.sortKey = sortKey
    }

    // MARK: Comparable

    public static func < (lhs: StorySearchResult, rhs: StorySearchResult) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    // MARK: Equatable

    public static func == (lhs: StorySearchResult, rhs: StorySearchResult) -> Bool {
        return lhs.thread.uniqueId == rhs.thread.uniqueId
    }
}

// MARK: -

public class HomeScreenSearchResultSet: NSObject {
    public let searchText: String
    public let contactThreads: [ConversationSearchResult<ConversationSortKey>]
    public let groupThreads: [GroupSearchResult]
    public let contacts: [ContactSearchResult]
    public let messages: [ConversationSearchResult<MessageSortKey>]

    public init(
        searchText: String,
        contactThreads: [ConversationSearchResult<ConversationSortKey>],
        groupThreads: [GroupSearchResult],
        contacts: [ContactSearchResult],
        messages: [ConversationSearchResult<MessageSortKey>]
    ) {
        self.searchText = searchText
        self.contactThreads = contactThreads
        self.groupThreads = groupThreads
        self.contacts = contacts
        self.messages = messages
    }

    public class var empty: HomeScreenSearchResultSet {
        return HomeScreenSearchResultSet(searchText: "", contactThreads: [], groupThreads: [], contacts: [], messages: [])
    }

    public var isEmpty: Bool {
        return contactThreads.isEmpty && groupThreads.isEmpty && contacts.isEmpty && messages.isEmpty
    }
}

// MARK: -

public class GroupSearchResult: Comparable {

    public let thread: ThreadViewModel
    public let matchedMembersSnippet: String?

    private let sortKey: ConversationSortKey

    class func withMatchedMembersSnippet(
        thread: ThreadViewModel,
        sortKey: ConversationSortKey,
        searchText: String,
        nameResolver: NameResolver,
        transaction: SDSAnyReadTransaction
    ) -> GroupSearchResult? {
        guard let groupThread = thread.threadRecord as? TSGroupThread else {
            owsFailDebug("Unexpected thread type")
            return nil
        }
        let matchedMembers = groupThread.sortedMemberNames(
            searchText: searchText,
            includingBlocked: true,
            nameResolver: nameResolver,
            transaction: transaction
        )
        let matchedMembersSnippet = matchedMembers.joined(separator: ", ")
        return GroupSearchResult(thread: thread, sortKey: sortKey, matchedMembersSnippet: matchedMembersSnippet)
    }

    init(thread: ThreadViewModel, sortKey: ConversationSortKey, matchedMembersSnippet: String? = nil) {
        self.thread = thread
        self.sortKey = sortKey
        self.matchedMembersSnippet = matchedMembersSnippet
    }

    // MARK: Comparable

    public static func < (lhs: GroupSearchResult, rhs: GroupSearchResult) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    // MARK: Equatable

    public static func == (lhs: GroupSearchResult, rhs: GroupSearchResult) -> Bool {
        return lhs.thread.threadRecord.uniqueId == rhs.thread.threadRecord.uniqueId
    }
}

// MARK: -

public class ComposeScreenSearchResultSet: Equatable {

    public let searchText: String

    public let groups: [GroupSearchResult]

    public var groupThreads: [TSGroupThread] {
        return groups.compactMap { $0.thread.threadRecord as? TSGroupThread }
    }

    public let signalContacts: [ContactSearchResult]

    public var signalAccounts: [SignalAccount] {
        return signalContacts.map { $0.signalAccount }
    }

    public init(searchText: String, groups: [GroupSearchResult], signalContacts: [ContactSearchResult]) {
        self.searchText = searchText
        self.groups = groups
        self.signalContacts = signalContacts
    }

    public static let empty = ComposeScreenSearchResultSet(searchText: "", groups: [], signalContacts: [])

    public var isEmpty: Bool {
        return groups.isEmpty && signalContacts.isEmpty
    }

    public var logDescription: String {
        var sections = [String]()
        if !groups.isEmpty {
            var splits = [String]()
            for group in groups {
                splits.append(group.thread.threadRecord.uniqueId)
            }
            sections.append("groups: " + splits.joined(separator: ","))
        }
        if !signalAccounts.isEmpty {
            var splits = [String]()
            for signalAccount in signalAccounts {
                splits.append(signalAccount.addressComponentsDescription)
            }
            sections.append("signalAccounts: " + splits.joined(separator: ","))
        }
        return "[" + sections.joined(separator: ",") + "]"
    }

    public static func == (lhs: ComposeScreenSearchResultSet, rhs: ComposeScreenSearchResultSet) -> Bool {
        guard lhs.searchText == rhs.searchText else { return false }
        guard lhs.groups == rhs.groups else { return false }
        guard lhs.signalAccounts == rhs.signalAccounts else { return false }
        return true
    }
}

// MARK: -

public class ConversationPickerScreenSearchResultSet: NSObject {

    public let searchText: String

    public let groups: [GroupSearchResult]

    public var groupThreads: [TSGroupThread] {
        return groups.compactMap { $0.thread.threadRecord as? TSGroupThread }
    }

    public let signalContacts: [ContactSearchResult]

    public var signalAccounts: [SignalAccount] {
        return signalContacts.map { $0.signalAccount }
    }

    /// Includes both group threads with stories, and private story threads.
    public let storyResults: [StorySearchResult]

    public var storyThreads: [TSThread] {
        return storyResults.map(\.thread)
    }

    public init(
        searchText: String,
        groups: [GroupSearchResult],
        storyThreads: [StorySearchResult],
        signalContacts: [ContactSearchResult]
    ) {
        self.searchText = searchText
        self.groups = groups
        self.storyResults = storyThreads
        self.signalContacts = signalContacts
    }

    public static let empty = ComposeScreenSearchResultSet(searchText: "", groups: [], signalContacts: [])

    public var isEmpty: Bool {
        return groups.isEmpty && signalContacts.isEmpty
    }

    public var logDescription: String {
        var sections = [String]()
        if !groups.isEmpty {
            var splits = [String]()
            for group in groups {
                splits.append(group.thread.threadRecord.uniqueId)
            }
            sections.append("groups: " + splits.joined(separator: ","))
        }
        if !signalAccounts.isEmpty {
            var splits = [String]()
            for signalAccount in signalAccounts {
                splits.append(signalAccount.addressComponentsDescription)
            }
            sections.append("signalAccounts: " + splits.joined(separator: ","))
        }
        return "[" + sections.joined(separator: ",") + "]"
    }
}

// MARK: -

public class MessageSearchResult: NSObject, Comparable {

    public let messageId: String
    public let sortId: UInt64

    init(messageId: String, sortId: UInt64) {
        self.messageId = messageId
        self.sortId = sortId
    }

    // MARK: - Comparable

    public static func < (lhs: MessageSearchResult, rhs: MessageSearchResult) -> Bool {
        return lhs.sortId < rhs.sortId
    }
}

// MARK: -

public class ConversationScreenSearchResultSet: NSObject {

    public let searchText: String

    public let messages: [MessageSearchResult]

    public lazy var messageSortIds: [UInt64] = {
        return messages.map { $0.sortId }
    }()

    // MARK: Static members

    public static let empty: ConversationScreenSearchResultSet = ConversationScreenSearchResultSet(searchText: "", messages: [])

    // MARK: Init

    public init(searchText: String, messages: [MessageSearchResult]) {
        self.searchText = searchText
        self.messages = messages
    }

    // MARK: - CustomDebugStringConvertible

    override public var debugDescription: String {
        return "ConversationScreenSearchResultSet(searchText: \(searchText), messages: [\(messages.count) matches])"
    }
}

public class FullTextSearcher: NSObject {

    public static let kDefaultMaxResults: UInt = 500

    public static let shared: FullTextSearcher = FullTextSearcher()

    public func searchForComposeScreen(
        searchText: String,
        omitLocalUser: Bool,
        maxResults: UInt = kDefaultMaxResults,
        transaction: SDSAnyReadTransaction
    ) -> ComposeScreenSearchResultSet {
        var signalContactMap = [SignalServiceAddress: ContactSearchResult]()
        var signalRecipentResults: [ContactSearchResult] = []
        var groups: [GroupSearchResult] = []

        var hasReachedMaxResults: Bool {
            guard (signalContactMap.count + signalRecipentResults.count + groups.count) < maxResults else { return true }
            return false
        }

        FullTextSearchFinder.enumerateObjects(
            searchText: searchText,
            collections: [
                SignalAccount.collection(),
                SignalRecipient.collection(),
                TSThread.collection()
            ],
            maxResults: maxResults,
            transaction: transaction
        ) { match, _, stop in
            guard !hasReachedMaxResults else {
                stop = true
                return
            }

            switch match {
            case let signalAccount as SignalAccount:
                let searchResult = ContactSearchResult(signalAccount: signalAccount, transaction: transaction)
                assert(signalContactMap[signalAccount.recipientAddress] == nil)
                signalContactMap[signalAccount.recipientAddress] = searchResult
            case let signalRecipient as SignalRecipient:
                guard signalRecipient.isRegistered else {
                    return
                }
                let signalAccount = SignalAccount.transientSignalAccount(forSignalRecipient: signalRecipient)
                let searchResult = ContactSearchResult(signalAccount: signalAccount, transaction: transaction)
                signalRecipentResults.append(searchResult)
            case let groupThread as TSGroupThread:
                let sortKey = ConversationSortKey(isContactThread: false,
                                                  creationDate: groupThread.creationDate,
                                                  lastInteractionRowId: groupThread.lastInteractionRowId)
                let threadViewModel = ThreadViewModel(thread: groupThread,
                                                      forChatList: true,
                                                      transaction: transaction)
                let searchResult = GroupSearchResult(thread: threadViewModel, sortKey: sortKey)
                groups.append(searchResult)
            case is TSContactThread:
                // not included in compose screen results
                break
            case is TSPrivateStoryThread:
                // not included in compose screen results
                break
            default:
                owsFailDebug("Unexpected match of type \(type(of: match))")
            }
        }

        // Fill in user matches from SignalRecipients, but only if
        // we don't already have a SignalAccount for the same user.
        for signalRecipentResult in signalRecipentResults {
            if signalContactMap[signalRecipentResult.recipientAddress] == nil {
                signalContactMap[signalRecipentResult.recipientAddress] = signalRecipentResult
            }
        }

        if let localAddress = TSAccountManager.localAddress {
            if matchesNoteToSelf(searchText: searchText, transaction: transaction) {
                if signalContactMap[localAddress] == nil {
                    let localAccount = SignalAccount(address: localAddress)
                    let localResult = ContactSearchResult(signalAccount: localAccount, transaction: transaction)
                    signalContactMap[localAddress] = localResult
                }
            }
        } else {
            owsFailDebug("localAddress was unexpectedly nil")
        }

        // Filter out contact results with pending message requests.
        var signalContacts = Array(signalContactMap.values).filter { (contactResult: ContactSearchResult) in
            !self.shouldFilterContactResult(contactResult: contactResult,
                                            omitLocalUser: omitLocalUser,
                                            transaction: transaction)
        }
        // Order contact results by display name.
        signalContacts.sort()

        // Order the conversation and message results in reverse chronological order.
        // The contact results are pre-sorted by display name.
        groups.sort(by: >)

        return ComposeScreenSearchResultSet(searchText: searchText, groups: groups, signalContacts: signalContacts)
    }

    public func searchForConversationPickerScreen(
        searchText: String,
        maxResults: UInt = kDefaultMaxResults,
        transaction: SDSAnyReadTransaction
    ) -> ConversationPickerScreenSearchResultSet {

        var signalContactMap = [SignalServiceAddress: ContactSearchResult]()
        var signalRecipentResults: [ContactSearchResult] = []
        var groups: [GroupSearchResult] = []
        var storyThreads: [StorySearchResult] = []

        var hasReachedMaxResults: Bool {
            guard (signalContactMap.count + signalRecipentResults.count + groups.count + storyThreads.count) < maxResults else { return true }
            return false
        }

        FullTextSearchFinder.enumerateObjects(
            searchText: searchText,
            collections: [
                SignalAccount.collection(),
                SignalRecipient.collection(),
                TSThread.collection()
            ],
            maxResults: maxResults,
            transaction: transaction
        ) { match, _, stop in
            guard !hasReachedMaxResults else {
                stop = true
                return
            }

            switch match {
            case let signalAccount as SignalAccount:
                let searchResult = ContactSearchResult(signalAccount: signalAccount, transaction: transaction)
                assert(signalContactMap[signalAccount.recipientAddress] == nil)
                signalContactMap[signalAccount.recipientAddress] = searchResult
            case let signalRecipient as SignalRecipient:
                guard signalRecipient.isRegistered else {
                    return
                }
                let signalAccount = SignalAccount.transientSignalAccount(forSignalRecipient: signalRecipient)
                let searchResult = ContactSearchResult(signalAccount: signalAccount, transaction: transaction)
                signalRecipentResults.append(searchResult)
            case let groupThread as TSGroupThread:
                let sortKey = ConversationSortKey(isContactThread: false,
                                                  creationDate: groupThread.creationDate,
                                                  lastInteractionRowId: groupThread.lastInteractionRowId)
                let threadViewModel = ThreadViewModel(thread: groupThread,
                                                      forChatList: true,
                                                      transaction: transaction)
                let searchResult = GroupSearchResult(thread: threadViewModel, sortKey: sortKey)
                groups.append(searchResult)

                if groupThread.isStorySendEnabled(transaction: transaction) {
                    let searchResult = StorySearchResult(thread: groupThread, sortKey: sortKey)
                    storyThreads.append(searchResult)
                }

            case let storyThread as TSPrivateStoryThread:
                guard storyThread.storyViewMode != .disabled else {
                    // Don't show disabled private story threads; these are queued up
                    // to be deleted.
                    break
                }
                let sortKey = ConversationSortKey(
                    isContactThread: false,
                    creationDate: storyThread.creationDate,
                    lastInteractionRowId: storyThread.lastInteractionRowId
                )
                let searchResult = StorySearchResult(thread: storyThread, sortKey: sortKey)
                storyThreads.append(searchResult)
            case is TSContactThread:
                // not included in compose screen results
                break
            default:
                owsFailDebug("Unexpected match of type \(type(of: match))")
            }
        }

        // Fill in user matches from SignalRecipients, but only if
        // we don't already have a SignalAccount for the same user.
        for signalRecipentResult in signalRecipentResults {
            if signalContactMap[signalRecipentResult.recipientAddress] == nil {
                signalContactMap[signalRecipentResult.recipientAddress] = signalRecipentResult
            }
        }

        if let localAddress = TSAccountManager.localAddress {
            if matchesNoteToSelf(searchText: searchText, transaction: transaction) {
                if signalContactMap[localAddress] == nil {
                    let localAccount = SignalAccount(address: localAddress)
                    let localResult = ContactSearchResult(signalAccount: localAccount, transaction: transaction)
                    signalContactMap[localAddress] = localResult
                }
            }
        } else {
            owsFailDebug("localAddress was unexpectedly nil")
        }

        // Filter out contact results with pending message requests.
        var signalContacts = Array(signalContactMap.values).filter { (contactResult: ContactSearchResult) in
            !self.shouldFilterContactResult(contactResult: contactResult,
                                            omitLocalUser: false,
                                            transaction: transaction)
        }
        // Order contact results by display name.
        signalContacts.sort()

        // Order the conversation and message results in reverse chronological order.
        // The contact results are pre-sorted by display name.
        groups.sort(by: >)

        return ConversationPickerScreenSearchResultSet(
            searchText: searchText,
            groups: groups,
            storyThreads: storyThreads,
            signalContacts: signalContacts
        )
    }

    func shouldFilterContactResult(contactResult: ContactSearchResult,
                                   omitLocalUser: Bool,
                                   transaction: SDSAnyReadTransaction) -> Bool {
        let address = contactResult.recipientAddress
        if address.isLocalAddress {
            return omitLocalUser
        }
        if self.contactsManager.isSystemContact(address: address, transaction: transaction) {
            return false
        }
        guard let thread = TSContactThread.getWithContactAddress(address, transaction: transaction) else {
            // Filter out users with whom we've never had contact.
            return true
        }
        return thread.hasPendingMessageRequest(transaction: transaction)
    }

    func matchesNoteToSelf(searchText: String, transaction: SDSAnyReadTransaction) -> Bool {
        guard let localAddress = TSAccountManager.localAddress else {
            return false
        }
        let noteToSelfText = self.conversationIndexingString(address: localAddress, transaction: transaction)
        let matchedTerm = searchText.split(separator: " ").first { term in
            return noteToSelfText.contains(term)
        }

        return matchedTerm != nil
    }

    public func searchForHomeScreen(
        searchText: String,
        maxResults: UInt = kDefaultMaxResults,
        isCanceled: () -> Bool,
        transaction: SDSAnyReadTransaction
    ) -> HomeScreenSearchResultSet? {
        var contactThreads: [ConversationSearchResult<ConversationSortKey>] = []
        var groupThreads: [GroupSearchResult] = []
        var groupThreadIds = Set<String>()
        var contactsMap: [SignalServiceAddress: ContactSearchResult] = [:]
        var messages: [UInt64: ConversationSearchResult<MessageSortKey>] = [:]

        var existingConversationAddresses: Set<SignalServiceAddress> = Set()

        let nameResolver = NameResolverImpl(contactsManager: contactsManager)

        var threadCache = [String: TSThread]()
        let getThread: (String) -> TSThread? = { threadUniqueId in
            if let thread = threadCache[threadUniqueId] {
                return thread
            }
            guard let thread = TSThread.anyFetch(uniqueId: threadUniqueId, transaction: transaction) else {
                return nil
            }
            threadCache[threadUniqueId] = thread
            return thread
        }

        var threadViewModelCache = [String: ThreadViewModel]()
        let getThreadViewModel: (TSThread) -> ThreadViewModel = { thread in
            if let threadViewModel = threadViewModelCache[thread.uniqueId] {
                return threadViewModel
            }
            let threadViewModel = ThreadViewModel(thread: thread,
                                                  forChatList: true,
                                                  transaction: transaction)
            threadViewModelCache[thread.uniqueId] = threadViewModel
            return threadViewModel
        }

        let getMentionedMessages: (SignalServiceAddress) -> [TSMessage] = { address in
            return MentionFinder.messagesMentioning(
                address: address,
                transaction: transaction.unwrapGrdbRead
            )
        }

        func appendMessage(_ message: TSMessage, snippet: CVTextValue?) {
            guard let thread = getThread(message.uniqueThreadId) else {
                owsFailDebug("Missing thread: \(type(of: message))")
                return
            }

            let threadViewModel = getThreadViewModel(thread)
            let sortKey = message.sortId
            let searchResult = ConversationSearchResult(
                thread: threadViewModel,
                sortKey: sortKey,
                messageId: message.uniqueId,
                messageDate: NSDate.ows_date(withMillisecondsSince1970: message.timestamp),
                snippet: snippet
            )
            guard messages[sortKey] == nil else { return }
            messages[sortKey] = searchResult
        }

        func appendSignalAccount(_ signalAccount: SignalAccount) {
            guard contactsMap[signalAccount.recipientAddress] == nil else { return }
            let searchResult = ContactSearchResult(signalAccount: signalAccount, transaction: transaction)
            contactsMap[searchResult.recipientAddress] = searchResult

            getMentionedMessages(signalAccount.recipientAddress)
                .forEach { message in
                    appendMessage(message, snippet: .messageBody(message.conversationListPreviewText(transaction)))
            }
        }

        var remainingAllowedResults: UInt {
            UInt(max(0, Int(maxResults) - (contactThreads.count + groupThreads.count + contactsMap.count + messages.count)))
        }

        var hasReachedMaxResults: Bool {
            guard remainingAllowedResults > 0 else { return true }
            return false
        }

        // We search for each type of result independently. The order here matters
        // – we want to give priority to chat and contact results above message
        // results. This makes sure if I search for a string like "Matthew" the
        // first results will be the chat with my contact named "Matthew", rather
        // than messages where his name was mentioned.

        // Check if we've been canceled before running the first query. If we have
        // to wait a while for the database to be available, this search may have
        // already been canceled.
        guard !isCanceled() else {
            return nil
        }

        FullTextSearchFinder.enumerateObjects(
            searchText: searchText,
            maxResults: remainingAllowedResults,
            transaction: transaction
        ) { (thread: TSThread, _, stop) in
            guard !isCanceled(), !hasReachedMaxResults else {
                stop = true
                return
            }

            // Ignore deleted threads.
            guard thread.shouldThreadBeVisible else { return }

            let threadViewModel = getThreadViewModel(thread)
            let sortKey = ConversationSortKey(
                isContactThread: thread is TSContactThread,
                creationDate: thread.creationDate,
                lastInteractionRowId: thread.lastInteractionRowId
            )

            switch thread {
            case is TSGroupThread:
                guard let searchResult = GroupSearchResult.withMatchedMembersSnippet(
                    thread: threadViewModel,
                    sortKey: sortKey,
                    searchText: searchText,
                    nameResolver: nameResolver,
                    transaction: transaction
                ) else {
                    return owsFailDebug("Unexpectedly failed to determine members snippet")
                }
                groupThreads.append(searchResult)
                groupThreadIds.insert(thread.uniqueId)
            case let contactThread as TSContactThread:
                let searchResult = ConversationSearchResult(thread: threadViewModel, sortKey: sortKey)
                existingConversationAddresses.insert(contactThread.contactAddress)
                contactThreads.append(searchResult)
            default:
                owsFailDebug("unexpected thread: \(type(of: thread))")
            }
        }

        guard !isCanceled() else {
            return nil
        }

        FullTextSearchFinder.enumerateObjects(
            searchText: searchText,
            maxResults: remainingAllowedResults,
            transaction: transaction
        ) { (groupMember: TSGroupMember, _, stop) in
            guard !isCanceled(), !hasReachedMaxResults else {
                stop = true
                return
            }

            guard !groupThreadIds.contains(groupMember.groupThreadId) else { return }
            guard let groupThread = TSGroupThread.anyFetchGroupThread(uniqueId: groupMember.groupThreadId, transaction: transaction) else {
                return owsFailDebug("Unexpectedly missing group thread for group member")
            }

            let threadViewModel = getThreadViewModel(groupThread)
            let sortKey = ConversationSortKey(
                isContactThread: false,
                creationDate: groupThread.creationDate,
                lastInteractionRowId: groupThread.lastInteractionRowId
            )

            guard let searchResult = GroupSearchResult.withMatchedMembersSnippet(
                thread: threadViewModel,
                sortKey: sortKey,
                searchText: searchText,
                nameResolver: nameResolver,
                transaction: transaction
            ) else {
                return owsFailDebug("Unexpectedly failed to determine members snippet")
            }

            groupThreads.append(searchResult)
            groupThreadIds.insert(groupThread.uniqueId)
        }

        guard !isCanceled() else {
            return nil
        }

        FullTextSearchFinder.enumerateObjects(
            searchText: searchText,
            maxResults: remainingAllowedResults,
            transaction: transaction
        ) { (account: SignalAccount, _, stop) in
            guard !isCanceled(), !hasReachedMaxResults else {
                stop = true
                return
            }
            appendSignalAccount(account)
        }

        guard !isCanceled() else {
            return nil
        }

        FullTextSearchFinder.enumerateObjects(
            searchText: searchText,
            maxResults: remainingAllowedResults,
            transaction: transaction
        ) { (recipient: SignalRecipient, _, stop) in
            guard !isCanceled(), !hasReachedMaxResults else {
                stop = true
                return
            }

            guard recipient.isRegistered else { return }

            let account = SignalAccount.transientSignalAccount(forSignalRecipient: recipient)
            appendSignalAccount(account)
        }

        guard !isCanceled() else {
            return nil
        }

        FullTextSearchFinder.enumerateObjects(
            searchText: searchText,
            maxResults: remainingAllowedResults,
            transaction: transaction
        ) { (message: TSMessage, snippet: String?, stop) in
            guard !isCanceled(), !hasReachedMaxResults else {
                stop = true
                return
            }
            let styledSnippet: CVTextValue? = { () -> CVTextValue? in
                guard let snippet else {
                    return nil
                }
                let attributeKey = NSAttributedString.Key("OWSSearchMatch")
                let matchStyle = BonMot.StringStyle(
                    .xmlRules([
                        .style(FullTextSearchFinder.matchTag, StringStyle(.extraAttributes([attributeKey: 0])))
                    ])
                )
                let matchStyleApplied = snippet.styled(with: matchStyle)
                var styles = [NSRangedValue<MessageBodyRanges.Style>]()
                matchStyleApplied.enumerateAttributes(in: matchStyleApplied.entireRange, using: { attrs, range, _ in
                    guard attrs[attributeKey] != nil else {
                        return
                    }
                    styles.append(NSRangedValue(.bold, range: range))
                })
                let mergedMessageBody: MessageBody
                if let messageBody = message.conversationListSearchResultsBody(transaction) {
                    mergedMessageBody = messageBody.mergeIntoFirstMatchOfStyledSubstring(matchStyleApplied.string, styles: styles)
                } else {
                    let singleStyles = styles.flatMap { style in
                        return style.value.contents.map {
                            return NSRangedValue($0, range: style.range)
                        }
                    }
                    mergedMessageBody = MessageBody(text: matchStyleApplied.string, ranges: .init(mentions: [:], styles: singleStyles))
                }
                return .messageBody(mergedMessageBody
                    .hydrating(mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: transaction.asV2Read)))
            }()
            appendMessage(message, snippet: styledSnippet)
        }

        guard !isCanceled() else {
            return nil
        }

        if matchesNoteToSelf(searchText: searchText, transaction: transaction) {
            if let localAddress = TSAccountManager.localAddress, contactsMap[localAddress] == nil {
                let localAccount = SignalAccount(address: localAddress)
                let localResult = ContactSearchResult(signalAccount: localAccount, transaction: transaction)
                contactsMap[localAddress] = localResult
            } else {
                owsFailDebug("localAddress was unexpectedly nil")
            }
        }

        // Only show contacts which were not included in an existing 1:1 conversation.
        var otherContacts: [ContactSearchResult] = contactsMap.values.filter {
            !existingConversationAddresses.contains($0.recipientAddress)
        }

        // Order the conversation and message results in reverse chronological order.
        // The contact results are pre-sorted by display name.
        contactThreads.sort(by: >)
        groupThreads.sort(by: >)
        let sortedMessages = messages.values.sorted(by: >)
        // Order "other" contact results by display name.
        otherContacts.sort()

        guard !isCanceled() else {
            return nil
        }

        return HomeScreenSearchResultSet(
            searchText: searchText,
            contactThreads: contactThreads,
            groupThreads: groupThreads,
            contacts: otherContacts,
            messages: sortedMessages
        )
    }

    public func searchWithinConversation(
        thread: TSThread,
        searchText: String,
        maxResults: UInt = kDefaultMaxResults,
        transaction: SDSAnyReadTransaction
    ) -> ConversationScreenSearchResultSet {
        var messages: [UInt64: MessageSearchResult] = [:]

        FullTextSearchFinder.enumerateObjects(
            searchText: searchText,
            collections: [
                TSMessage.collection(),
                SignalRecipient.collection()
            ],
            maxResults: maxResults,
            transaction: transaction
        ) { match, _, stop in
            guard messages.count < maxResults else {
                stop = true
                return
            }

            func appendMessage(_ message: TSMessage) {
                let messageId = message.uniqueId
                let searchResult = MessageSearchResult(messageId: messageId, sortId: message.sortId)
                messages[message.sortId] = searchResult
            }

            switch match {
            case let message as TSMessage:
                guard message.uniqueThreadId == thread.uniqueId else {
                    return
                }

                appendMessage(message)
            case let recipient as SignalRecipient:
                guard thread.recipientAddresses(with: transaction).contains(recipient.address) || recipient.address.isLocalAddress else {
                    return
                }
                let messagesMentioningAccount = MentionFinder.messagesMentioning(
                    address: recipient.address,
                    in: thread,
                    transaction: transaction.unwrapGrdbRead
                )
                messagesMentioningAccount.forEach { appendMessage($0) }
            default:
                owsFailDebug("Unexpected match of type \(type(of: match))")
            }
        }

        // We want most recent first
        let sortedMessages = messages.values.sorted(by: >)

        return ConversationScreenSearchResultSet(searchText: searchText, messages: sortedMessages)
    }

    // MARK: Filtering Signal accounts

    @objc(filterSignalAccounts:withSearchText:transaction:)
    public func filterSignalAccounts(_ signalAccounts: [SignalAccount], searchText: String, transaction: SDSAnyReadTransaction) -> [SignalAccount] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return signalAccounts
        }

        return signalAccounts.filter { signalAccount in
            self.signalAccountSearcher.matches(item: signalAccount, query: searchText, transaction: transaction)
        }
    }

    private lazy var signalAccountSearcher: Searcher<SignalAccount> = Searcher { (signalAccount: SignalAccount, transaction: SDSAnyReadTransaction) in
        let recipientAddress = signalAccount.recipientAddress
        return self.conversationIndexingString(address: recipientAddress, transaction: transaction)
    }

    private func conversationIndexingString(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        var result = self.indexingString(address: address, transaction: transaction)

        if address.isLocalAddress {
            result += " \(MessageStrings.noteToSelf)"
        }

        return result
    }

    private func indexingString(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        let displayName = contactsManager.displayName(for: address, transaction: transaction)

        return "\(address.phoneNumber ?? "") \(displayName)"
    }
}

// MARK: -

extension SignalAccount {
    public static func transientSignalAccount(forSignalRecipient signalRecipient: SignalRecipient) -> SignalAccount {
        SignalAccount(address: signalRecipient.address)
    }
}
