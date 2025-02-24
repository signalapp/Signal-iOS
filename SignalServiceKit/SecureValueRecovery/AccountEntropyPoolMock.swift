//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

#if TESTABLE_BUILD

open class AccountEntropyPoolMock: AccountEntropyPool {
    private let masterKey: MasterKey?
    private let key: String?
    public var rawData: String { key! }

    public init(key: String? = nil, masterKey: MasterKey? = nil) {
        self.key = key
        self.masterKey = masterKey
    }

    public required init(from decoder: any Decoder) throws {
        key = nil
        masterKey = nil
    }
    public func encode(to encoder: any Encoder) throws { }

    public func getMasterKey() -> any MasterKey {
        return masterKey!
    }

    public func getBackupKey() -> BackupKey {
        fatalError("not implemented")
    }
}

#endif
