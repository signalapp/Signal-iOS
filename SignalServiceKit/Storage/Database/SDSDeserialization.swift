//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

// This class can be used to convert database values to Swift values.
//
// TODO: Maybe we should rename this to a SDSSerializer protocol and
//       move these methods to an extension?
public class SDSDeserialization {

    private init() {}

    // MARK: - Data

    public class func required<T>(
        _ value: T?,
        name: String,
        _ file: StaticString = #file,
        _ function: StaticString = #function,
        _ line: UInt = #line,
    ) throws -> T {
        guard let value else {
            owsFailDebug("Missing required field: \(name).")
            throw SDSError.missingRequiredField(file, function, line)
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
        guard let value else {
            return nil
        }
        return requiredDoubleAsDate(value, name: name)
    }

    // MARK: - Numeric Primitive

    public class func optionalNumericAsNSNumber<T>(_ value: T?, name: String, conversion: (T) -> NSNumber) -> NSNumber? {
        guard let value else {
            return nil
        }
        return conversion(value)
    }

    // MARK: - Blob

    public class func unarchivedObject<T: NSObject & NSSecureCoding>(
        ofClass cls: T.Type,
        from encodedValue: Data,
    ) throws -> T {
        let decodedValue = try NSKeyedUnarchiver.unarchivedObject(ofClass: cls, from: encodedValue)
        guard let decodedValue else {
            throw SDSError.invalidValue()
        }
        return decodedValue
    }

    public class func unarchivedArrayOfObjects<T: NSObject & NSSecureCoding>(
        ofClass cls: T.Type,
        from encodedValue: Data,
    ) throws -> [T] {
        let decodedValue = try NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: cls, from: encodedValue)
        guard let decodedValue else {
            throw SDSError.invalidValue()
        }
        return decodedValue
    }

    public class func unarchivedDictionary<K: NSObject & NSSecureCoding & NSCopying, V: NSObject & NSSecureCoding>(
        ofKeyClass keyClass: K.Type,
        objectClass: V.Type,
        from encodedValue: Data,
    ) throws -> [K: V] {
        let decodedValue = try NSKeyedUnarchiver.unarchivedDictionary(ofKeyClass: keyClass, objectClass: objectClass, from: encodedValue)
        guard let decodedValue else {
            throw SDSError.invalidValue()
        }
        return decodedValue
    }

    public class func unarchivedInfoDictionary(from encodedValue: Data) throws -> [InfoMessageUserInfoKey: AnyObject] {
        let decodedValue = try NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSDictionary.self, NSString.self] + TSInfoMessage.infoMessageUserInfoObjectClasses(),
            from: encodedValue,
        ) as? [InfoMessageUserInfoKey: AnyObject]
        guard let decodedValue else {
            throw SDSError.invalidValue()
        }
        return decodedValue
    }
}
