//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Legacy onboarding historically used KeyBackupServiceImpl to store state related to
/// the onboarding steps involving key backups.
/// This class now contains that state, and can be removed along with legacy registration.
public class LegacyKbsStateManager {

    public static let shared = LegacyKbsStateManager(keyValueStoreFactory: DependenciesBridge.shared.keyValueStoreFactory)

    private let keyValueStore: KeyValueStore

    public init(
        keyValueStoreFactory: KeyValueStoreFactory
    ) {
        // Collection name must not be changed; matches that historically kept in KeyBackupServiceImpl.
        self.keyValueStore = keyValueStoreFactory.keyValueStore(collection: "kOWSKeyBackupService_Keys")
    }

    private static let hasBackupKeyRequestFailedIdentifier = "hasBackupKeyRequestFailed"

    public func hasBackupKeyRequestFailed(transaction: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(Self.hasBackupKeyRequestFailedIdentifier, defaultValue: false, transaction: transaction)
    }

    public func setHasBackupKeyRequestFailed(_ value: Bool, transaction: DBWriteTransaction) {
        keyValueStore.setBool(value, key: Self.hasBackupKeyRequestFailedIdentifier, transaction: transaction)
    }

    private static let hasPendingRestorationIdentifier = "hasPendingRestoration"

    public func hasPendingRestoration(transaction: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(Self.hasBackupKeyRequestFailedIdentifier, defaultValue: false, transaction: transaction)
    }

    public func recordPendingRestoration(transaction: DBWriteTransaction) {
        keyValueStore.setBool(true, key: Self.hasPendingRestorationIdentifier, transaction: transaction)
    }

    public func clearPendingRestoration(transaction: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: Self.hasPendingRestorationIdentifier, transaction: transaction)
    }
}
