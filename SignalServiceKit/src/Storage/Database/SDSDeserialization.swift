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

    // MARK: - Numeric Primitive

    public class func optionalNumericAsNSNumber<T>(_ value: T?, name: String, conversion: (T) -> NSNumber) -> NSNumber? {
        guard let value = value else {
            return nil
        }
        return conversion(value)
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
