//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol UploadMetadata {
    /// File URL of the data consisting of "iv  + encrypted data + hmac"
    var fileUrl: URL { get }

    /// The digest of the encrypted file.  The encrypted file consist of "iv + encrypted data + hmac"
    var digest: Data { get }

    /// The length of the encrypted data, consiting of "iv  + encrypted data + hmac"
    var encryptedDataLength: UInt32 { get }

    /// The length of the unencrypted data
    var plaintextDataLength: UInt32 { get }
}
