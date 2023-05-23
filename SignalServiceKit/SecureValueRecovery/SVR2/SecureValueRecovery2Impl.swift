//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Implementation of `SecureValueRecovery` that talks to the SVR2 server.
public class SecureValueRecovery2Impl: SecureValueRecovery {

    private let credentialStorage: SVRAuthCredentialStorage
    private let db: DB
    private let localStorage: SVRLocalStorage
    private let schedulers: Schedulers
    private let storageServiceManager: StorageServiceManager
    private let syncManager: SyncManagerProtocolSwift
    private let tsAccountManager: SVR.Shims.TSAccountManager
    private let twoFAManager: SVR.Shims.OWS2FAManager

    public init(
        credentialStorage: SVRAuthCredentialStorage,
        db: DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        schedulers: Schedulers,
        storageServiceManager: StorageServiceManager,
        syncManager: SyncManagerProtocolSwift,
        tsAccountManager: SVR.Shims.TSAccountManager,
        twoFAManager: SVR.Shims.OWS2FAManager
    ) {
        self.credentialStorage = credentialStorage
        self.db = db
        self.localStorage = SVRLocalStorage(keyValueStoreFactory: keyValueStoreFactory)
        self.schedulers = schedulers
        self.storageServiceManager = storageServiceManager
        self.syncManager = syncManager
        self.tsAccountManager = tsAccountManager
        self.twoFAManager = twoFAManager
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
        setLocalDataAndSyncStorageServiceIfNeeded(
            masterKey: Cryptography.generateRandomBytes(SVR.masterKeyLengthBytes),
            isMasterKeyBackedUp: false,
            pinType: .alphanumeric,
            encodedPINVerificationString: nil,
            enclaveName: nil,
            authedAccount: authedAccount,
            transaction: transaction
        )
        // Disable the PIN locally.
        twoFAManager.markDisabled(transaction: transaction)

        // Wipe credentials; they're now useless.
        credentialStorage.removeSVR2CredentialsForCurrentUser(transaction)

        // TODO: wipe tokens and any in progress SVR backups; they're now useless.

        // We should update account attributes so we wipe the reglock and
        // reg recovery password.
        tsAccountManager.scheduleAccountAttributesUpdate(authedAccount: authedAccount, transaction: transaction)
    }

    // MARK: - PIN Management

    public func currentPinType(transaction: DBReadTransaction) -> SVR.PinType? {
        return localStorage.getPinType(transaction)
    }

    public func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        // Kick off to a background thread to do expensive cryptography operations.
        schedulers.global().async { [schedulers, localStorage, db] in
            var isValid = false
            defer {
                schedulers.main.async { resultHandler(isValid) }
            }

            guard let encodedVerificationString = db.read(block: { tx in
                localStorage.getEncodedPINVerificationString(tx)
            }) else {
                owsFailDebug("Attempted to verify pin locally when we don't have a verification string")
                return
            }

            isValid = SVRUtil.verifyPIN(pin: pin, againstEncodedPINVerificationString: encodedVerificationString)
        }
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
        // TODO: wipe tokens and any in progress SVR backups
        localStorage.clearKeys(transaction)
    }

    // MARK: - Master Key Encryption

    public func encrypt(
        keyType: SVR.DerivedKey,
        data: Data,
        transaction: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        guard let keyData = self.data(for: keyType, transaction: transaction) else {
            return .masterKeyMissing
        }
        do {
            return .success(try Aes256GcmEncryptedData.encrypt(data, key: keyData.rawData).concatenate())
        } catch let error {
            return .cryptographyError(error)
        }
    }

    public func decrypt(
        keyType: SVR.DerivedKey,
        encryptedData: Data,
        transaction: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        guard let keyData = self.data(for: keyType, transaction: transaction) else {
            return .masterKeyMissing
        }
        do {
            return .success(try Aes256GcmEncryptedData(concatenated: encryptedData).decrypt(key: keyData.rawData))
        } catch let error {
            return .cryptographyError(error)
        }
    }

    public func storeSyncedStorageServiceKey(data: Data?, authedAccount: AuthedAccount, transaction: DBWriteTransaction) {
        localStorage.setSyncedStorageServiceKey(data, transaction)

        // Trigger a re-fetch of the storage manifest, our keys have changed
        if data != nil {
            storageServiceManager.restoreOrCreateManifestIfNecessary(authedAccount: authedAccount)
        }
    }

    // MARK: - Value Derivation

    public func data(for key: SVR.DerivedKey, transaction: DBReadTransaction) -> SVR.DerivedKeyData? {
        // If we are a linked device, we don't have the master key. But we might
        // have the storage service derived key in local storage, which we got from
        // a sync message. Check for that first.
        if key == .storageService, let data = localStorage.getSyncedStorageServiceKey(transaction) {
            return SVR.DerivedKeyData(data, .storageService)
        }

        guard let rootKeyData = rootKeyData(for: key, transaction: transaction) else {
            return nil
        }
        return SVR.DerivedKeyData(key.derivedData(from: rootKeyData), key)
    }

    public func isKeyAvailable(_ key: SVR.DerivedKey, transaction: DBReadTransaction) -> Bool {
        return data(for: key, transaction: transaction) != nil
    }

    // MARK: Helpers

    private func rootKeyData(for key: SVR.DerivedKey, transaction: DBReadTransaction) -> Data? {
        switch key {
        case .storageServiceManifest, .storageServiceRecord:
            // StorageService manifest and record keys are derived from
            // the root storageService key, which itself is derived from
            // the svr master key.
            // Linked devices have the storage service key but not the master key,
            // so try that first before doing the double derivation from the master key.
            if let storageServiceData = localStorage.getSyncedStorageServiceKey(transaction) {
                return storageServiceData
            } else if let masterKey = localStorage.getMasterKey(transaction) {
                return SVR.DerivedKey.storageService.derivedData(from: masterKey)
            } else {
                return nil
            }
        case .storageService, .registrationLock, .registrationRecoveryPassword:
            // Most keys derive directly from the master key.
            return localStorage.getMasterKey(transaction)
        }
    }

    private func setLocalDataAndSyncStorageServiceIfNeeded(
        masterKey: Data,
        isMasterKeyBackedUp: Bool,
        pinType: SVR.PinType,
        encodedPINVerificationString: String?,
        enclaveName: String?,
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
        let masterKeyChanged = masterKey != localStorage.getMasterKey(transaction)
        if masterKeyChanged {
            localStorage.setMasterKey(masterKey, transaction)
        }
        if isMasterKeyBackedUp != localStorage.getIsMasterKeyBackedUp(transaction) {
            localStorage.setIsMasterKeyBackedUp(isMasterKeyBackedUp, transaction)
        }
        if pinType != localStorage.getPinType(transaction) {
            localStorage.setPinType(pinType, transaction)
        }
        if encodedPINVerificationString != localStorage.getEncodedPINVerificationString(transaction) {
            localStorage.setEncodedPINVerificationString(encodedPINVerificationString, transaction)
        }
        if enclaveName != localStorage.getSVR2EnclaveName(transaction) {
            localStorage.setSVR2EnclaveName(enclaveName, transaction)
        }

        // Only continue if we didn't previously have a master key or our master key has changed
        guard masterKeyChanged, tsAccountManager.isRegisteredAndReady(transaction: transaction) else { return }

        // Trigger a re-creation of the storage manifest, our keys have changed
        storageServiceManager.resetLocalData(transaction: transaction)

        // If the app is ready start that restoration.
        guard AppReadiness.isAppReady else { return }

        storageServiceManager.restoreOrCreateManifestIfNecessary(authedAccount: authedAccount)

        let syncManager = self.syncManager
        storageServiceManager.waitForPendingRestores().observe { _ in
            // Sync our new keys with linked devices, but wait until the storage
            // service restore is done. That way we avoid the linked device getting
            // the new keys first, failing to decrypt old storage service data,
            // and asking for new keys even though thats not the problem.
            // We don't wanna miss sending one of these, though, so go ahead and send it
            // even if it fails. In any scenario it should eventually recover once
            // both storage service and the linked device have the latest stuff.
            syncManager.sendKeysSyncMessage()
        }
    }
}
