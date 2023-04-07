//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// This file has "shim" classes that allow KeyBackupServiceImpl to talk to
// other classes which aren't protocolized and aren't stub-able in tests.
// We can easily produce stub instances of these protocols in tests,
// allowing us to control their behavior precisely.
// This also allows us to bridge from "v2" database transaction types
// which KeyBackupServiceImpl uses, to sds transaction types that these
// older classes expect as parameters.
//
// Eventually, this whole file can be deleted, once:
// 1) The classes involved have been protocolized (and stub instances
//    can be passed to KeyBackupServiceImpl's initializer in tests).
// 2) The classes involved accept v2 transaction types.

// MARK: - Namespace

extension KBS {
    public enum Shims {
        public typealias TSAccountManager = _KeyBackupServiceImpl_TSAccountManagerShim
        public typealias StorageServiceManager = _KeyBackupServiceImpl_StorageServiceManagerShim
        public typealias OWS2FAManager = _KeyBackupServiceImpl_OWS2FAManagerShim
        public typealias RemoteAttestation = _KeyBackupServiceImpl_RemoteAttestationShim
    }

    public enum Wrappers {
        public typealias TSAccountManager = _KeyBackupServiceImpl_TSAccountManagerWrapper
        public typealias StorageServiceManager = _KeyBackupServiceImpl_StorageServiceManagerWrapper
        public typealias OWS2FAManager = _KeyBackupServiceImpl_OWS2FAManagerWrapper
        public typealias RemoteAttestation = _KeyBackupServiceImpl_RemoteAttestationWrapper
    }
}

// MARK: - TSAccountManager

public protocol _KeyBackupServiceImpl_TSAccountManagerShim {

    func isPrimaryDevice(transaction: DBReadTransaction) -> Bool
    func isRegisteredAndReady(transaction: DBReadTransaction) -> Bool
}

public class _KeyBackupServiceImpl_TSAccountManagerWrapper: KBS.Shims.TSAccountManager {
    private let accountManager: TSAccountManager
    public init(_ accountManager: TSAccountManager) { self.accountManager = accountManager }

    public func isPrimaryDevice(transaction: DBReadTransaction) -> Bool {
        return accountManager.isPrimaryDevice(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    public func isRegisteredAndReady(transaction: DBReadTransaction) -> Bool {
        return accountManager.isRegisteredAndReady(transaction: SDSDB.shimOnlyBridge(transaction))
    }
}

// MARK: - StorageServiceManager

public protocol _KeyBackupServiceImpl_StorageServiceManagerShim {
    func resetLocalData(transaction: DBWriteTransaction)
    func restoreOrCreateManifestIfNecessary(
        authedAccount: AuthedAccount
    )
}

public class _KeyBackupServiceImpl_StorageServiceManagerWrapper: KBS.Shims.StorageServiceManager {
    private let manager: StorageServiceManager
    public init(_ manager: StorageServiceManager) { self.manager = manager }

    public func resetLocalData(transaction: DBWriteTransaction) {
        manager.resetLocalData(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    public func restoreOrCreateManifestIfNecessary(
        authedAccount: AuthedAccount
    ) {
        manager.restoreOrCreateManifestIfNecessary(
            authedAccount: authedAccount
        )
    }
}

// MARK: - OWS2FAManager

public protocol _KeyBackupServiceImpl_OWS2FAManagerShim {
    func pinCode(transaction: DBReadTransaction) -> String?
    func markDisabled(transaction: DBWriteTransaction)
}

public class _KeyBackupServiceImpl_OWS2FAManagerWrapper: KBS.Shims.OWS2FAManager {
    private let manager: OWS2FAManager
    public init(_ manager: OWS2FAManager) { self.manager = manager }

    public func pinCode(transaction: DBReadTransaction) -> String? {
        return manager.pinCode(with: SDSDB.shimOnlyBridge(transaction))
    }

    public func markDisabled(transaction: DBWriteTransaction) {
        manager.markDisabled(transaction: SDSDB.shimOnlyBridge(transaction))
    }
}

// MARK: - RemoteAttestation

public protocol _KeyBackupServiceImpl_RemoteAttestationShim {
    func performForKeyBackup(
        authMethod: RemoteAttestation.KeyBackupAuthMethod,
        enclave: KeyBackupEnclave
    ) -> Promise<RemoteAttestation>
}

public class _KeyBackupServiceImpl_RemoteAttestationWrapper: _KeyBackupServiceImpl_RemoteAttestationShim {
    public func performForKeyBackup(
        authMethod: RemoteAttestation.KeyBackupAuthMethod,
        enclave: KeyBackupEnclave
    ) -> Promise<RemoteAttestation> {
        return RemoteAttestation.performForKeyBackup(
            authMethod: authMethod,
            enclave: enclave
        )
    }
}
