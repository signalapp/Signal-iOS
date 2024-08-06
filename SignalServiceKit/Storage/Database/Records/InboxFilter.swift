//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// An enumeration describing ways that the inbox (i.e., the main chat list)
/// can be filtered.
public enum InboxFilter: Int, Hashable, Sendable {
    /// Don't filter the inbox.
    case none = 0

    /// Include only chats that have unread messages, or are explicitly marked unread.
    case unread = 1
}
