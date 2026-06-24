//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public struct ReleaseNoteStore {
    public init() {}

    public func existingReleaseNoteForManifestId(_ manifestId: String, tx: DBReadTransaction) -> StoredReleaseNote? {
        failIfThrows {
            try StoredReleaseNote
                .fetchOne(tx.database, key: manifestId)
        }
    }

    public func existingReleaseNoteForInteractionId(_ interactionId: Int64, tx: DBReadTransaction) -> StoredReleaseNote? {
        failIfThrows {
            try StoredReleaseNote
                .filter(Column(StoredReleaseNote.CodingKeys.interactionId.rawValue) == interactionId)
                .fetchOne(tx.database)
        }
    }

    public func storeReleaseNote(
        uniqueId: String,
        interactionId: Int64?,
        ctaText: String?,
        callToActionId: String?,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try StoredReleaseNote(
                uniqueId: uniqueId,
                interactionId: interactionId,
                ctaId: callToActionId,
                ctaText: ctaText,
            ).insert(tx.database)
        }
    }
}
