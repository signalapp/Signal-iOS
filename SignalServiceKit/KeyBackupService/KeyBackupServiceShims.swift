//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// This file has "shim" classes that allow KeyBackupService to talk to
// other classes which aren't protocolized and aren't stub-able in tests.
// We can easily produce stub instances of these protocols in tests,
// allowing us to control their behavior precisely.
// This also allows us to bridge from "v2" database transaction types
// which KeyBackupService uses, to sds transaction types that these
// older classes expect as parameters.
//
// Eventually, this whole file can be deleted, once:
// 1) The classes involved have been protocolized (and stub instances
//    can be passed to KeyBackupService's initializer in tests).
// 2) The classes involved accept v2 transaction types.

// MARK: - Namespace

extension KBS {
    public enum Shims {
        public typealias TSAccountManager = _KeyBackupService_TSAccountManagerShim
        public typealias StorageServiceManager = _KeyBackupService_StorageServiceManagerShim
        public typealias OWS2FAManager = _KeyBackupService_OWS2FAManagerShim
    }

    public enum Wrappers {
        public typealias TSAccountManager = _KeyBackupService_TSAccountManagerWrapper
        public typealias StorageServiceManager = _KeyBackupService_StorageServiceManagerWrapper
        public typealias OWS2FAManager = _KeyBackupService_OWS2FAManagerWrapper
    }
}

// MARK: - TSAccountManager

public protocol _KeyBackupService_TSAccountManagerShim {

    func isPrimaryDevice(transaction: DBReadTransaction) -> Bool
    func isRegisteredAndReady(transaction: DBReadTransaction) -> Bool
}

public class _KeyBackupService_TSAccountManagerWrapper: KBS.Shims.TSAccountManager {
    private let accountManager: TSAccountManager
    public init(_ accountManager: TSAccountManager) { self.accountManager = accountManager }

    public func isPrimaryDevice(transaction: DBReadTransaction) -> Bool {
        return accountManager.isPrimaryDevice(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    public func isRegisteredAndReady(transaction: DBReadTransaction) -> Bool {
        return accountManager.isRegisteredAndReady(with: SDSDB.shimOnlyBridge(transaction))
    }
}

// MARK: - StorageServiceManager

public protocol _KeyBackupService_StorageServiceManagerShim {
    func resetLocalData(transaction: DBWriteTransaction)
    func restoreOrCreateManifestIfNecessary()
}

public class _KeyBackupService_StorageServiceManagerWrapper: KBS.Shims.StorageServiceManager {
    private let manager: StorageServiceManagerProtocol
    public init(_ manager: StorageServiceManagerProtocol) { self.manager = manager }

    public func resetLocalData(transaction: DBWriteTransaction) {
        manager.resetLocalData(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    public func restoreOrCreateManifestIfNecessary() {
        manager.restoreOrCreateManifestIfNecessary()
    }
}

// MARK: - OWS2FAManager

public protocol _KeyBackupService_OWS2FAManagerShim {
    func pinCode(transaction: DBReadTransaction) -> String?
    func markDisabled(transaction: DBWriteTransaction)
}

public class _KeyBackupService_OWS2FAManagerWrapper: KBS.Shims.OWS2FAManager {
    private let manager: OWS2FAManager
    public init(_ manager: OWS2FAManager) { self.manager = manager }

    public func pinCode(transaction: DBReadTransaction) -> String? {
        return manager.pinCode(with: SDSDB.shimOnlyBridge(transaction))
    }

    public func markDisabled(transaction: DBWriteTransaction) {
        manager.markDisabled(transaction: SDSDB.shimOnlyBridge(transaction))
    }
}
