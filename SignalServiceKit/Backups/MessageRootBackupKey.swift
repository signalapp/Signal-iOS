//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct MessageRootBackupKey: BackupKeyMaterial {
    public var credentialType: BackupAuthCredentialType { .messages }
    public let backupKey: BackupKey
    public let messageBackupKey: LibSignalClient.MessageBackupKey

    public let aci: Aci

    public var aesKey: Data { messageBackupKey.aesKey }

    public var hmacKey: Data { messageBackupKey.hmacKey }

    public init(accountEntropyPool: AccountEntropyPool, aci: Aci) throws(BackupKeyMaterialError) {
        do {
            let backupKey = try LibSignalClient.AccountEntropyPool.deriveBackupKey(accountEntropyPool.rawData)
            try self.init(backupKey: backupKey, aci: aci)
        } catch {
            throw BackupKeyMaterialError.derivationError(error)
        }
    }

    init(data: Data, aci: Aci) throws(BackupKeyMaterialError) {
        do {
            let backupKey = try BackupKey(contents: data)
            try self.init(backupKey: backupKey, aci: aci)
        } catch {
            throw BackupKeyMaterialError.derivationError(error)
        }
    }

    private init(backupKey: BackupKey, aci: Aci) throws {
        self.backupKey = backupKey
        self.messageBackupKey = try MessageBackupKey(
            backupKey: backupKey,
            backupId: backupKey.deriveBackupId(aci: aci)
        )
        self.aci = aci
    }
}
