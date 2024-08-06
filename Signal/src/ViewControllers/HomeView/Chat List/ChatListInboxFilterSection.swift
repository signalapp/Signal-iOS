//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// View model describing the current state of the inbox filter footer.
struct ChatListInboxFilterSection: Hashable, Identifiable {
    let id = ChatListSectionType.inboxFilterFooter
    var isEmptyState: Bool

    var message: String? {
        guard isEmptyState else { return nil }
        return OWSLocalizedString("CHAT_LIST_UNREAD_FILTER_NO_CHATS", comment: "Message displayed on chat list when Filter by Unread is enabled but no unread chats are available")
    }

    init?(renderState: CLVRenderState) {
        guard renderState.viewInfo.inboxFilter != .none else { return nil }
        isEmptyState = renderState.visibleThreadCount == 0
    }
}
