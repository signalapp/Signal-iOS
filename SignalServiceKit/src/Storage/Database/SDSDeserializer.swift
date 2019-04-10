//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
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
            throw SDSError.unexpectedType
        }
    }

    // MARK: - String

    public func string(at index: Int32) throws -> String {
        guard let value = try optionalString(at: index) else {
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
            throw SDSError.unexpectedType
        }
    }

    // MARK: - Int64

    public func int64(at index: Int32) throws -> Int64 {
        guard let value = try optionalInt64(at: index) else {
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
            throw SDSError.unexpectedType
        }
    }

    // MARK: - Int

    public func int(at index: Int32) throws -> Int {
        guard let value = try optionalInt(at: index) else {
            throw SDSError.missingRequiredField
        }
        return value
    }

    public func optionalInt(at index: Int32) throws -> Int? {
        let columnType = sqlite3_column_type(sqliteStatement, index)
        switch columnType {
        case SQLITE_NULL:
            return nil
        case SQLITE_INTEGER:
            return Int(sqlite3_column_int(sqliteStatement, index))
        default:
            throw SDSError.unexpectedType
        }
    }

    // MARK: - Bool

    public func bool(at index: Int32) throws -> Bool {
        guard let value = try optionalBool(at: index) else {
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
            throw SDSError.unexpectedType
        }
    }

    // MARK: - Date

    public func date(at index: Int32) throws -> Date {
        guard let value = try optionalDate(at: index) else {
            throw SDSError.missingRequiredField
        }
        return value
    }

    public func optionalDate(at index: Int32) throws -> Date? {
        let columnType = sqlite3_column_type(sqliteStatement, index)
        switch columnType {
        case SQLITE_NULL:
            return nil
        case SQLITE_INTEGER:
            // TODO: Revisit Date persistence.
            let value = UInt64(sqlite3_column_int64(sqliteStatement, index))
            return NSDate.ows_date(withMillisecondsSince1970: value)
        default:
            throw SDSError.unexpectedType
        }
    }

    // MARK: - Archive

    public class func unarchive<T>(_ encoded: Data) throws -> T {
        do {
            guard let decoded = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encoded) as? T else {
                throw SDSError.invalidValue
            }
            return decoded
        } catch let error {
            owsFailDebug("Read failed: \(error).")
            throw SDSError.invalidValue
        }
    }
}
