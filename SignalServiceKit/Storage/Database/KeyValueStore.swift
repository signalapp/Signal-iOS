//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public struct KeyValueStore {
    static var tableName: String { NewKeyValueStore.tableName }
    static var collectionColumnName: String { NewKeyValueStore.collectionColumnName }

    private let collection: String

    public init(collection: String) {
        self.collection = collection
    }

    // MARK: -

    public func hasValue(_ key: String, transaction: DBReadTransaction) -> Bool {
        return getData(key, transaction: transaction) != nil
    }

    // MARK: - String

    public func getString(_ key: String, transaction: DBReadTransaction) -> String? {
        return getObject(key, ofClass: NSString.self, transaction: transaction) as String?
    }

    public func setString(_ value: String?, key: String, transaction: DBWriteTransaction) {
        guard let value else {
            write(nil, forKey: key, transaction: transaction)
            return
        }
        write(value as NSString, forKey: key, transaction: transaction)
    }

    // MARK: - Date

    public func getDate(_ key: String, transaction: DBReadTransaction) -> Date? {
        // Our legacy methods sometimes stored dates as NSNumber and
        // sometimes as NSDate, so we are permissive when decoding.
        let value = getObject(key, ofClasses: [NSDate.self, NSNumber.self], transaction: transaction)
        if let dateValue = value as? NSDate {
            return dateValue as Date
        }
        if let numberValue = value as? NSNumber {
            return Date(timeIntervalSince1970: numberValue.doubleValue)
        }
        return nil
    }

    public func setDate(_ value: Date, key: String, transaction: DBWriteTransaction) {
        let epochInterval = NSNumber(value: value.timeIntervalSince1970)
        setObject(epochInterval, key: key, transaction: transaction)
    }

    // MARK: - Bool

    public func getBool(_ key: String, transaction: DBReadTransaction) -> Bool? {
        return getNSNumber(key, transaction: transaction)?.boolValue
    }

    public func getBool(_ key: String, defaultValue: Bool, transaction: DBReadTransaction) -> Bool {
        return getBool(key, transaction: transaction) ?? defaultValue
    }

    public func setBool(_ value: Bool, key: String, transaction: DBWriteTransaction) {
        write(NSNumber(value: value), forKey: key, transaction: transaction)
    }

    // MARK: - UInt

    public func getUInt(_ key: String, transaction: DBReadTransaction) -> UInt? {
        return getNSNumber(key, transaction: transaction)?.uintValue
    }

    public func getUInt(_ key: String, defaultValue: UInt, transaction: DBReadTransaction) -> UInt {
        return getUInt(key, transaction: transaction) ?? defaultValue
    }

    public func setUInt(_ value: UInt, key: String, transaction: DBWriteTransaction) {
        write(NSNumber(value: value), forKey: key, transaction: transaction)
    }

    // MARK: - Data

    public func getData(_ key: String, transaction: DBReadTransaction) -> Data? {
        return NewKeyValueStore(collection: collection).fetchValue(Data.self, forKey: key, tx: transaction)
    }

    public func setData(_ data: Data?, key: String, transaction tx: DBWriteTransaction) {
        NewKeyValueStore(collection: collection).writeValue(data, forKey: key, tx: tx)
    }

    // MARK: - Int

    public func getInt(_ key: String, transaction: DBReadTransaction) -> Int? {
        return getNSNumber(key, transaction: transaction)?.intValue
    }

    public func getInt(_ key: String, defaultValue: Int, transaction: DBReadTransaction) -> Int {
        return getInt(key, transaction: transaction) ?? defaultValue
    }

    public func setInt(_ value: Int, key: String, transaction: DBWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - Int32

    public func getInt32(_ key: String, transaction: DBReadTransaction) -> Int32? {
        return getNSNumber(key, transaction: transaction)?.int32Value
    }

    public func getInt32(_ key: String, defaultValue: Int32, transaction: DBReadTransaction) -> Int32 {
        return getInt32(key, transaction: transaction) ?? defaultValue
    }

    public func setInt32(_ value: Int32, key: String, transaction: DBWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - UInt32

    public func getUInt32(_ key: String, transaction: DBReadTransaction) -> UInt32? {
        return getNSNumber(key, transaction: transaction)?.uint32Value
    }

    public func getUInt32(_ key: String, defaultValue: UInt32, transaction: DBReadTransaction) -> UInt32 {
        return getUInt32(key, transaction: transaction) ?? defaultValue
    }

    public func setUInt32(_ value: UInt32, key: String, transaction: DBWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - UInt64

    public func getUInt64(_ key: String, transaction: DBReadTransaction) -> UInt64? {
        return getNSNumber(key, transaction: transaction)?.uint64Value
    }

    public func getUInt64(_ key: String, defaultValue: UInt64, transaction: DBReadTransaction) -> UInt64 {
        return getUInt64(key, transaction: transaction) ?? defaultValue
    }

    public func setUInt64(_ value: UInt64, key: String, transaction: DBWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - Int64

    public func getInt64(_ key: String, transaction: DBReadTransaction) -> Int64? {
        return getNSNumber(key, transaction: transaction)?.int64Value
    }

    public func getInt64(_ key: String, defaultValue: Int64, transaction: DBReadTransaction) -> Int64 {
        return getInt64(key, transaction: transaction) ?? defaultValue
    }

    public func setInt64(_ value: Int64, key: String, transaction: DBWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - Double

    public func getDouble(_ key: String, transaction: DBReadTransaction) -> Double? {
        return getNSNumber(key, transaction: transaction)?.doubleValue
    }

    public func getDouble(_ key: String, defaultValue: Double, transaction: DBReadTransaction) -> Double {
        return getDouble(key, transaction: transaction) ?? defaultValue
    }

    public func setDouble(_ value: Double, key: String, transaction: DBWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - Object

    public func setObject(_ anyValue: Any?, key: String, transaction: DBWriteTransaction) {
        guard let anyValue else {
            write(nil, forKey: key, transaction: transaction)
            return
        }
        guard let codingValue = anyValue as? NSCoding else {
            owsFailDebug("Invalid value.")
            write(nil, forKey: key, transaction: transaction)
            return
        }
        write(codingValue, forKey: key, transaction: transaction)
    }

    // MARK: -

    public func removeValue(forKey key: String, transaction: DBWriteTransaction) {
        write(nil, forKey: key, transaction: transaction)
    }

    public func removeValues(forKeys keys: [String], transaction: DBWriteTransaction) {
        for key in keys {
            write(nil, forKey: key, transaction: transaction)
        }
    }

    public func removeAll(transaction tx: DBWriteTransaction) {
        NewKeyValueStore(collection: collection).removeAll(tx: tx)
    }

    public func allDataValues(transaction: DBReadTransaction) -> [Data] {
        return allKeys(transaction: transaction).compactMap { key in
            return self.getData(key, transaction: transaction)
        }
    }

    // MARK: -

    public func anyDataValue(transaction: DBReadTransaction) -> Data? {
        let randomKey = allKeys(transaction: transaction).randomElement()
        guard let randomKey else {
            return nil
        }
        guard let dataValue = self.getData(randomKey, transaction: transaction) else {
            owsFailDebug("Couldn't fetch random element")
            return nil
        }
        return dataValue
    }

    public func allKeys(transaction tx: DBReadTransaction) -> [String] {
        return NewKeyValueStore(collection: collection).fetchKeys(tx: tx)
    }

    // MARK: -

    @available(*, deprecated, message: "Did you mean removeValue(forKey:transaction:) or setCodable(optional:key:transaction)?")
    public func setCodable<T: Encodable>(_ value: T?, key: String, transaction: DBWriteTransaction) throws {
        try setCodable(optional: value, key: key, transaction: transaction)
    }

    public func setCodable<T: Encodable>(_ value: T, key: String, transaction: DBWriteTransaction) throws {
        // The only difference between setCodable(optional:...) and setCodable(_...) is
        // the non-optional variant has a deprecated overload to warn callers of the ambiguity.
        try setCodable(optional: value, key: key, transaction: transaction)
    }

    public func setCodable<T: Encodable>(optional value: T, key: String, transaction: DBWriteTransaction) throws {
        do {
            let data = try JSONEncoder().encode(value)
            setData(data, key: key, transaction: transaction)
        } catch {
            owsFailDebug("Failed to encode: \(error).")
            throw error
        }
    }

    public func getCodableValue<T: Decodable>(forKey key: String, failDebugOnParseError: Bool = true, transaction: DBReadTransaction) throws -> T? {
        guard let data = getData(key, transaction: transaction) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if failDebugOnParseError {
                owsFailDebug("Failed to decode: \(error).")
            } else {
                Logger.warn("Failed to decode: \(error).")
            }
            throw error
        }
    }

    public func allCodableValues<T: Decodable>(transaction: DBReadTransaction) throws -> [T] {
        var result = [T]()
        for data in allDataValues(transaction: transaction) {
            do {
                result.append(try JSONDecoder().decode(T.self, from: data))
            } catch {
                owsFailDebug("Failed to decode: \(error).")
                throw error
            }
        }
        return result
    }

    // MARK: - Archived Values

    public func getObject<ObjectType: NSObject & NSSecureCoding>(_ key: String, ofClass cls: ObjectType.Type, transaction: DBReadTransaction) -> ObjectType? {
        return self.getData(key, transaction: transaction).flatMap { self.parseArchivedValue($0, ofClass: cls) }
    }

    public func getObject(_ key: String, ofClasses classes: [AnyClass], transaction: DBReadTransaction) -> Any? {
        return self.getData(key, transaction: transaction).flatMap {
            do {
                return try NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: $0)
            } catch {
                owsFailDebug("Couldn't decode value.")
                return nil
            }
        }
    }

    private func parseArchivedValue<DecodedObject: NSObject & NSSecureCoding>(_ encodedData: Data, ofClass cls: DecodedObject.Type) -> DecodedObject? {
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: cls, from: encodedData)
        } catch {
            owsFailDebug("Couldn't decode value.")
            return nil
        }
    }

    private func getNSNumber(_ key: String, transaction: DBReadTransaction) -> NSNumber? {
        return getObject(key, ofClass: NSNumber.self, transaction: transaction)
    }

    public func getDictionary<DecodedKey: NSObject & NSCopying & NSSecureCoding, DecodedObject: NSObject & NSSecureCoding>(
        _ key: String,
        keyClass: DecodedKey.Type,
        objectClass: DecodedObject.Type,
        transaction: DBReadTransaction,
    ) -> [DecodedKey: DecodedObject]? {
        return self.getData(key, transaction: transaction).flatMap {
            do {
                return try NSKeyedUnarchiver.unarchivedDictionary(ofKeyClass: keyClass, objectClass: objectClass, from: $0)
            } catch {
                owsFailDebug("Decode failed.")
                return nil
            }
        }
    }

    public func getArray<DecodedObject: NSObject & NSSecureCoding>(_ key: String, ofClass cls: DecodedObject.Type, transaction: DBReadTransaction) -> [DecodedObject]? {
        return self.getData(key, transaction: transaction).flatMap {
            do {
                return try NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: cls, from: $0)
            } catch {
                owsFailDebug("Decode failed.")
                return nil
            }
        }
    }

    public func getStringArray(_ key: String, transaction: DBReadTransaction) -> [String]? {
        return self.getArray(key, ofClass: NSString.self, transaction: transaction) as [String]?
    }

    public func getSet<DecodedObject: NSObject & NSSecureCoding>(_ key: String, ofClass cls: DecodedObject.Type, transaction: DBReadTransaction) -> Set<DecodedObject>? {
        return self.getObject(key, ofClasses: [NSSet.self, cls], transaction: transaction) as? Set<DecodedObject>
    }

    // MARK: - Internal Methods

    private func write(
        _ value: NSCoding?,
        forKey key: String,
        transaction: DBWriteTransaction,
    ) {
        let encoded: Data? = value.flatMap {
            try? NSKeyedArchiver.archivedData(
                withRootObject: $0,
                requiringSecureCoding: false,
            )
        }

        setData(encoded, key: key, transaction: transaction)
    }
}
