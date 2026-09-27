//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class SecureValueRecoveryMock: SecureValueRecovery {

    public init() {}

    public func refreshBackupIfNecessary() async throws {
    }

    public func refreshCredentialsIfNecessary() async throws {
    }

    public var reglockToken: String?

    public var backUpMasterKeyMock: ((_ pin: String, _ masterKey: MasterKey, _ authMethod: SVR.AuthMethod) async throws -> Void)!

    public func backUpMasterKey(pin: String, masterKey: MasterKey, authMethod: SVR.AuthMethod) async throws {
        try await backUpMasterKeyMock(pin, masterKey, authMethod)
    }

    public var restoreKeysMock: ((_ pin: String, _ authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult>)?

    public func restoreKeys(pin: String, authMethod: SVR.AuthMethod) async -> SVR.RestoreKeysResult {
        return await restoreKeysMock!(pin, authMethod).awaitable()
    }

    public func invalidateBackupAttemptForEveryEnclave(tx: DBWriteTransaction) {
    }

    public var syncedMasterKey: MasterKey?

    public func storeKeys(
        fromKeysSyncMessage syncMessage: SSKProtoSyncMessageKeys,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction,
    ) throws(SVR.KeysError) {
        let aep = syncMessage.accountEntropyPool.flatMap({ try? AccountEntropyPool(key: $0) })
        guard let aep else {
            throw .missingAep
        }
        syncedMasterKey = aep.getMasterKey()
    }

    public func storeKeys(
        fromProvisioningMessage provisioningMessage: LinkingProvisioningMessage,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction,
    ) {
        syncedMasterKey = provisioningMessage.aep.getMasterKey()
    }

    public var doesHavePendingRestoration = false

    public func hasPendingRestoration(transaction: DBReadTransaction) -> Bool {
        return doesHavePendingRestoration
    }

    public func recordPendingRestoration(transaction: DBWriteTransaction) {
        doesHavePendingRestoration = true
    }

    public func clearPendingRestoration(transaction: DBWriteTransaction) {
        doesHavePendingRestoration = false
    }
}

#endif
