// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

// MARK: - Setting

public struct Setting: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "settings" }
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case key
        case value
    }
    
    public var id: String { key }
    
    let key: String
    let value: Data
}

extension Setting {
    fileprivate init?<T>(key: String, value: T?) {
        guard let value: T = value else { return nil }
        
        var targetValue: T = value
        
        self.key = key
        self.value = Data(bytes: &targetValue, count: MemoryLayout.size(ofValue: targetValue))
    }
    
    fileprivate func value<T>(as type: T.Type) -> T {
        return value.withUnsafeBytes { $0.load(as: T.self) }
    }
}

// MARK: - Keys

public extension Setting {
    struct BoolKey: RawRepresentable, ExpressibleByStringLiteral {
        public let rawValue: String
        
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init?(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.init(value) }
        public init(unicodeScalarLiteral value: String) { self.init(value) }
        public init(extendedGraphemeClusterLiteral value: String) { self.init(value) }
    }
    
    struct DateKey: RawRepresentable, ExpressibleByStringLiteral {
        public let rawValue: String
        
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init?(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.init(value) }
        public init(unicodeScalarLiteral value: String) { self.init(value) }
        public init(extendedGraphemeClusterLiteral value: String) { self.init(value) }
    }
    
    struct DoubleKey: RawRepresentable, ExpressibleByStringLiteral {
        public let rawValue: String
        
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init?(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.init(value) }
        public init(unicodeScalarLiteral value: String) { self.init(value) }
        public init(extendedGraphemeClusterLiteral value: String) { self.init(value) }
    }
    
    struct IntKey: RawRepresentable, ExpressibleByStringLiteral {
        public let rawValue: String
        
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init?(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.init(value) }
        public init(unicodeScalarLiteral value: String) { self.init(value) }
        public init(extendedGraphemeClusterLiteral value: String) { self.init(value) }
    }
    
    struct StringKey: RawRepresentable, ExpressibleByStringLiteral {
        public let rawValue: String
        
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init?(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.init(value) }
        public init(unicodeScalarLiteral value: String) { self.init(value) }
        public init(extendedGraphemeClusterLiteral value: String) { self.init(value) }
    }
}

// MARK: - Database Access

public extension GRDBStorage {
    subscript(key: Setting.BoolKey) -> Bool? { return read { db in db[key] } }
    subscript(key: Setting.DoubleKey) -> Double? { return read { db in db[key] } }
    subscript(key: Setting.IntKey) -> Int? { return read { db in db[key] } }
    subscript(key: Setting.StringKey) -> String? { return read { db in db[key] } }
    subscript(key: Setting.DateKey) -> Date? { return read { db in db[key] } }
}

public extension Database {
    private subscript(key: String) -> Setting? {
        get { try? Setting.filter(id: key).fetchOne(self) }
        set {
            guard let newValue: Setting = newValue else {
                _ = try? Setting.filter(id: key).deleteAll(self)
                return
            }
            
            try? newValue.save(self)
        }
    }
    
    subscript(key: Setting.BoolKey) -> Bool? {
        get { self[key.rawValue]?.value(as: Bool.self) }
        set { self[key.rawValue] = Setting(key: key.rawValue, value: newValue) }
    }
    
    subscript(key: Setting.DoubleKey) -> Double? {
        get { self[key.rawValue]?.value(as: Double.self) }
        set { self[key.rawValue] = Setting(key: key.rawValue, value: newValue) }
    }
    
    subscript(key: Setting.IntKey) -> Int? {
        get { self[key.rawValue]?.value(as: Int.self) }
        set { self[key.rawValue] = Setting(key: key.rawValue, value: newValue) }
    }
    
    subscript(key: Setting.StringKey) -> String? {
        get { self[key.rawValue]?.value(as: String.self) }
        set { self[key.rawValue] = Setting(key: key.rawValue, value: newValue) }
    }
    
    /// Value will be stored as a timestamp in seconds since 1970
    subscript(key: Setting.DateKey) -> Date? {
        get {
            let timestamp: TimeInterval? = self[key.rawValue]?.value(as: TimeInterval.self)
            
            return timestamp.map { Date(timeIntervalSince1970: $0) }
        }
        set {
            self[key.rawValue] = Setting(
                key: key.rawValue,
                value: newValue.map { $0.timeIntervalSince1970 }
            )
        }
    }
}
