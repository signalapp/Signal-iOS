//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Applies to attachment uploads, backup proto uploads, etc.
public protocol UploadMetadata {
    /// The digest of the encrypted file.  The encrypted file consist of "iv + encrypted data + hmac"
    var digest: Data { get }

    /// The length of the unencrypted data
    var plaintextDataLength: UInt32 { get }
}

/// Specifically an upload of an attachment.
public protocol AttachmentUploadMetadata: UploadMetadata {
    /// encryption key + hmac
    var key: Data { get }

    /// True if the upload represents the reuse of an existing transit tier upload
    /// with metadata we had stored locally on disk.
    var isReusedTransitTierUpload: Bool { get }
}
