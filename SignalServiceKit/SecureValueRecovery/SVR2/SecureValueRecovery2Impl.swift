//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Implementation of `SecureValueRecovery` that talks to the SVR2 server.
public class SecureValueRecovery2Impl: SecureValueRecovery {

    private let localStorage: SVRLocalStorage

    public init(
        keyValueStoreFactory: KeyValueStoreFactory
    ) {
        self.localStorage = SVRLocalStorage(keyValueStoreFactory: keyValueStoreFactory)
    }

    public func warmCaches() {
        fatalError("Unimplemented!")
    }

    // MARK: - Key Existence

    public func hasMasterKey(transaction: DBReadTransaction) -> Bool {
        return localStorage.getMasterKey(transaction) != nil
    }

    public func hasBackedUpMasterKey(transaction: DBReadTransaction) -> Bool {
        return localStorage.getIsMasterKeyBackedUp(transaction)
    }

    public func setMasterKeyBackedUp(_ value: Bool, transaction: DBWriteTransaction) {
        localStorage.setIsMasterKeyBackedUp(value, transaction)
    }

    public func useDeviceLocalMasterKey(authedAccount: AuthedAccount, transaction: DBWriteTransaction) {
        fatalError("Unimplemented!")
    }

    // MARK: - PIN Management

    public func currentPinType(transaction: DBReadTransaction) -> SVR.PinType? {
        return localStorage.getPinType(transaction)
    }

    public func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        fatalError("Unimplemented!")
    }

    // MARK: - Key Management

    public func acquireRegistrationLockForNewNumber(with pin: String, and auth: SVRAuthCredential) -> Promise<String> {
        fatalError("Unimplemented!")
    }

    public func generateAndBackupKeys(pin: String, authMethod: SVR.AuthMethod, rotateMasterKey: Bool) -> Promise<Void> {
        fatalError("Unimplemented!")
    }

    public func restoreKeysAndBackup(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult> {
        fatalError("Unimplemented!")
    }

    public func deleteKeys() -> Promise<Void> {
        fatalError("Unimplemented!")
    }

    public func clearKeys(transaction: DBWriteTransaction) {
        fatalError("Unimplemented!")
    }

    // MARK: - Master Key Encryption

    public func encrypt(keyType: SVR.DerivedKey, data: Data) -> SVR.DerivedKeyResult {
        fatalError("Unimplemented!")
    }

    public func decrypt(keyType: SVR.DerivedKey, encryptedData: Data) -> SVR.DerivedKeyResult {
        fatalError("Unimplemented!")
    }

    public func storeSyncedStorageServiceKey(data: Data?, authedAccount: AuthedAccount, transaction: DBWriteTransaction) {
        fatalError("Unimplemented!")
    }

    // MARK: - Value Derivation

    public func deriveRegistrationLockToken(transaction: DBReadTransaction) -> String? {
        fatalError("Unimplemented!")
    }

    public func data(for key: SVR.DerivedKey, transaction: DBReadTransaction) -> Data? {
        fatalError("Unimplemented!")
    }

    public func isKeyAvailable(_ key: SVR.DerivedKey, transaction: DBReadTransaction) -> Bool {
        fatalError("Unimplemented!")
    }
}
