//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class SecureValueRecoveryMock: SecureValueRecovery {

    public var hasAccountEntropyPool = false
    public func hasAccountEntropyPool(transaction: any DBReadTransaction) -> Bool {
        return hasAccountEntropyPool
    }

    public init() {}

    public var hasMasterKey = false

    public var hasBackedUpMasterKey: Bool = false

    public func hasBackedUpMasterKey(transaction: DBReadTransaction) -> Bool {
        return hasBackedUpMasterKey
    }

    public func hasMasterKey(transaction: DBReadTransaction) -> Bool {
        return hasMasterKey
    }

    public var currentPinType: SVR.PinType?

    public func currentPinType(transaction: DBReadTransaction) -> SVR.PinType? {
        return currentPinType
    }

    public var verifyPinHandler: (String) -> Bool = { _ in return true }

    public func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        resultHandler(verifyPinHandler(pin))
    }

    public var reglockToken: String?

    public var backupMasterKeyMock: ((_ pin: String, _ masterKey: MasterKey, _ authMethod: SVR.AuthMethod) -> Promise<MasterKey>)?

    public func backupMasterKey(pin: String, masterKey: MasterKey, authMethod: SVR.AuthMethod) -> Promise<MasterKey> {
        return backupMasterKeyMock!(pin, masterKey, authMethod)
    }

    public var restoreKeysMock: ((_ pin: String, _ authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult>)?

    public func restoreKeys(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult> {
        return restoreKeysMock!(pin, authMethod)
    }

    public var restoreKeysAndBackupMock: ((_ pin: String, _ authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult>)?

    public func restoreKeysAndBackup(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult> {
        return restoreKeysAndBackupMock!(pin, authMethod)
    }

    public func deleteKeys() -> Promise<Void> {
        return .value(())
    }

    public func warmCaches() {
        // Do nothing
    }

    public func clearKeys(transaction: DBWriteTransaction) {
        hasMasterKey = false
    }

    public var syncedMasterKey: Data?

    public func storeKeys(
        fromKeysSyncMessage syncMessage: SSKProtoSyncMessageKeys,
        authedDevice: AuthedDevice,
        tx: any DBWriteTransaction
    ) throws(SVR.KeysError) {
        syncedMasterKey = syncMessage.master
    }

    public func storeKeys(
        fromProvisioningMessage provisioningMessage: ProvisionMessage,
        authedDevice: AuthedDevice,
        tx: DBWriteTransaction
    ) throws(SVR.KeysError) {
        syncedMasterKey = provisioningMessage.masterKey
    }

    public var hasHadBackupKeyRequestFail = false

    public func hasBackupKeyRequestFailed(transaction: DBReadTransaction) -> Bool {
        return hasHadBackupKeyRequestFail
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

    public var useDeviceLocalMasterKeyMock: ((_ authedAccount: AuthedAccount) -> Void)?

    public func useDeviceLocalMasterKey(
        _ masterKey: MasterKey,
        disablePIN: Bool,
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
        useDeviceLocalMasterKeyMock?(authedAccount)
        hasMasterKey = true
    }

    public var useDeviceLocalAccountEntropyPoolMock: ((_ authedAccount: AuthedAccount) -> Void)?
    public func useDeviceLocalAccountEntropyPool(
        _ accountEntropyPool: AccountEntropyPool,
        disablePIN: Bool,
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
        useDeviceLocalAccountEntropyPoolMock?(authedAccount)
        hasAccountEntropyPool = true
        hasMasterKey = true
    }
}

#endif
