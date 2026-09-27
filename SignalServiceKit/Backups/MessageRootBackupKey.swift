//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct MessageRootBackupKey: BackupKeyMaterial {
    public var credentialType: BackupAuthCredentialType { .messages }
    public let backupKey: BackupKey
    public let backupId: Data

    public let aci: Aci
    public let loggingKey: String

    public init(accountEntropyPool: AccountEntropyPool, aci: Aci) {
        let backupKey = accountEntropyPool.getBackupKey()
        self.init(backupKey: backupKey, aci: aci, loggingKey: accountEntropyPool.getLoggingKey())
    }

    init(backupKey: BackupKey, aci: Aci, loggingKey: String = "") {
        self.backupKey = backupKey
        self.backupId = backupKey.deriveBackupId(aci: aci)
        self.aci = aci
        self.loggingKey = loggingKey
    }
}
