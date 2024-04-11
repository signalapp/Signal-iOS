//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct MediaGalleryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "media_gallery_items"

    let attachmentId: Int64
    let albumMessageId: Int64
    let threadId: Int64
    let originalAlbumOrder: Int
}
