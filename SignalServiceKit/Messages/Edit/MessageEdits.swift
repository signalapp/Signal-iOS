//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A set of changes to the prior revision of a message when appying an edit.
///
/// Excluding attachment-related edits, this is a complete set of what is
/// _allowed_ to be edited and how it is edited.
public struct MessageEdits {
    public enum Edit<T> {
        case keep
        case change(T)
    }

    /// We always apply the new timestamp; you can't "keep" the old one.
    public let timestamp: UInt64

    public let body: Edit<String?>
    public let bodyRanges: Edit<MessageBodyRanges?>

    public init(
        timestamp: UInt64,
        body: Edit<String?>,
        bodyRanges: Edit<MessageBodyRanges?>
    ) {
        self.timestamp = timestamp
        self.body = body
        self.bodyRanges = bodyRanges
    }
}

extension MessageEdits.Edit {

    func unwrap(keepValue: T) -> T {
        switch self {
        case .keep:
            return keepValue
        case .change(let t):
            return t
        }
    }
}
