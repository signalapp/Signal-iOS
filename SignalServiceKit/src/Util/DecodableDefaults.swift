//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

// Based on https://www.swiftbysundell.com/tips/default-decoding-values/

public protocol DecodableDefaultSource {
    associatedtype Value: Decodable
    static var defaultValue: Value { get }
}

public enum DecodableDefault {
    @propertyWrapper
    public struct Wrapper<Source: DecodableDefaultSource> {
        public typealias Value = Source.Value
        public var wrappedValue = Source.defaultValue
        public init() {}
        public init(wrappedValue: Value) {
            self.wrappedValue = wrappedValue
        }
    }
}

extension DecodableDefault.Wrapper: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = try container.decode(Value.self)
    }
}

extension KeyedDecodingContainer {
    func decode<T>(
        _ type: DecodableDefault.Wrapper<T>.Type,
        forKey key: Key
    ) throws -> DecodableDefault.Wrapper<T> {
        try decodeIfPresent(type, forKey: key) ?? .init()
    }
}

public extension DecodableDefault {
    typealias Source = DecodableDefaultSource
    typealias DecodableBooleanLiteral = Decodable & ExpressibleByBooleanLiteral
    typealias DecodableIntegerLiteral = Decodable & ExpressibleByIntegerLiteral
    typealias DecodableFloatLiteral = Decodable & ExpressibleByFloatLiteral
    typealias DecodableStringLiteral = Decodable & ExpressibleByStringLiteral
    typealias DecodableArrayLiteral = Decodable & ExpressibleByArrayLiteral
    typealias DecodableDictionaryLiteral = Decodable & ExpressibleByDictionaryLiteral

    enum Sources {
        public enum True<T: DecodableBooleanLiteral>: Source {
            public static var defaultValue: T { true }
        }

        public enum False<T: DecodableBooleanLiteral>: Source {
            public static var defaultValue: T { false }
        }

        public enum Zero<T: DecodableIntegerLiteral>: Source {
            public static var defaultValue: T { 0 }
        }

        public enum One<T: DecodableIntegerLiteral>: Source {
            public static var defaultValue: T { 1 }
        }

        public enum ZeroFloat<T: DecodableFloatLiteral>: Source {
            public static var defaultValue: T { 0.0 }
        }

        public enum OneFloat<T: DecodableFloatLiteral>: Source {
            public static var defaultValue: T { 1.0 }
        }

        public enum EmptyString<T: DecodableStringLiteral>: Source {
            public static var defaultValue: T { "" }
        }

        public enum EmptyArray<T: DecodableArrayLiteral>: Source {
            public static var defaultValue: T { [] }
        }

        public enum EmptyDictionary<T: DecodableDictionaryLiteral>: Source {
            public static var defaultValue: T { [:] }
        }

        public enum GenerateUUIDString: Source {
            public static var defaultValue: String { UUID().uuidString }
        }

        public enum OutgoingMessageSending: Source {
            public static var defaultValue: OWSOutgoingMessageRecipientState { .sending }
        }
    }
}

public extension DecodableDefault {
    typealias GenerateUUIDString = Wrapper<Sources.GenerateUUIDString>
    typealias OutgoingMessageSending = Wrapper<Sources.OutgoingMessageSending>
    typealias True<T: DecodableBooleanLiteral> = Wrapper<Sources.True<T>>
    typealias False<T: DecodableBooleanLiteral> = Wrapper<Sources.False<T>>
    typealias Zero<T: DecodableIntegerLiteral> = Wrapper<Sources.Zero<T>>
    typealias One<T: DecodableIntegerLiteral> = Wrapper<Sources.One<T>>
    typealias ZeroFloat<T: DecodableFloatLiteral> = Wrapper<Sources.ZeroFloat<T>>
    typealias OneFloat<T: DecodableFloatLiteral> = Wrapper<Sources.OneFloat<T>>
    typealias EmptyString<T: DecodableStringLiteral> = Wrapper<Sources.EmptyString<T>>
    typealias EmptyArray<T: DecodableArrayLiteral> = Wrapper<Sources.EmptyArray<T>>
    typealias EmptyDictionary<T: DecodableDictionaryLiteral> = Wrapper<Sources.EmptyDictionary<T>>
}

extension DecodableDefault.Wrapper: Equatable where Value: Equatable {}
extension DecodableDefault.Wrapper: Hashable where Value: Hashable {}

extension DecodableDefault.Wrapper: Encodable where Value: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension DecodableDefault.Wrapper: CustomStringConvertible where Value: CustomStringConvertible {
    public var description: String { wrappedValue.description }
}

extension DecodableDefault.Wrapper: CustomDebugStringConvertible where Value: CustomDebugStringConvertible {
    public var debugDescription: String { wrappedValue.debugDescription }
}
