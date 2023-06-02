//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Implementation of `SecureValueRecovery` that talks to KBS (SVR1) and/or SVR2
/// depending on local and remote flags.
/// Once we are fully migrated to SVR2 this class can be deleted.
public class OrchestratingSVRImpl: SecureValueRecovery {

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
        self.svr2 = SecureValueRecovery2Impl(
            connectionFactory: connectionFactory,
            credentialStorage: credentialStorage,
            db: databaseStorage,
            keyValueStoreFactory: keyValueStoreFactory,
            schedulers: schedulers,
            storageServiceManager: storageServiceManager,
            syncManager: syncManager,
            tsAccountManager: accountManager,
            tsConstants: tsConstants,
            twoFAManager: twoFAManager
        )
        self.kbs = KeyBackupServiceImpl(
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
        )
        self.db = databaseStorage
        self.schedulers = schedulers
    }

    // MARK: - Delegation

    private let svr2: SecureValueRecovery2Impl
    private let kbs: KeyBackupServiceImpl

    private var remoteSVRConfig: RemoteConfig.SVRConfiguration?

    public func setRemoteConfiguration(_ config: RemoteConfig.SVRConfiguration) {
        self.remoteSVRConfig = config
    }

    private enum ReadStrategy {
        case kbsOnly
        case fallbackToKBSForNonInvalidPinFailure
        case fallbackToKBSForNoBackupFailureOnly
        case svr2Only
    }

    private var readStrategy: ReadStrategy {
        guard FeatureFlags.svr2 else {
            return .kbsOnly
        }
        switch remoteSVRConfig {
        case .none:
            // We do reads before registering, which means before
            // we have any remote config flags.
            // In this case, we want to try SVR2 but fall back to
            // KBS if _anything_ goes wrong (besides an explicit wrong PIN).
            return .fallbackToKBSForNonInvalidPinFailure
        case .kbsOnly:
            return .kbsOnly
        case .mirroring:
            return .fallbackToKBSForNoBackupFailureOnly
        case .svr2Only:
            return .svr2Only
        }
    }

    private enum WriteStrategy {
        case kbsOnly
        case mirroring
        case svr2Only
    }

    private var writeStrategy: WriteStrategy {
        guard let remoteSVRConfig else {
            owsFailBeta("Should only be writing after setting remote config")
            return FeatureFlags.svr2 ? .mirroring : .kbsOnly
        }
        switch remoteSVRConfig {
        case .kbsOnly:
            return .kbsOnly
        case .mirroring:
            return .mirroring
        case .svr2Only:
            return .svr2Only
        }
    }

    public func warmCaches() {
        var shouldWarmKBS = false
        var shouldWarmSVR2 = false
        switch remoteSVRConfig {
        case .none:
            // Both of these no-op if not registered,
            // so its pretty safe to call without a remote config.
            shouldWarmKBS = true
            shouldWarmSVR2 = FeatureFlags.svr2
        case .kbsOnly:
            shouldWarmKBS = true
        case .svr2Only:
            shouldWarmSVR2 = true
        case .mirroring:
            shouldWarmKBS = true
            shouldWarmSVR2 = true
        }

        if shouldWarmKBS {
            kbs.warmCaches()
        }
        if shouldWarmSVR2 {
            svr2.warmCaches()
        }
    }

    // MARK: - Key Existence

    public var hasMasterKey: Bool {
        return db.read(block: self.hasMasterKey(transaction:))
    }

    public func hasMasterKey(transaction: DBReadTransaction) -> Bool {
        switch readStrategy {
        case .kbsOnly:
            return kbs.hasMasterKey(transaction: transaction)
        case .svr2Only:
            return svr2.hasMasterKey(transaction: transaction)
        case .fallbackToKBSForNoBackupFailureOnly, .fallbackToKBSForNonInvalidPinFailure:
            // Local only operation; no errors to differentiate.
            return svr2.hasMasterKey(transaction: transaction) || kbs.hasMasterKey(transaction: transaction)
        }
    }

    public var hasBackedUpMasterKey: Bool {
        return db.read(block: self.hasBackedUpMasterKey(transaction:))
    }

    public func hasBackedUpMasterKey(transaction: DBReadTransaction) -> Bool {
        switch readStrategy {
        case .kbsOnly:
            return kbs.hasBackedUpMasterKey(transaction: transaction)
        case .svr2Only:
            return svr2.hasBackedUpMasterKey(transaction: transaction)
        case .fallbackToKBSForNoBackupFailureOnly, .fallbackToKBSForNonInvalidPinFailure:
            // Local only operation; no errors to differentiate.
            return svr2.hasBackedUpMasterKey(transaction: transaction) || kbs.hasBackedUpMasterKey(transaction: transaction)
        }
    }

    public func useDeviceLocalMasterKey(authedAccount: AuthedAccount, transaction: DBWriteTransaction) {
        switch writeStrategy {
        case .kbsOnly:
            kbs.useDeviceLocalMasterKey(authedAccount: authedAccount, transaction: transaction)
        case .svr2Only:
            svr2.useDeviceLocalMasterKey(authedAccount: authedAccount, transaction: transaction)
        case .mirroring:
            kbs.useDeviceLocalMasterKey(authedAccount: authedAccount, transaction: transaction)
            svr2.useDeviceLocalMasterKey(authedAccount: authedAccount, transaction: transaction)
        }
    }

    // MARK: - PIN Management

    public var currentPinType: SVR.PinType? {
        return db.read(block: self.currentPinType(transaction:))
    }

    public func currentPinType(transaction: DBReadTransaction) -> SVR.PinType? {
        switch readStrategy {
        case .kbsOnly:
            return kbs.currentPinType(transaction: transaction)
        case .svr2Only:
            return svr2.currentPinType(transaction: transaction)
        case .fallbackToKBSForNoBackupFailureOnly, .fallbackToKBSForNonInvalidPinFailure:
            // Local only operation; no errors to differentiate.
            return svr2.currentPinType(transaction: transaction) ?? kbs.currentPinType(transaction: transaction)
        }
    }

    public func verifyPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        switch readStrategy {
        case .kbsOnly:
            kbs.verifyPin(pin, resultHandler: resultHandler)
        case .svr2Only:
            svr2.verifyPin(pin, resultHandler: resultHandler)
        case .fallbackToKBSForNoBackupFailureOnly, .fallbackToKBSForNonInvalidPinFailure:
            // Return true if any return true.
            // Note this is a local operation; the different fallback strategies
            // are irrelevant here.
            svr2.verifyPin(pin) { [kbs] success in
                if success {
                    resultHandler(true)
                } else {
                    kbs.verifyPin(pin, resultHandler: resultHandler)
                }
            }
        }
    }

    // MARK: - Key Management

    public func acquireRegistrationLockForNewNumber(with pin: String, and auth: SVRAuthCredential) -> Promise<String> {
        switch readStrategy {
        case .kbsOnly:
            return kbs.acquireRegistrationLockForNewNumber(with: pin, and: auth)
        case .svr2Only:
            return svr2.acquireRegistrationLockForNewNumber(with: pin, and: auth)
        case .fallbackToKBSForNoBackupFailureOnly:
            return svr2.acquireRegistrationLockForNewNumber(with: pin, and: auth).recover(on: schedulers.main) { [kbs] error in
                if error.isBackupMissingError {
                    return kbs.acquireRegistrationLockForNewNumber(with: pin, and: auth)
                } else {
                    return .init(error: error)
                }
            }
        case .fallbackToKBSForNonInvalidPinFailure:
            return svr2.acquireRegistrationLockForNewNumber(with: pin, and: auth).recover(on: schedulers.main) { [kbs] error in
                if error.isInvalidPinError {
                    return Promise<String>(error: error)
                } else {
                    return kbs.acquireRegistrationLockForNewNumber(with: pin, and: auth)
                }
            }
        }
    }

    public func generateAndBackupKeys(pin: String, authMethod: SVR.AuthMethod, rotateMasterKey: Bool) -> Promise<Void> {
        switch writeStrategy {
        case .kbsOnly:
            return kbs.generateAndBackupKeys(pin: pin, authMethod: authMethod, rotateMasterKey: rotateMasterKey)
        case .svr2Only:
            return svr2.generateAndBackupKeys(pin: pin, authMethod: authMethod, rotateMasterKey: rotateMasterKey)
        case .mirroring:
            return svr2.generateAndBackupKeys(pin: pin, authMethod: authMethod, rotateMasterKey: rotateMasterKey).then(on: schedulers.main) { [kbs] (masterKey: Data) in
                return kbs.generateAndBackupKeys(pin: pin, authMethod: authMethod, masterKey: masterKey)
            }
        }
    }

    public func restoreKeys(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult> {
        switch readStrategy {
        case .kbsOnly:
            return kbs.restoreKeys(pin: pin, authMethod: authMethod)
        case .svr2Only:
            return svr2.restoreKeys(pin: pin, authMethod: authMethod)
        case .fallbackToKBSForNoBackupFailureOnly:
            return svr2.restoreKeys(pin: pin, authMethod: authMethod).then(on: schedulers.main) { [kbs] result in
                switch result {
                case .success, .invalidPin, .genericError, .networkError:
                    return .value(result)
                case .backupMissing:
                    return kbs.restoreKeys(pin: pin, authMethod: authMethod)
                }
            }
        case .fallbackToKBSForNonInvalidPinFailure:
            return svr2.restoreKeys(pin: pin, authMethod: authMethod).then(on: schedulers.main) { [kbs] result in
                switch result {
                case .success, .invalidPin:
                    return .value(result)
                case .backupMissing, .genericError, .networkError:
                    return kbs.restoreKeys(pin: pin, authMethod: authMethod)
                }
            }
        }
    }

    public func restoreKeysAndBackup(pin: String, authMethod: SVR.AuthMethod) -> Guarantee<SVR.RestoreKeysResult> {
        // We have to separate the read from the write, because each might fail.
        // A valid path here is reading from SVR succeeds, then we write that
        // restored value to both svr and kbs.
        return firstly(on: schedulers.sync) {
            return self.restoreKeys(pin: pin, authMethod: authMethod)
        }.then(on: schedulers.main) { [weak self] restoreKeysResult in
            guard let self else {
                return .value(.genericError(OWSAssertionError("unretained self")))
            }
            return self.generateAndBackupKeys(pin: pin, authMethod: authMethod, rotateMasterKey: false)
                .map(on: SyncScheduler()) {
                    return restoreKeysResult
                }
                .recover(on: SyncScheduler()) { error in
                    if error.isNetworkFailureOrTimeout {
                        return .value(.networkError(error))
                    }
                    return .value(.genericError(error))
                }
        }
    }

    public func deleteKeys() -> Promise<Void> {
        switch writeStrategy {
        case .kbsOnly:
            return kbs.deleteKeys()
        case .svr2Only:
            return svr2.deleteKeys()
        case .mirroring:
            return svr2.deleteKeys().then(on: schedulers.main) { [kbs] in
                return kbs.deleteKeys()
            }
        }
    }

    public func clearKeys(transaction: DBWriteTransaction) {
        switch writeStrategy {
        case .kbsOnly:
            kbs.clearKeys(transaction: transaction)
        case .svr2Only:
            svr2.clearKeys(transaction: transaction)
        case .mirroring:
            svr2.clearKeys(transaction: transaction)
            kbs.clearKeys(transaction: transaction)
        }
    }

    // MARK: - Master Key Encryption

    public func encrypt(
        keyType: SVR.DerivedKey,
        data: Data,
        transaction: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        switch readStrategy {
        case .kbsOnly:
            return kbs.encrypt(keyType: keyType, data: data, transaction: transaction)
        case .svr2Only:
            return svr2.encrypt(keyType: keyType, data: data, transaction: transaction)
        case .fallbackToKBSForNoBackupFailureOnly, .fallbackToKBSForNonInvalidPinFailure:
            // Local only operation; no different error behavior.
            let svr2Result = svr2.encrypt(keyType: keyType, data: data, transaction: transaction)
            if svr2Result.isKeyMissingError {
                return kbs.encrypt(keyType: keyType, data: data, transaction: transaction)
            } else {
                return svr2Result
            }
        }
    }

    public func decrypt(
        keyType: SVR.DerivedKey,
        encryptedData: Data,
        transaction: DBReadTransaction
    ) -> SVR.ApplyDerivedKeyResult {
        switch readStrategy {
        case .kbsOnly:
            return kbs.decrypt(keyType: keyType, encryptedData: encryptedData, transaction: transaction)
        case .svr2Only:
            return svr2.decrypt(keyType: keyType, encryptedData: encryptedData, transaction: transaction)
        case .fallbackToKBSForNoBackupFailureOnly, .fallbackToKBSForNonInvalidPinFailure:
            // Local only operation; no different error behavior.
            let svr2Result = svr2.decrypt(keyType: keyType, encryptedData: encryptedData, transaction: transaction)
            if svr2Result.isKeyMissingError {
                return kbs.decrypt(keyType: keyType, encryptedData: encryptedData, transaction: transaction)
            } else {
                return svr2Result
            }
        }
    }

    public func storeSyncedStorageServiceKey(
        data: Data?,
        authedAccount: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
        switch readStrategy {
        case .kbsOnly:
            kbs.storeSyncedStorageServiceKey(data: data, authedAccount: authedAccount, transaction: transaction)
        case .svr2Only:
            svr2.storeSyncedStorageServiceKey(data: data, authedAccount: authedAccount, transaction: transaction)
        case .fallbackToKBSForNoBackupFailureOnly, .fallbackToKBSForNonInvalidPinFailure:
            // NOTE: this will trigger multiple storage service syncs.
            // However, those happen asynchronously, and StorageService code
            // should dedupe the requests. So this should be fine in the
            // short term while we use both SVRs in parallel.
            kbs.storeSyncedStorageServiceKey(data: data, authedAccount: authedAccount, transaction: transaction)
            svr2.storeSyncedStorageServiceKey(data: data, authedAccount: authedAccount, transaction: transaction)
        }
    }

    // MARK: - Value Derivation

    public func data(for key: SVR.DerivedKey, transaction: DBReadTransaction) -> SVR.DerivedKeyData? {
        switch readStrategy {
        case .kbsOnly:
            return kbs.data(for: key, transaction: transaction)
        case .svr2Only:
            return svr2.data(for: key, transaction: transaction)
        case .fallbackToKBSForNoBackupFailureOnly, .fallbackToKBSForNonInvalidPinFailure:
            // Local only operation; no different error behavior.
            return svr2.data(for: key, transaction: transaction) ?? kbs.data(for: key, transaction: transaction)
        }
    }

    public func isKeyAvailable(_ key: SVR.DerivedKey) -> Bool {
        return db.read {
            return self.isKeyAvailable(key, transaction: $0)
        }
    }

    public func isKeyAvailable(_ key: SVR.DerivedKey, transaction: DBReadTransaction) -> Bool {
        switch readStrategy {
        case .kbsOnly:
            return kbs.isKeyAvailable(key, transaction: transaction)
        case .svr2Only:
            return svr2.isKeyAvailable(key, transaction: transaction)
        case .fallbackToKBSForNoBackupFailureOnly, .fallbackToKBSForNonInvalidPinFailure:
            // Local only operation; no different error behavior.
            return svr2.isKeyAvailable(key, transaction: transaction) || kbs.isKeyAvailable(key, transaction: transaction)
        }
    }
}

// MARK: - Errors

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

extension Error {

    fileprivate var isBackupMissingError: Bool {
        switch self as? SVR.SVRError {
        case .none, .assertion, .invalidPin:
            return false
        case .backupMissing:
            return true
        }
    }

    fileprivate var isInvalidPinError: Bool {
        switch self as? SVR.SVRError {
        case .none, .assertion, .backupMissing:
            return false
        case .invalidPin:
            return true
        }
    }
}
