//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// A DSL for parsing expected and optional values from a Dictionary, appropriate for
// validating a service response.
//
// Additionally it includes some helpers to DRY up common conversions.
//
// Rather than exhaustively enumerate accessors for types like `requireUInt32`, `requireInt64`, etc.
// We instead leverage generics at the call site.
//
//     do {
//         // Required
//         let name: String = try paramParser.required(key: "name")
//         let count: UInt32 = try paramParser.required(key: "count")
//
//         // Optional
//         let lastSeen: Date? = try paramParser.optional(key: "last_seen")
//
//         return Foo(name: name, count: count, isNew: lastSeen == nil)
//     } catch {
//         handleInvalidResponse(error: error)
//     }
//
public class ParamParser {
    public typealias Key = String

    let dictionary: [Key: Any]

    public init(dictionary: [Key: Any]) {
        self.dictionary = dictionary
    }

    public convenience init?(responseObject: Any?) {
        guard let responseDict = responseObject as? [String: AnyObject] else {
            return nil
        }

        self.init(dictionary: responseDict)
    }

    // MARK: Errors

    private enum ParseError: Error, CustomStringConvertible {
        case missingField(Key)
        case invalidType(Key, expectedType: Any.Type, actualType: Any.Type)
        case intValueOutOfBounds(Key)
        case invalidUuidString(Key)
        case invalidBase64DataString(Key)

        var description: String {
            switch self {
            case .missingField(let key):
                return "ParseError: Missing field for key \(key)!"
            case .invalidType(let key, let expectedType, let actualType):
                return "ParseError: Invalid type for key \(key)! Expected \(expectedType), found \(actualType)"
            case .intValueOutOfBounds(let key):
                return "ParseError: Int value was out of bounds for key \(key)!"
            case .invalidUuidString(let key):
                return "ParseError: Invalid UUID string for key \(key)!"
            case .invalidBase64DataString(let key):
                return "ParseError: Invalid base64 data string for key \(key)!"
            }
        }
    }

    private func badCast<T>(key: Key, expectedType: T.Type, castTarget: Any) -> ParseError {
        return .invalidType(key, expectedType: expectedType, actualType: type(of: castTarget))
    }

    private func missing(key: Key) -> ParseError {
        return ParseError.missingField(key)
    }

    // MARK: - Public API

    public func required<T>(key: Key) throws -> T {
        guard let value: T = try optional(key: key) else {
            throw missing(key: key)
        }

        return value
    }

    public func optional<T>(key: Key) throws -> T? {
        guard let someValue = dictionary[key] else {
            return nil
        }

        guard !(someValue is NSNull) else {
            return nil
        }

        guard let typedValue = someValue as? T else {
            throw badCast(key: key, expectedType: T.self, castTarget: someValue)
        }

        return typedValue
    }

    public func hasKey(_ key: Key) -> Bool {
        return dictionary[key] != nil && !(dictionary[key] is NSNull)
    }

    // MARK: FixedWidthIntegers (e.g. Int, Int32, UInt, UInt32, etc.)

    // You can't blindly cast across Integer types, so we need to specify and validate which Int type we want.
    // In general, you'll find numeric types parsed into a Dictionary as `Int`.

    public func required<T>(key: Key) throws -> T where T: FixedWidthInteger {
        guard let value: T = try optional(key: key) else {
            throw missing(key: key)
        }

        return value
    }

    public func optional<T>(key: Key) throws -> T? where T: FixedWidthInteger {
        guard let someValue: Any = try optional(key: key) else {
            return nil
        }

        switch someValue {
        case let typedValue as T:
            return typedValue
        case let int as Int:
            guard int >= T.min, int <= T.max else {
                throw ParseError.intValueOutOfBounds(key)
            }
            return T(int)
        default:
            throw badCast(key: key, expectedType: T.self, castTarget: someValue)
        }
    }

    // MARK: UUIDs

    public func required(key: Key) throws -> UUID {
        guard let value: UUID = try optional(key: key) else {
            throw missing(key: key)
        }

        return value
    }

    public func optional(key: Key) throws -> UUID? {
        guard let uuidString: String = try optional(key: key) else {
            return nil
        }

        guard let uuid = UUID(uuidString: uuidString) else {
            throw ParseError.invalidUuidString(key)
        }

        return uuid
    }

    // MARK: Base64 Data

    public func requiredBase64EncodedData(key: Key) throws -> Data {
        guard let data: Data = try optionalBase64EncodedData(key: key) else {
            throw ParseError.missingField(key)
        }

        return data
    }

    public func optionalBase64EncodedData(key: Key) throws -> Data? {
        guard let encodedData: String = try self.optional(key: key) else {
            return nil
        }

        guard let data = Data(base64Encoded: encodedData) else {
            throw ParseError.invalidBase64DataString(key)
        }

        guard data.count > 0 else {
            return nil
        }

        return data
    }
}

extension ParamParser: CustomDebugStringConvertible {
    public var debugDescription: String {
        "<ParamParser: \(dictionary)>"
    }
}
