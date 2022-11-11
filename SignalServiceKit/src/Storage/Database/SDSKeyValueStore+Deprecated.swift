//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

// TODO: Remove this extension.
@objc
public extension SDSKeyValueStore {

    // MARK: - Date

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func getDate(_ key: String) -> Date? {
        return databaseStorage.read { (transaction) in
            return self.getDate(key, transaction: transaction)
        }
    }

    // MARK: - Bool

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func getBool(_ key: String, defaultValue: Bool) -> Bool {
        return databaseStorage.read { (transaction) in
            return self.getBool(key, defaultValue: defaultValue, transaction: transaction)
        }
    }
}
