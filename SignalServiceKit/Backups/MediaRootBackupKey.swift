//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum MediaTierEncryptionType: CaseIterable {
    case outerLayerFullsizeOrThumbnail
    case transitTierThumbnail
}

public struct MediaTierEncryptionMetadata: Equatable {
    let type: MediaTierEncryptionType
    let mediaId: Data
    let hmacKey: Data
    let aesKey: Data

    func attachmentKey() throws -> AttachmentKey {
        return try AttachmentKey(combinedKey: aesKey + hmacKey)
    }
}

public struct MediaRootBackupKey: BackupKeyMaterial {
    public var credentialType: BackupAuthCredentialType { .media }
    public var backupKey: BackupKey

    public init(backupKey: BackupKey) {
        self.backupKey = backupKey
    }

    public func deriveMediaId(_ mediaName: String) -> Data {
        return failIfThrows {
            return try backupKey.deriveMediaId(mediaName)
        }
    }

    public func mediaEncryptionMetadata(
        mediaName: String,
        type: MediaTierEncryptionType,
    ) -> MediaTierEncryptionMetadata {
        let mediaId = self.deriveMediaId(mediaName)
        let keyBytes: Data
        switch type {
        case .outerLayerFullsizeOrThumbnail:
            keyBytes = failIfThrows { try backupKey.deriveMediaEncryptionKey(mediaId) }
        case .transitTierThumbnail:
            keyBytes = failIfThrows { try backupKey.deriveThumbnailTransitEncryptionKey(mediaId) }
        }
        owsPrecondition(keyBytes.count >= 64)
        return MediaTierEncryptionMetadata(
            type: type,
            mediaId: mediaId,
            hmacKey: keyBytes.prefix(32),
            aesKey: keyBytes.dropFirst(32).prefix(32),
        )
    }
}
