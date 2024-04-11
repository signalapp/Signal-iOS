//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct DatedMediaGalleryItemId {
    public var id: MediaGalleryItemId
    public var receivedAtTimestamp: UInt64 // timestamp in milliseconds

    public var date: Date {
        return Date(millisecondsSince1970: receivedAtTimestamp)
    }

    public init(id: MediaGalleryItemId, receivedAtTimestamp: UInt64) {
        self.id = id
        self.receivedAtTimestamp = receivedAtTimestamp
    }
}

extension DatedAttachmentReferenceId {

    var asItemId: DatedMediaGalleryItemId {
        return .init(id: .v2(id), receivedAtTimestamp: receivedAtTimestamp)
    }
}
