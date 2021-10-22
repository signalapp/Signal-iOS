//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import SignalCoreKit

// Sentinel protocol used to convey that a Codable type should be encoded/decoded to database storage
// using Swift.Codable instead of NS(Secure)Coding.
public protocol SDSSwiftSerializable: Codable {}
extension Array: SDSSwiftSerializable where Element: SDSSwiftSerializable {}
extension Dictionary: SDSSwiftSerializable where Key: SDSSwiftSerializable, Value: SDSSwiftSerializable {}
extension Set: SDSSwiftSerializable where Element: SDSSwiftSerializable {}
extension Optional: SDSSwiftSerializable where Wrapped: SDSSwiftSerializable {}

// This class can be used to convert database values to Swift values.
//
// TODO: Maybe we should rename this to a SDSSerializer protocol and
//       move these methods to an extension?
public class SDSDeserialization {

    private init() {}

    // MARK: - Data

    public class func required<T>(_ value: T?, name: String) throws -> T {
        guard let value = value else {
            owsFailDebug("Missing required field: \(name).")
            throw SDSError.missingRequiredField
        }
        return value
    }

    // MARK: - Data

    public class func optionalData(_ value: Data?, name: String) -> Data? {
        return value
    }

    // MARK: - Date

    public class func requiredDoubleAsDate(_ value: Double, name: String) -> Date {
        return Date(timeIntervalSince1970: value)
    }

    public class func optionalDoubleAsDate(_ value: Double?, name: String) -> Date? {
        guard let value = value else {
            return nil
        }
        return requiredDoubleAsDate(value, name: name)
    }

    // MARK: - Numeric Primitive

    public class func optionalNumericAsNSNumber<T>(_ value: T?, name: String, conversion: (T) -> NSNumber) -> NSNumber? {
        guard let value = value else {
            return nil
        }
        return conversion(value)
    }

    // MARK: - Blob

    public class func optionalUnarchive<T: SDSSwiftSerializable>(_ encoded: Data?, name: String) throws -> T? {
        guard let encoded = encoded else {
            return nil
        }
        return try unarchive(encoded, name: name)
    }

    public class func unarchive<T: SDSSwiftSerializable>(_ encoded: Data?, name: String) throws -> T {
        guard let encoded = encoded else {
            owsFailDebug("Missing required field: \(name).")
            throw SDSError.missingRequiredField
        }

        do {
            return try JSONDecoder().decode(T.self, from: encoded)
        } catch {
            owsFailDebug("Read failed[\(name)]: \(error).")
            throw SDSError.invalidValue
        }
    }

    public class func optionalUnarchive<T: Any>(_ encoded: Data?, name: String) throws -> T? {
        guard let encoded = encoded else {
            return nil
        }
        return try unarchive(encoded, name: name)
    }

    public class func unarchive<T: Any>(_ encoded: Data?, name: String) throws -> T {
        guard let encoded = encoded else {
            owsFailDebug("Missing required field: \(name).")
            throw SDSError.missingRequiredField
        }

        do {
            guard let decoded = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encoded) as? T else {
                owsFailDebug("Invalid value: \(name).")
                throw SDSError.invalidValue
            }
            return decoded
        } catch {
            owsFailDebug("Read failed[\(name)]: \(error).")
            throw SDSError.invalidValue
        }
    }
}
