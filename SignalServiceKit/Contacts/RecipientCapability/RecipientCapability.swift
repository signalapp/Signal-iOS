//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Capabilities we track for recipients.
///
/// The raw value is the key the server returns.
public enum RecipientCapability: String, CaseIterable {

    /// A dummy capability that keeps this enum non-empty. If it were
    /// empty, the compiler would complain about some important code
    /// being unused... which is true! But, we want to keep it around for the
    /// future, when we may add new capabilities. We keep this around even
    /// if there are other capabilities below because those might be retired
    /// and removed before we add any new ones.
    case dummy

    case adminRemoveAndDelete

    case usernameChangeSyncMessage

    /// Whether or not to persist this in the RecipientCapability table.
    var isStoredPerRecipient: Bool {
        switch self {
        case .adminRemoveAndDelete: true
        case .dummy: false
        case .usernameChangeSyncMessage: false
        }
    }
}
