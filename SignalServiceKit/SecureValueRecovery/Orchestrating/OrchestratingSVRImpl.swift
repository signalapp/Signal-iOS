//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Implementation of `SecureValueRecovery` that talks to KBS (SVR1) and/or SVR2
/// depending on local and remote flags.
/// Once we are fully migrated to SVR2 this class can be deleted.
public class OrchestratingSVRImpl: SecureValueRecovery {

    /// SVR implementations to delegate actions out to.
    /// Writes should be taken _in order_, e.g. we write to the first element in
    /// the array, then the second. All writes are required to succeed for
    /// the write overall to be considered a success.
    /// Reads should happen in order, but if there is a non-transient error
    /// we can fall back to the next instance until some read succeeds
    /// or we reach the end.
    private let svrs: [SecureValueRecovery]

    private let db: DB
    private let schedulers: Schedulers

    public init(
        accountManager: SVR.Shims.TSAccountManager,
        appContext: AppContext,
        connectionFactory: SgxWebsocketConnectionFactory,
        credentialStorage: SVRAuthCredentialStorage,
        databaseStorage: DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        remoteAttestation: SVR.Shims.RemoteAttestation,
        schedulers: Schedulers,
        signalService: OWSSignalServiceProtocol,
        storageServiceManager: StorageServiceManager,
        syncManager: SyncManagerProtocolSwift,
        tsConstants: TSConstantsProtocol,
        twoFAManager: SVR.Shims.OWS2FAManager
    ) {
        var svrs = [SecureValueRecovery]()
        let shouldUseSVR2 = FeatureFlags.mirrorSVR2 || FeatureFlags.exclusiveSVR2
        if shouldUseSVR2 {
            svrs.append(SecureValueRecovery2Impl(
                connectionFactory: connectionFactory,
                credentialStorage: credentialStorage,
                db: databaseStorage,
                keyValueStoreFactory: keyValueStoreFactory,
                schedulers: schedulers,
                storageServiceManager: storageServiceManager,
                syncManager: syncManager,
                tsAccountManager: accountManager,
                twoFAManager: twoFAManager
            ))
        }
        if !FeatureFlags.exclusiveSVR2 {
            svrs.append(KeyBackupServiceImpl(
                accountManager: accountManager,
                appContext: appContext,
                credentialStorage: credentialStorage,
                databaseStorage: databaseStorage,
                keyValueStoreFactory: keyValueStoreFactory,
                remoteAttestation: remoteAttestation,
                schedulers: schedulers,
                signalService: signalService,
                storageServiceManager: storageServiceManager,
                syncManager: syncManager,
                tsConstants: tsConstants,
                twoFAManager: twoFAManager
            ))
        }
        self.svrs = svrs
        self.db = databaseStorage
        self.schedulers = schedulers
    }

    public func warmCaches() {
        svrs.forEach { $0.warmCaches() }
    }

    // MARK: - Key Existence

    public var hasMasterKey: Bool {
        return db.read(block: self.hasMasterKey(transaction:))
    }

    public func hasMasterKey(transaction: DBReadTransaction) -> Bool {
        return svrs.contains(where: { $0.hasMasterKey(transaction: transaction) })
    }

    public var hasBackedUpMasterKey: Bool {
        return db.read(block: self.hasBackedUpMasterKey(transaction:))
    }

    public func hasBackedUpMasterKey(transaction: DBReadTransaction) -> Bool {
        return svrs.contains(where: { $0.hasBackedUpMasterKey(transaction: transaction) })
    }

    public func setMasterKeyBackedUp(_ value: Bool, transaction: DBWriteTransaction) {
        svrs.forEach { $0.setMasterKeyBackedUp(value, transaction: transaction) }
    }

    public func useDeviceLocalMasterKey(authedAccount: AuthedAccount, transaction: DBWriteTransaction) {
        svrs.forEach { $0.useDeviceLocalMasterKey(authedAccount: authedAccount, transaction: transaction) }
    }

    // MARK: - PIN Management

    public var currentPinType: SVR.PinType? {
        return db.read(block: self.currentPinType(transaction:))
    }

    public func currentPinType(transaction: DBReadTransaction) -> SVR.PinType? {
        return svrs.lazy.compactMap({ $0.currentPinType(transaction: transaction) }).first
    }

    public func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        // Return true if any return true, in order.
        // This is so we verify the pin if its right for KBS while SVR2 still has nothing
        // set; its the right pin and SVR2 just needs to catch up.
        var i = 0
        func tryNext() {
            guard let svr = svrs[safe: i] else {
                resultHandler(false)
                return
            }
            svr.verifyPin(pin, resultHandler: { success in
                if success {
                    resultHandler(true)
                } else {
                    i += 1
                    tryNext()
                }
            })
        }
        tryNext()
    }

    // MARK: - Key Management

    public func acquireRegistrationLockForNewNumber(with pin: String, and auth: SVRAuthCredential) -> Promise<String> {
        return doRead {
            return $0.acquireRegistrationLockForNewNumber(with: pin, and: auth)
        }
    }

    public func generateAndBackupKeys(pin: String, authMethod: SVR.AuthMethod, rotateMasterKey: Bool) -> Promise<Void> {
        return doWrite {
            return $0.generateAndBackupKeys(pin: pin, authMethod: authMethod, rotateMasterKey: rotateMasterKey)
        }
    }

    public func restoreKeysAndBackup(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult> {
        return doRead({
                return $0.restoreKeysAndBackup(pin: pin, authMethod: authMethod)
            },
            isNoBackupError: \.isNoSVRBackupError
        )
    }

    public func deleteKeys() -> Promise<Void> {
        return doWrite {
            return $0.deleteKeys()
        }
    }

    public func clearKeys(transaction: DBWriteTransaction) {
        svrs.forEach {
            $0.clearKeys(transaction: transaction)
        }
    }

    // MARK: - Master Key Encryption

    public func encrypt(
        keyType: SVR.DerivedKey,
        data: Data,
        transaction: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        return doLocalRead({
                return $0.encrypt(keyType: keyType, data: data, transaction: transaction)
            },
            isLocalKeyMissingError: \.isKeyMissingError
        )
    }

    public func decrypt(
        keyType: SVR.DerivedKey,
        encryptedData: Data,
        transaction: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        return doLocalRead({
                return $0.decrypt(keyType: keyType, encryptedData: encryptedData, transaction: transaction)
            },
            isLocalKeyMissingError: \.isKeyMissingError
        )
    }

    public func storeSyncedStorageServiceKey(
        data: Data?,
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
        // NOTE: this will trigger multiple storage service syncs.
        // However, those happen asynchronously, and StorageService code
        // should dedupe the requests. So this should be fine in the
        // short term while we use both SVRs in parallel.
        svrs.forEach {
            $0.storeSyncedStorageServiceKey(
                data: data,
                authedAccount: authedAccount,
                transaction: transaction
            )
        }
    }

    // MARK: - Value Derivation

    public func data(for key: SVR.DerivedKey, transaction: DBReadTransaction) -> SVR.DerivedKeyData? {
        return doLocalRead {
            $0.data(for: key, transaction: transaction)
        }
    }

    public func isKeyAvailable(_ key: SVR.DerivedKey) -> Bool {
        return db.read {
            return self.isKeyAvailable(key, transaction: $0)
        }
    }

    public func isKeyAvailable(_ key: SVR.DerivedKey, transaction: DBReadTransaction) -> Bool {
        return svrs.contains(where: { $0.isKeyAvailable(key, transaction: transaction) })
    }

    // MARK: - Helpers

    private func doRead<T>(_ fn: @escaping (SecureValueRecovery) -> Promise<T>) -> Promise<T> {
        // Reads can happen from whichever is available.
        // We do things in order, as SVR2 is considered s
        var i = 0
        var firstFailure: Error?
        let schedulers = self.schedulers
        let svrs = self.svrs
        func tryNext() -> Promise<T> {
            guard let svr = svrs[safe: i] else {
                // svrs is never empty; this force unwrap fails only if it is.
                return .init(error: firstFailure!)
            }
            return fn(svr).recover(
                on: schedulers.main
            ) { error -> Promise<T> in
                if firstFailure == nil {
                    firstFailure = error
                }

                // If we didn't find a backup, try the next
                // svr instance.
                if error.isNoSVRBackupError {
                    i += 1
                    return tryNext()
                } else {
                    return .init(error: error)
                }
            }
        }
        return tryNext()
    }

    private func doRead<T>(
        _ fn: @escaping (SecureValueRecovery) -> Guarantee<T>,
        isNoBackupError: @escaping (T) -> Bool
    ) -> Guarantee<T> {
        // Reads can happen from whichever is available.
        // We do things in order, as SVR2 is considered source of truth.
        var i = 0
        var firstResult: T?
        let schedulers = self.schedulers
        let svrs = self.svrs
        func tryNext() -> Guarantee<T> {
            guard let svr = svrs[safe: i] else {
                // svrs is never empty; this force unwrap fails only if it is.
                return .value(firstResult!)
            }
            return fn(svr).then(
                on: schedulers.main
            ) { t -> Guarantee<T> in
                if firstResult == nil {
                    firstResult = t
                }
                if isNoBackupError(t) {
                    i += 1
                    return tryNext()
                } else {
                    return .value(t)
                }
            }
        }
        return tryNext()
    }

    private func doLocalRead<T>(
        _ fn: (SecureValueRecovery) -> T,
        isLocalKeyMissingError: (T) -> Bool
    ) -> T {
        var firstValue: T?
        for svr in svrs {
            let t = fn(svr)
            firstValue = t
            if isLocalKeyMissingError(t) {
                continue
            }
            return t
        }
        // svrs is never empty; this force unwrap fails only if it is.
        return firstValue!
    }

    private func doLocalRead<T>(_ fn: (SecureValueRecovery) -> T?) -> T? {
        for svr in svrs {
            if let t = fn(svr) {
                return t
            }
        }
        return nil
    }

    private func doWrite(_ fn: @escaping (SecureValueRecovery) -> Promise<Void>) -> Promise<Void> {
        // MUST be done sequentially in order, not in parallel.
        // We can't have SVR2 fail and KBS succeed, SVR2 must succeed
        // first and then KBS gets its turn (but we require it to succeed too)
        var i = 0
        let schedulers = self.schedulers
        let svrs = self.svrs
        func tryNext() -> Promise<Void> {
            guard let svr = svrs[safe: i] else {
                return .value(())
            }
            return fn(svr).then(on: schedulers.main) {
                i += 1
                return tryNext()
            }
        }
        return tryNext()
    }
}

// MARK: - Errors

extension Error {

    fileprivate var isNoSVRBackupError: Bool {
        switch self as? SVR.SVRError {
        case .backupMissing:
            return true
        case .invalidPin:
            // If we are _told_ the pin is wrong,
            // consider that a failure; we want to retry the
            // first svr instance instead of falling back to
            // potentially stale data from the next instance.
            return false
        case .assertion:
            // Its unfortunate that "assertion" is a catch
            // all for any number of failures, but we only really
            // care about the backup missing failure, anyway.
            return false
        case .none:
            // Some other error, likely a network error.
            // Fail; we want to retry the first svr instance
            // instead of falling back to potentially stale data
            // from the next instance.
            return false
        }
    }
}

extension SVR.RestoreKeysResult {

    fileprivate var isNoSVRBackupError: Bool {
        switch self {
        case .backupMissing:
            return true
        case .genericError, .networkError, .invalidPin, .success:
            return false
        }
    }
}

extension SVR.ApplyDerivedKeyResult {

    fileprivate var isKeyMissingError: Bool {
        switch self {
        case .success:
            return false
        case .masterKeyMissing:
            return true
        case .cryptographyError:
            return false
        }
    }
}
