//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct ChatFolder: Equatable {
    public enum MembershipType: Int, Codable, Sendable {
        case included = 0
        case excluded = 1
    }

    let record: ChatFolderRecord

    public let includedThreadRowIds: Set<Int64>

    public let excludedThreadRowIds: Set<Int64>

    public var chatFolderId: UUID { record.chatFolderId }
    public var rowId: Int64 { record.id }
    public var folderType: ChatFolderRecord.FolderType { record.folderType }
    public var name: String { record.name }
    public var position: UInt32 { record.position }
    public var showOnlyUnread: Bool { record.showOnlyUnread }
    public var showMutedChats: Bool { record.showMutedChats }
    public var includeAllIndividualChats: Bool { record.includeAllIndividualChats }
    public var includeAllGroupChats: Bool { record.includeAllGroupChats }
    public var isDeleted: Bool { record.isDeleted }

    func contains(_ thread: ThreadFinder.InboxThread, nowMs: UInt64) -> Bool {
        if folderType == .all {
            return true
        }
        guard let threadType = TSThreadType(rawValue: thread.recordType) else {
            return false
        }
        if excludedThreadRowIds.contains(thread.id) {
            return false
        }
        if UInt64(bitPattern: thread.mutedUntilTimestamp) > nowMs, !showMutedChats {
            return false
        }
        if includedThreadRowIds.contains(thread.id) {
            return true
        }
        switch threadType {
        case .contactThread, .releaseNotesThread:
            return includeAllIndividualChats
        case .groupThread:
            return includeAllGroupChats
        case .thread, .privateStoryThread:
            return false
        }
    }

    public static let maxNameLength = 32

    public var displayName: String {
        switch folderType {
        case .all:
            return OWSLocalizedString(
                "CHAT_FOLDERS_ALL_CHATS",
                comment: "Name of the default chat folder, which shows every chat.",
            )
        case .custom:
            if let name = String(name.prefix(Self.maxNameLength)).filterForDisplay.nilIfEmpty {
                return name
            }
            return OWSLocalizedString(
                "CHAT_FOLDERS_UNNAMED_FOLDER",
                comment: "Name shown for a chat folder whose name is empty.",
            )
        }
    }

    public var contentsSummary: String? {
        guard folderType == .custom else {
            return nil
        }

        var parts = [String]()

        let chatTypeCount = (includeAllIndividualChats ? 1 : 0) + (includeAllGroupChats ? 1 : 0)
        if chatTypeCount > 0 {
            parts.append(String.localizedStringWithFormat(
                OWSLocalizedString(
                    "CHAT_FOLDERS_CHAT_TYPE_COUNT_%d",
                    tableName: "PluralAware",
                    comment: "Describes how many types of chats (1:1 chats, groups) a chat folder includes. Embeds {{ number of chat types }}.",
                ),
                chatTypeCount,
            ))
        }
        if !includedThreadRowIds.isEmpty {
            parts.append(String.localizedStringWithFormat(
                OWSLocalizedString(
                    "CHAT_FOLDERS_CHAT_COUNT_%d",
                    tableName: "PluralAware",
                    comment: "Describes how many chats were added to a chat folder. Embeds {{ number of chats }}.",
                ),
                includedThreadRowIds.count,
            ))
        }
        if !excludedThreadRowIds.isEmpty {
            parts.append(String.localizedStringWithFormat(
                OWSLocalizedString(
                    "CHAT_FOLDERS_EXCLUDED_CHAT_COUNT_%d",
                    tableName: "PluralAware",
                    comment: "Describes how many chats are excluded from a chat folder. Embeds {{ number of chats }}.",
                ),
                excludedThreadRowIds.count,
            ))
        }

        return parts.formatted(.list(type: .and, width: .narrow)).nilIfEmpty
    }
}

// MARK: -

public struct ChatFolderDraft: Equatable {
    public var name: String
    public var showOnlyUnread: Bool
    public var showMutedChats: Bool
    public var includeAllIndividualChats: Bool
    public var includeAllGroupChats: Bool
    public var includedThreadRowIds: Set<Int64>
    public var excludedThreadRowIds: Set<Int64>

    public init(
        name: String = "",
        showOnlyUnread: Bool = false,
        showMutedChats: Bool = true,
        includeAllIndividualChats: Bool = false,
        includeAllGroupChats: Bool = false,
        includedThreadRowIds: Set<Int64> = [],
        excludedThreadRowIds: Set<Int64> = [],
    ) {
        self.name = name
        self.showOnlyUnread = showOnlyUnread
        self.showMutedChats = showMutedChats
        self.includeAllIndividualChats = includeAllIndividualChats
        self.includeAllGroupChats = includeAllGroupChats
        self.includedThreadRowIds = includedThreadRowIds
        self.excludedThreadRowIds = excludedThreadRowIds
    }
}

extension ChatFolder {
    public var draft: ChatFolderDraft {
        return ChatFolderDraft(
            name: name,
            showOnlyUnread: showOnlyUnread,
            showMutedChats: showMutedChats,
            includeAllIndividualChats: includeAllIndividualChats,
            includeAllGroupChats: includeAllGroupChats,
            includedThreadRowIds: includedThreadRowIds,
            excludedThreadRowIds: excludedThreadRowIds,
        )
    }
}
