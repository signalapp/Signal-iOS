//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalCoreKit

// This class can be used to convert database values to Swift values.
//
// TODO: Maybe we should rename this to a SDSSerializer protocol and
//       move these methods to an extension?
public class SDSDeserialization {

    private init() {}

//    // MARK: - Blob
//    
//    public class func blob(data: Data?, name: String) throws -> Data {
//        guard let value = try optionalBlob(data: data) else {
//            owsFailDebug("Missing required field: \(name).")
//            throw SDSError.missingRequiredField
//        }
//        return value
//    }
//    
//    public class func optionalBlob(data: Data?, name: String) throws -> Data? {
//        return data
//    }

    // MARK: - Data

    public class func data(_ value: Data?, name: String) throws -> Data {
        guard let value = value else {
            owsFailDebug("Missing required field: \(name).")
            throw SDSError.missingRequiredField
        }
        return value
    }

    public class func optionalData(_ value: Data?, name: String) -> Data? {
        return value
    }

    // MARK: - String

    public class func string(_ value: String?, name: String) throws -> String {
        guard let value = value else {
            owsFailDebug("Missing required field: \(name).")
            throw SDSError.missingRequiredField
        }
        return value
    }

    public class func optionalString(_ value: String?, name: String) -> String? {
        return value
    }

    // MARK: - Numeric Primitive

    public class func numeric<T>(_ value: T?, name: String) throws -> T {
        guard let value = value else {
            owsFailDebug("Missing required field: \(name).")
            throw SDSError.missingRequiredField
        }
        return value
    }

    public class func optionalNumericAsNSNumber<T>(_ value: T?, name: String, conversion: (T) -> NSNumber) -> NSNumber? {
        guard let value = value else {
            return nil
        }
        return conversion(value)
    }

//    // MARK: - Int64
//
//    public class func int64(_ value: Int64?, name: String) throws -> Int64 {
//        guard let value = value else {
//            owsFailDebug("Missing required field: \(name).")
//            throw SDSError.missingRequiredField
//        }
//        return value
//    }
//
//    public class func optionalInt64AsNSNumber(_ value: Int64?, name: String) -> NSNumber? {
//        guard let value = value else {
//            return nil
//        }
//        return NSNumber(value: value)
//    }

//    public class func optionalInt64(data: Data?, name: String) throws -> Int64? {
//        let columnType = sqlite3_column_type(sqliteStatement, index)
//        switch columnType {
//        case SQLITE_NULL:
//            return nil
//        case SQLITE_INTEGER:
//            return sqlite3_column_int64(sqliteStatement, index)
//        default:
//            owsFailDebug("Unexpected type: \(columnType)")
//            throw SDSError.unexpectedType
//        }
//    }

//    // MARK: - Int
//
//    public class func int(_ value: Int?, name: String) throws -> Int {
//        guard let value = value else {
//            owsFailDebug("Missing required field: \(name).")
//            throw SDSError.missingRequiredField
//        }
//        return value
//    }
//
//    public class func optionalInt64AsNSNumber(_ value: Int?, name: String) -> NSNumber? {
//        guard let value = value else {
//            return nil
//        }
//        return NSNumber(value: value)
//    }

//    public class func optionalInt(data: Data?, name: String) throws -> Int? {
//        let columnType = sqlite3_column_type(sqliteStatement, index)
//        switch columnType {
//        case SQLITE_NULL:
//            return nil
//        case SQLITE_INTEGER:
//            return Int(sqlite3_column_int(sqliteStatement, index))
//        default:
//            owsFailDebug("Unexpected type: \(columnType)")
//            throw SDSError.unexpectedType
//        }
//    }

//    // MARK: - UInt64
//
//    public class func uint64(_ value: UInt64?, name: String) throws -> UInt64 {
//        guard let value = value else {
//            owsFailDebug("Missing required field: \(name).")
//            throw SDSError.missingRequiredField
//        }
//        return value
//    }
//
//    public class func optionalUInt64AsNSNumber(_ value: UInt64?, name: String) -> NSNumber? {
//        guard let value = value else {
//            return nil
//        }
//        return NSNumber(value: value)
//    }

//    public class func optionalUInt64(data: Data?, name: String) throws -> UInt64? {
//        let columnType = sqlite3_column_type(sqliteStatement, index)
//        switch columnType {
//        case SQLITE_NULL:
//            return nil
//        case SQLITE_INTEGER:
//            return UInt64(sqlite3_column_int64(sqliteStatement, index))
//        default:
//            owsFailDebug("Unexpected type: \(columnType)")
//            throw SDSError.unexpectedType
//        }
//    }

//    // MARK: - Bool
//
//    public class func bool(_ value: Bool?, name: String) throws -> Bool {
//        guard let value = value else {
//            owsFailDebug("Missing required field: \(name).")
//            throw SDSError.missingRequiredField
//        }
//        return value
//    }
//
//    public class func optionalBoolAsNSNumber(_ value: Bool?, name: String) -> NSNumber? {
//        guard let value = value else {
//            return nil
//        }
//        return NSNumber(value: value)
//    }

//    public class func optionalBool(data: Data?, name: String) throws -> Bool? {
//        let columnType = sqlite3_column_type(sqliteStatement, index)
//        switch columnType {
//        case SQLITE_NULL:
//            return nil
//        case SQLITE_INTEGER:
//            return sqlite3_column_int(sqliteStatement, index) > 0
//        default:
//            owsFailDebug("Unexpected type: \(columnType)")
//            throw SDSError.unexpectedType
//        }
//    }

//    // MARK: - Bool
//
//    public class func double(_ value: Double?, name: String) throws -> Double {
//        guard let value = value else {
//            owsFailDebug("Missing required field: \(name).")
//            throw SDSError.missingRequiredField
//        }
//        return value
//    }
//
//    public class func optionalDoubleAsNSNumber(_ value: Double?, name: String) -> NSNumber? {
//        guard let value = value else {
//            return nil
//        }
//        return NSNumber(value: value)
//    }

//    public class func optionalDouble(data: Data?, name: String) throws -> Double? {
//        let columnType = sqlite3_column_type(sqliteStatement, index)
//        switch columnType {
//        case SQLITE_NULL:
//            return nil
//        case SQLITE_FLOAT:
//            return sqlite3_column_double(sqliteStatement, index)
//        default:
//            owsFailDebug("Unexpected type: \(columnType)")
//            throw SDSError.unexpectedType
//        }
//    }

    // MARK: - Date

    public class func date(_ value: Date?, name: String) throws -> Date {
        guard let value = value else {
            owsFailDebug("Missing required field: \(name).")
            throw SDSError.missingRequiredField
        }
        return value
    }

    public class func optionalDate(_ value: Date?, name: String) -> Date? {
        return value
    }

    // MARK: - Blob

    public class func optionalUnarchive<T>(_ encoded: Data?, name: String) throws -> T? {
        guard let encoded = encoded else {
            return nil
        }
        return try unarchive(encoded, name: name)
    }

    public class func unarchive<T>(_ encoded: Data?, name: String) throws -> T {
        guard let encoded = encoded else {
            owsFailDebug("Missing required field: \(name).")
            throw SDSError.missingRequiredField
        }

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
