//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol AccountEntropyPool: Codable {
    var rawData: String { get }
    func getMasterKey() -> MasterKey
    func getBackupKey() -> BackupKey
}

public struct AccountEntropyPoolImpl: AccountEntropyPool {

    private let key: String
    public var rawData: String { key }

    public init(key: String) {
        // TODO: Validate the key as a
        self.key = key
    }

    // Derived Keys
    public func getMasterKey() -> MasterKey {
        return MasterKeyImpl(masterKey: try! LibSignalClient.AccountEntropyPool.deriveSvrKey(key).asData)
    }

    public func getBackupKey() -> BackupKey {
        return try! LibSignalClient.AccountEntropyPool.deriveBackupKey(key)
    }
}
