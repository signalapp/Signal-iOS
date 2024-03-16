//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

enum MessageBackupKeyMaterialError: Error {
    case invalidKeyInfo
    case missingMasterKey
    case notRegistered
    case invalidEncryptionKey
}

public protocol MessageBackupKeyMaterial {

    /// Backup ID material derived from a combination of the backup key and the
    /// local ACI.  This ID is used both as the salt for the backup encryption and
    /// to create the anonymous credentials for interacting with server stored backups
    func backupID(tx: DBReadTransaction) throws -> Data

    /// Builds an encrypting StreamTransform object derived from the backup master key and the backupID
    func createEncryptingStreamTransform(tx: DBReadTransaction) throws -> EncryptingStreamTransform
}
