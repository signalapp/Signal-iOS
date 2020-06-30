//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

    public enum ParseError: Error, CustomStringConvertible {
        case missingField(Key)
        case invalidFormat(_ key: Key, description: String? = nil)

        public var description: String {
            switch self {
            case .missingField(let key):
                return "ParseError: missing field for \(key)"
            case .invalidFormat(let key, let description):
                if let description = description {
                    return "ParseError: invalid format for \(key) - \(description)"
                } else {
                    return "ParseError: invalid format for \(key)"
                }
            }
        }
    }

    private func badCast<T>(key: Key, type: T.Type) -> ParseError {
        let description = "Could not cast result to expected type: \(T.self)."
        return ParseError.invalidFormat(key, description: description)
    }

    private func invalid(key: Key) -> ParseError {
        return ParseError.invalidFormat(key)
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
            throw badCast(key: key, type: T.self)
        }

        return typedValue
    }

    public func hasKey(_ key: Key) -> Bool {
        return dictionary[key] != nil && !(dictionary[key] is NSNull)
    }

    // MARK: FixedWidthIntegers (e.g. Int, Int32, UInt, UInt32, etc.)

    // You can't blindly cast accross Integer types, so we need to specify and validate which Int type we want.
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
                throw badCast(key: key, type: T.self)
            }
            return T(int)
        default:
            throw badCast(key: key, type: T.self)
        }
    }

    // MARK: Base64 Data

    public func requiredBase64EncodedData(key: Key, byteCount: Int? = nil) throws -> Data {
        guard let data: Data = try optionalBase64EncodedData(key: key, byteCount: byteCount) else {
            throw ParseError.missingField(key)
        }

        return data
    }

    public func optionalBase64EncodedData(key: Key, byteCount: Int? = nil) throws -> Data? {
        guard let encodedData: String = try self.optional(key: key) else {
            return nil
        }

        guard let data = Data(base64Encoded: encodedData) else {
            throw ParseError.invalidFormat(key)
        }

        if let byteCount = byteCount {
            guard data.count == byteCount else {
                throw ParseError.invalidFormat(key, description: "expected byteCount: \(byteCount) but found: \(data.count)")
            }
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
