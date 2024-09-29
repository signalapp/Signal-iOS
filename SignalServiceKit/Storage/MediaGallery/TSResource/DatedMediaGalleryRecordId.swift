//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct DatedMediaGalleryRecordId: Codable, FetchableRecord {
    public var rowid: Int64 // sqlite row id of the MediaGalleryRecord
    public var receivedAtTimestamp: UInt64 // timestamp in milliseconds

    public var date: Date {
        return Date(millisecondsSince1970: receivedAtTimestamp)
    }

    public init(rowid: Int64, receivedAtTimestamp: UInt64) {
        self.rowid = rowid
        self.receivedAtTimestamp = receivedAtTimestamp
    }
}

extension DatedMediaGalleryRecordId {

    var asItemId: DatedMediaGalleryItemId {
        return .init(id: .legacy(mediaGalleryRecordId: rowid), receivedAtTimestamp: receivedAtTimestamp)
    }
}
