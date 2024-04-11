//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct DatedAttachmentReferenceId {
    public let id: AttachmentReferenceId
    // timestamp of the owning message.
    public let receivedAtTimestamp: UInt64

    public var date: Date {
        return Date(millisecondsSince1970: receivedAtTimestamp)
    }

    public init(id: AttachmentReferenceId, receivedAtTimestamp: UInt64) {
        self.id = id
        self.receivedAtTimestamp = receivedAtTimestamp
    }
}
