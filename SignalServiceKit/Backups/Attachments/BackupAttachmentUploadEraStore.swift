//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// The "era" for a Backup Attachment upload identifies when it was uploaded to
/// the media tier, relative to events that might require us to reupload it.
///
/// The upload era should rotate whenever something happens such that we may
/// need to (re-)upload backup media. Rotating the upload era causes us to run
/// list-media, and thereby learn about any media needing upload.
public struct BackupAttachmentUploadEraStore {
    private enum StoreKeys {
        static let currentUploadEra = "currentUploadEra"
    }

    private let kvStore: KeyValueStore

    public init() {
        self.kvStore = KeyValueStore(collection: "BackupUploadEraStore")
    }

    /// The current upload era for Backup Attachments. Attachments not matching
    /// this upload era may need to be reuploaded.
    public func currentUploadEra(tx: DBReadTransaction) -> String {
        if let persisted = kvStore.getString(StoreKeys.currentUploadEra, transaction: tx) {
            return persisted
        }

        return "initialUploadEra"
    }

    /// Rotate the current upload era. This implicitly "marks" attachments from
    /// prior eras as potentially needing to be reuploaded.
    public func rotateUploadEra(tx: DBWriteTransaction) {
        kvStore.setString(
            Randomness.generateRandomBytes(32).base64EncodedString(),
            key: StoreKeys.currentUploadEra,
            transaction: tx,
        )
    }
}
