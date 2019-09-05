//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

    // MARK: -

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func getString(_ key: String) -> String? {
        return databaseStorage.readReturningResult { (transaction) in
            return self.getString(key, transaction: transaction)
        }
    }

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func setString(_ value: String?, key: String) {
        return databaseStorage.write { (transaction) in
            return self.setString(value, key: key, transaction: transaction)
        }
    }

    // MARK: - Date

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func getDate(_ key: String) -> Date? {
        return databaseStorage.readReturningResult { (transaction) in
            return self.getDate(key, transaction: transaction)
        }
    }

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func setDate(_ value: Date, key: String) {
        return databaseStorage.write { (transaction) in
            return self.setDate(value, key: key, transaction: transaction)
        }
    }

    // MARK: - Bool

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func getBool(_ key: String, defaultValue: Bool) -> Bool {
        return databaseStorage.readReturningResult { (transaction) in
            return self.getBool(key, defaultValue: defaultValue, transaction: transaction)
        }
    }

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func setBool(_ value: Bool, key: String) {
        return databaseStorage.write { (transaction) in
            return self.setBool(value, key: key, transaction: transaction)
        }
    }

    // MARK: - UInt

    // TODO: Handle numerics more generally.
    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func getUInt(_ key: String, defaultValue: UInt) -> UInt {
        return databaseStorage.readReturningResult { (transaction) in
            return self.getUInt(key, defaultValue: defaultValue, transaction: transaction)
        }
    }

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func setUInt(_ value: UInt, key: String) {
        return databaseStorage.write { (transaction) in
            return self.setUInt(value, key: key, transaction: transaction)
        }
    }

    // MARK: - Data

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func getData(_ key: String) -> Data? {
        return databaseStorage.readReturningResult { (transaction) in
            return self.getData(key, transaction: transaction)
        }
    }

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func setData(_ value: Data?, key: String) {
        return databaseStorage.write { (transaction) in
            return self.setData(value, key: key, transaction: transaction)
        }
    }

    // MARK: - Numeric

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func getInt(_ key: String, defaultValue: Int) -> Int {
        return databaseStorage.readReturningResult { (transaction) in
            return self.getInt(key, defaultValue: defaultValue, transaction: transaction)
        }
    }

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func setInt(_ value: Int, key: String) {
        return databaseStorage.write { (transaction) in
            return self.setInt(value, key: key, transaction: transaction)
        }
    }

    // MARK: - Numeric

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func getUInt64(_ key: String, defaultValue: UInt64) -> UInt64 {
        return databaseStorage.readReturningResult { (transaction) in
            return self.getUInt64(key, defaultValue: defaultValue, transaction: transaction)
        }
    }

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func setUInt64(_ value: UInt64, key: String) {
        return databaseStorage.write { (transaction) in
            return self.setUInt64(value, key: key, transaction: transaction)
        }
    }

    // MARK: - Object

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func getObject(_ key: String) -> Any? {
        return databaseStorage.readReturningResult { (transaction) in
            return self.getObject(key, transaction: transaction)
        }
    }

    @available(*, deprecated, message: "Avoid sneaky transactions by passing a transaction")
    func setObject(_ value: Any?, key: String) {
        return databaseStorage.write { (transaction) in
            return self.setObject(value, key: key, transaction: transaction)
        }
    }

    func removeValue(forKey key: String) {
        return databaseStorage.write { (transaction) in
            return self.removeValue(forKey: key, transaction: transaction)
        }
    }
}
