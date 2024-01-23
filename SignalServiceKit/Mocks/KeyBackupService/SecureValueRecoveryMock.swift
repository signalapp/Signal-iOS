//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class SecureValueRecoveryMock: SecureValueRecovery {

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

    public func acquireRegistrationLockForNewNumber(with pin: String, and auth: SVRAuthCredential) -> Promise<String> {
        return .value(reglockToken!)
    }

    public var generateAndBackupKeysMock: ((_ pin: String, _ authMethod: SVR.AuthMethod) -> Promise<Void>)?

    public func generateAndBackupKeys(pin: String, authMethod: SVR.AuthMethod) -> Promise<Void> {
        return generateAndBackupKeysMock!(pin, authMethod)
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

    public func encrypt(
        keyType: SVR.DerivedKey,
        data: Data,
        transaction: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        return .success(data)
    }

    public func decrypt(
        keyType: SVR.DerivedKey,
        encryptedData: Data,
        transaction: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        return .success(encryptedData)
    }

    public func warmCaches() {
        // Do nothing
    }

    public func clearKeys(transaction: DBWriteTransaction) {
        hasMasterKey = false
    }

    public func storeSyncedStorageServiceKey(
        data: Data?,
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
        // Do nothing
    }

    public var syncedMasterKey: Data?

    public func storeSyncedMasterKey(
        data: Data,
        authedDevice: AuthedDevice,
        updateStorageService: Bool,
        transaction: DBWriteTransaction
    ) {
        syncedMasterKey = data
    }

    public func masterKeyDataForKeysSyncMessage(tx: DBReadTransaction) -> Data? {
        return nil
    }

    public func clearSyncedStorageServiceKey(transaction: DBWriteTransaction) {
        // Do nothing
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
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
        useDeviceLocalMasterKeyMock?(authedAccount)
    }

    public var dataGenerator: (SVR.DerivedKey) -> Data? = { _ in return nil }

    public func data(for key: SVR.DerivedKey) -> Data? {
        return dataGenerator(key)
    }

    public func data(for key: SVR.DerivedKey, transaction: DBReadTransaction) -> SVR.DerivedKeyData? {
        return SVR.DerivedKeyData(dataGenerator(key), key)
    }

    public func isKeyAvailable(_ key: SVR.DerivedKey, transaction: DBReadTransaction) -> Bool {
        return true
    }
}

#endif
