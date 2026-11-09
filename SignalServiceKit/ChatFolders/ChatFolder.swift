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
}
