//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Unwraps DB Transactions into SDS Transactions and forwards calls.
extension SDSKeyValueStore: KeyValueStore {

    public func hasValue(_ key: String, transaction: DBReadTransaction) -> Bool {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return hasValue(forKey: key, transaction: sdsTx)
    }

    public func getString(_ key: String, transaction: DBReadTransaction) -> String? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getString(key, transaction: sdsTx)
    }

    public func setString(_ value: String?, key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        setString(value, key: key, transaction: sdsTx)
    }

    public func getDate(_ key: String, transaction: DBReadTransaction) -> Date? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getDate(key, transaction: sdsTx)
    }

    public func setDate(_ value: Date, key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        setDate(value, key: key, transaction: sdsTx)
    }

    public func getBool(_ key: String, transaction: DBReadTransaction) -> Bool? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getBool(key, transaction: sdsTx)
    }

    public func getBool(_ key: String, defaultValue: Bool, transaction: DBReadTransaction) -> Bool {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getBool(key, defaultValue: defaultValue, transaction: sdsTx)
    }

    public func setBool(_ value: Bool, key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        setBool(value, key: key, transaction: sdsTx)
    }

    public func setBoolIfChanged(_ value: Bool, defaultValue: Bool, key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        setBoolIfChanged(value, defaultValue: defaultValue, key: key, transaction: sdsTx)
    }

    public func getUInt(_ key: String, transaction: DBReadTransaction) -> UInt? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getUInt(key, transaction: sdsTx)
    }

    public func getUInt(_ key: String, defaultValue: UInt, transaction: DBReadTransaction) -> UInt {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getUInt(key, defaultValue: defaultValue, transaction: sdsTx)
    }

    public func setUInt(_ value: UInt, key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        setUInt(value, key: key, transaction: sdsTx)
    }

    public func getData(_ key: String, transaction: DBReadTransaction) -> Data? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getData(key, transaction: sdsTx)
    }

    public func setData(_ value: Data?, key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        setData(value, key: key, transaction: sdsTx)
    }

    public func getNSNumber(_ key: String, transaction: DBReadTransaction) -> NSNumber? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getNSNumber(key, transaction: sdsTx)
    }

    public func getInt(_ key: String, transaction: DBReadTransaction) -> Int? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getInt(key, transaction: sdsTx)
    }

    public func getInt(_ key: String, defaultValue: Int, transaction: DBReadTransaction) -> Int {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getInt(key, defaultValue: defaultValue, transaction: sdsTx)
    }

    public func setInt(_ value: Int, key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        setInt(value, key: key, transaction: sdsTx)
    }

    public func getInt32(_ key: String, transaction: DBReadTransaction) -> Int32? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getInt32(key, transaction: sdsTx)
    }

    public func getInt32(_ key: String, defaultValue: Int32, transaction: DBReadTransaction) -> Int32 {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getInt32(key, defaultValue: defaultValue, transaction: sdsTx)
    }

    public func setInt32(_ value: Int32, key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return setInt32(value, key: key, transaction: sdsTx)
    }

    public func getUInt32(_ key: String, transaction: DBReadTransaction) -> UInt32? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getUInt32(key, transaction: sdsTx)
    }

    public func getUInt32(_ key: String, defaultValue: UInt32, transaction: DBReadTransaction) -> UInt32 {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getUInt32(key, defaultValue: defaultValue, transaction: sdsTx)
    }

    public func setUInt32(_ value: UInt32, key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        setUInt32(value, key: key, transaction: sdsTx)
    }

    public func getUInt64(_ key: String, transaction: DBReadTransaction) -> UInt64? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getUInt64(key, transaction: sdsTx)
    }

    public func getUInt64(_ key: String, defaultValue: UInt64, transaction: DBReadTransaction) -> UInt64 {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getUInt64(key, defaultValue: defaultValue, transaction: sdsTx)
    }

    public func setUInt64(_ value: UInt64, key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        setUInt64(value, key: key, transaction: sdsTx)
    }

    public func getInt64(_ key: String, transaction: DBReadTransaction) -> Int64? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getInt64(key, transaction: sdsTx)
    }

    public func getInt64(_ key: String, defaultValue: Int64, transaction: DBReadTransaction) -> Int64 {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getInt64(key, defaultValue: defaultValue, transaction: sdsTx)
    }

    public func setInt64(_ value: Int64, key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        setInt64(value, key: key, transaction: sdsTx)
    }

    public func getDouble(_ key: String, transaction: DBReadTransaction) -> Double? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getDouble(key, transaction: sdsTx)
    }

    public func getDouble(_ key: String, defaultValue: Double, transaction: DBReadTransaction) -> Double {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getDouble(key, defaultValue: defaultValue, transaction: sdsTx)
    }

    public func setDouble(_ value: Double, key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        setDouble(value, key: key, transaction: sdsTx)
    }

    public func getObject(forKey key: String, transaction: DBReadTransaction) -> Any? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return getObject(forKey: key, transaction: sdsTx)
    }

    public func setObject(_ anyValue: Any?, key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        setObject(anyValue, key: key, transaction: sdsTx)
    }

    public func removeValue(forKey key: String, transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return removeValue(forKey: key, transaction: sdsTx)
    }

    public func removeValues(forKeys keys: [String], transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return removeValues(forKeys: keys, transaction: sdsTx)
    }

    public func removeAll(transaction: DBWriteTransaction) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return removeAll(transaction: sdsTx)
    }

    public func enumerateKeysAndObjects(transaction: DBReadTransaction, block: (String, Any, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return enumerateKeysAndObjects(transaction: sdsTx, block: block)
    }

    public func enumerateKeys(transaction: DBReadTransaction, block: (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return enumerateKeys(transaction: sdsTx, block: block)
    }

    public func allValues(transaction: DBReadTransaction) -> [Any] {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return allValues(transaction: sdsTx)
    }

    public func allDataValues(transaction: DBReadTransaction) -> [Data] {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return allDataValues(transaction: sdsTx)
    }

    public func allBoolValuesMap(transaction: DBReadTransaction) -> [String: Bool] {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return allBoolValuesMap(transaction: sdsTx)
    }

    public func allUIntValuesMap(transaction: DBReadTransaction) -> [String: UInt] {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return allUIntValuesMap(transaction: sdsTx)
    }

    public func anyDataValue(transaction: DBReadTransaction) -> Data? {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return anyDataValue(transaction: sdsTx)
    }

    public func allKeys(transaction: DBReadTransaction) -> [String] {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return allKeys(transaction: sdsTx)
    }

    public func numberOfKeys(transaction: DBReadTransaction) -> UInt {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return numberOfKeys(transaction: sdsTx)
    }

    public func setCodable<T>(_ value: T, key: String, transaction: DBWriteTransaction) throws where T: Encodable {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        try setCodable(value, key: key, transaction: sdsTx)
    }

    public func setCodable<T>(optional value: T, key: String, transaction: DBWriteTransaction) throws where T: Encodable {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        try setCodable(optional: value, key: key, transaction: sdsTx)
    }

    public func getCodableValue<T>(forKey key: String, transaction: DBReadTransaction) throws -> T? where T: Decodable {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return try getCodableValue(forKey: key, transaction: sdsTx)
    }

    public func allCodableValues<T>(transaction: DBReadTransaction) throws -> [T] where T: Decodable {
        let sdsTx = SDSDB.shimOnlyBridge(transaction)
        return try allCodableValues(transaction: sdsTx)
    }

}
