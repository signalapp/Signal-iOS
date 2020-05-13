//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import SignalCoreKit

// TODO: Remove this extension.
@objc
public extension SDSKeyValueStore {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

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
