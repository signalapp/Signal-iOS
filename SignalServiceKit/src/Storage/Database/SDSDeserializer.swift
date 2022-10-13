//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

// This class can be used to convert database values to Swift values.
public class SDSDeserializer {
    private let sqliteStatement: SQLiteStatement

    public init(sqliteStatement: SQLiteStatement) {
        self.sqliteStatement = sqliteStatement
    }

    // MARK: - Blob

    public func blob(at index: Int32) throws -> Data {
        guard let value = try optionalBlob(at: index) else {
            owsFailDebug("Missing required filed: \(index)")
            throw SDSError.missingRequiredField
        }
        return value
    }

    public func optionalBlob(at index: Int32) throws -> Data? {
        let columnType = sqlite3_column_type(sqliteStatement, index)
        switch columnType {
        case SQLITE_NULL:
            return nil
        case SQLITE_BLOB:
            if let bytes = sqlite3_column_blob(sqliteStatement, index) {
                let count = Int(sqlite3_column_bytes(sqliteStatement, index))
               return Data(bytes: bytes, count: count)
            } else {
                // TODO: Should this throw?
               return Data()
            }
        default:
            owsFailDebug("Unexpected type: \(columnType)")
            throw SDSError.unexpectedType
        }
    }

    // MARK: - String

    public func string(at index: Int32) throws -> String {
        guard let value = try optionalString(at: index) else {
            owsFailDebug("Missing required filed: \(index)")
            throw SDSError.missingRequiredField
        }
        return value
    }

    public func optionalString(at index: Int32) throws -> String? {
        let columnType = sqlite3_column_type(sqliteStatement, index)
        switch columnType {
        case SQLITE_NULL:
            return nil
        case SQLITE_TEXT:
            return String(cString: sqlite3_column_text(sqliteStatement, index))
        default:
            owsFailDebug("Unexpected type: \(columnType)")
            throw SDSError.unexpectedType
        }
    }

    // MARK: - Int64

    public func int64(at index: Int32) throws -> Int64 {
        guard let value = try optionalInt64(at: index) else {
            owsFailDebug("Missing required filed: \(index)")
            throw SDSError.missingRequiredField
        }
        return value
    }

    public func optionalInt64(at index: Int32) throws -> Int64? {
        let columnType = sqlite3_column_type(sqliteStatement, index)
        switch columnType {
        case SQLITE_NULL:
            return nil
        case SQLITE_INTEGER:
            return sqlite3_column_int64(sqliteStatement, index)
        default:
            owsFailDebug("Unexpected type: \(columnType)")
            throw SDSError.unexpectedType
        }
    }

    // MARK: - Int

    public func int(at index: Int32) throws -> Int {
        guard let value = try optionalInt(at: index) else {
            owsFailDebug("Missing required filed: \(index)")
            throw SDSError.missingRequiredField
        }
        return value
    }

    public func optionalInt64AsNSNumber(at index: Int32) throws -> NSNumber? {
        guard let value = try optionalInt64(at: index) else {
            return nil
        }
        return NSNumber(value: value)
    }

    public func optionalInt(at index: Int32) throws -> Int? {
        let columnType = sqlite3_column_type(sqliteStatement, index)
        switch columnType {
        case SQLITE_NULL:
            return nil
        case SQLITE_INTEGER:
            return Int(sqlite3_column_int(sqliteStatement, index))
        default:
            owsFailDebug("Unexpected type: \(columnType)")
            throw SDSError.unexpectedType
        }
    }

    // MARK: - UInt64

    public func uint64(at index: Int32) throws -> UInt64 {
        guard let value = try optionalUInt64(at: index) else {
            owsFailDebug("Missing required filed: \(index)")
            throw SDSError.missingRequiredField
        }
        return value
    }

    public func optionalUInt64AsNSNumber(at index: Int32) throws -> NSNumber? {
        guard let value = try optionalUInt64(at: index) else {
            return nil
        }
        return NSNumber(value: value)
    }

    public func optionalUInt64(at index: Int32) throws -> UInt64? {
        let columnType = sqlite3_column_type(sqliteStatement, index)
        switch columnType {
        case SQLITE_NULL:
            return nil
        case SQLITE_INTEGER:
            return UInt64(sqlite3_column_int64(sqliteStatement, index))
        default:
            owsFailDebug("Unexpected type: \(columnType)")
            throw SDSError.unexpectedType
        }
    }

    // MARK: - Bool

    public func bool(at index: Int32) throws -> Bool {
        guard let value = try optionalBool(at: index) else {
            owsFailDebug("Missing required filed: \(index)")
            throw SDSError.missingRequiredField
        }
        return value
    }

    public func optionalBoolAsNSNumber(at index: Int32) throws -> NSNumber? {
        guard let value = try optionalBool(at: index) else {
            return nil
        }
        return NSNumber(value: value)
    }

    public func optionalBool(at index: Int32) throws -> Bool? {
        let columnType = sqlite3_column_type(sqliteStatement, index)
        switch columnType {
        case SQLITE_NULL:
            return nil
        case SQLITE_INTEGER:
            return sqlite3_column_int(sqliteStatement, index) > 0
        default:
            owsFailDebug("Unexpected type: \(columnType)")
            throw SDSError.unexpectedType
        }
    }

    // MARK: - Bool

    public func double(at index: Int32) throws -> Double {
        guard let value = try optionalDouble(at: index) else {
            owsFailDebug("Missing required filed: \(index)")
            throw SDSError.missingRequiredField
        }
        return value
    }

    public func optionalDoubleAsNSNumber(at index: Int32) throws -> NSNumber? {
        guard let value = try optionalDouble(at: index) else {
            return nil
        }
        return NSNumber(value: value)
    }

    public func optionalDouble(at index: Int32) throws -> Double? {
        let columnType = sqlite3_column_type(sqliteStatement, index)
        switch columnType {
        case SQLITE_NULL:
            return nil
        case SQLITE_FLOAT:
            return sqlite3_column_double(sqliteStatement, index)
        default:
            owsFailDebug("Unexpected type: \(columnType)")
            throw SDSError.unexpectedType
        }
    }

    // MARK: - Date

    public func date(at index: Int32) throws -> Date {
        guard let value = try optionalDate(at: index) else {
            owsFailDebug("Missing required filed: \(index)")
            throw SDSError.missingRequiredField
        }
        return value
    }

    public func optionalDate(at index: Int32) throws -> Date? {
        let columnType = sqlite3_column_type(sqliteStatement, index)
        switch columnType {
        case SQLITE_NULL:
            return nil
        case SQLITE_TEXT:
            let dateString = String(cString: sqlite3_column_text(sqliteStatement, index))
            guard let date = Date.fromDatabaseValue(dateString.databaseValue) else {
                owsFailDebug("Invalid value.")
                throw SDSError.invalidValue
            }
            return date
        default:
            owsFailDebug("Unexpected type: \(columnType)")
            throw SDSError.unexpectedType
        }
    }

    // MARK: - Archive

    public class func archive(_ value: Any?) -> Data? {
        guard let value = value else {
            return nil
        }
        return NSKeyedArchiver.archivedData(withRootObject: value)
    }

    public class func optionalUnarchive<T>(_ encoded: Data?) throws -> T? {
        guard let encoded = encoded else {
            return nil
        }
        return try unarchive(encoded)
    }

    public class func unarchive<T>(_ encoded: Data) throws -> T {
        do {
            guard let decoded = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encoded) as? T else {
                owsFailDebug("Invalid value.")
                throw SDSError.invalidValue
            }
            return decoded
        } catch {
            owsFailDebug("Read failed: \(error).")
            throw SDSError.invalidValue
        }
    }
}
