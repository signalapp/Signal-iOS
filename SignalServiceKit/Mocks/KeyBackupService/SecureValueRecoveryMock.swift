//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class SecureValueRecoveryMock: SecureValueRecovery {

    public init() {}

    public var hasMasterKey = false

    public var currentEnclave: KeyBackupEnclave = .init(
        name: "",
        mrenclave: .init("8888888888888888888888888888888888888888888888888888888888888888"),
        serviceId: ""
    )

    public var hasBackedUpMasterKey: Bool = false

    public func hasBackedUpMasterKey(transaction: DBReadTransaction) -> Bool {
        return hasBackedUpMasterKey
    }

    public func hasMasterKey(transaction: DBReadTransaction) -> Bool {
        return hasMasterKey
    }

    public var currentPinType: SVR.PinType?

    public var verifyPinHandler: (String) -> Bool = { _ in return true }

    public func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        resultHandler(verifyPinHandler(pin))
    }

    public var reglockToken: String?

    public func acquireRegistrationLockForNewNumber(with pin: String, and auth: KBSAuthCredential) -> Promise<String> {
        return .value(reglockToken!)
    }

    public func generateAndBackupKeys(with pin: String, rotateMasterKey: Bool) -> AnyPromise {
        return AnyPromise(Promise<Void>.value(()))
    }

    public var generateAndBackupKeysMock: ((_ pin: String, _ authMethod: SVR.AuthMethod, _ rotateMasterKey: Bool) -> Promise<Void>)?

    public func generateAndBackupKeys(with pin: String, rotateMasterKey: Bool) -> Promise<Void> {
        return generateAndBackupKeysMock!(pin, .implicit, rotateMasterKey)
    }

    public func generateAndBackupKeys(pin: String, authMethod: SVR.AuthMethod, rotateMasterKey: Bool) -> Promise<Void> {
        return generateAndBackupKeysMock!(pin, authMethod, rotateMasterKey)
    }

    public func restoreKeysAndBackup(with pin: String, and auth: KBSAuthCredential?) -> Promise<Void> {
        fatalError("Unimplemented")
    }

    public var restoreKeysAndBackupMock: ((_ pin: String, _ authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult>)?

    public func restoreKeysAndBackup(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult> {
        return restoreKeysAndBackupMock!(pin, authMethod)
    }

    public func deleteKeys() -> Promise<Void> {
        return .value(())
    }

    public func encrypt(keyType: SVR.DerivedKey, data: Data) throws -> Data {
        return data
    }

    public func decrypt(keyType: SVR.DerivedKey, encryptedData: Data) throws -> Data {
        return encryptedData
    }

    public func deriveRegistrationLockToken() -> String? {
        return reglockToken
    }

    public func deriveRegistrationLockToken(transaction: DBReadTransaction) -> String? {
        return reglockToken
    }

    public func warmCaches() {
        // Do nothing
    }

    public func clearKeys(transaction: DBWriteTransaction) {
        hasMasterKey = false
    }

    public func storeSyncedKey(
        type: SVR.DerivedKey,
        data: Data?,
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
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

    public func setMasterKeyBackedUp(_ value: Bool, transaction: DBWriteTransaction) {
        hasBackedUpMasterKey = true
    }

    public func useDeviceLocalMasterKey(
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
        // Do nothing
    }

    public var dataGenerator: (SVR.DerivedKey) -> Data? = { _ in return nil }

    public func data(for key: SVR.DerivedKey) -> Data? {
        return dataGenerator(key)
    }

    public func data(for key: SVR.DerivedKey, transaction: DBReadTransaction) -> Data? {
        return dataGenerator(key)
    }

    public func isKeyAvailable(_ key: SVR.DerivedKey) -> Bool {
        return true
    }
}

#endif
