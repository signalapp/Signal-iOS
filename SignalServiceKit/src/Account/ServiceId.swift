//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public struct ServiceId: Equatable, Hashable, Codable, CustomDebugStringConvertible {
    private enum Constant {
        static let myStory = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        static let systemStory = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    }

    public static var myStory: ServiceId { ServiceId(Constant.myStory) }
    public static var systemStory: ServiceId { ServiceId(Constant.myStory) }

    public let uuidValue: UUID

    public init(_ uuidValue: UUID) {
        self.uuidValue = uuidValue
    }

    public init?(uuidString: String?) {
        guard let uuidString, let uuidValue = UUID(uuidString: uuidString) else {
            return nil
        }
        self.init(uuidValue)
    }

    public enum KnownValue {
        case myStory
        case systemStory
        case other(UUID)
    }

    public var knownValue: KnownValue {
        switch uuidValue {
        case Constant.myStory:
            return .myStory
        case Constant.systemStory:
            return .systemStory
        default:
            return .other(uuidValue)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(uuidValue)
    }

    public init(from decoder: Decoder) throws {
        self.uuidValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public var debugDescription: String { "<ServiceId \(uuidValue.uuidString)>" }
}

@objc
public class ServiceIdObjC: NSObject, NSCopying {
    public let wrappedValue: ServiceId

    public init(_ wrappedValue: ServiceId) {
        self.wrappedValue = wrappedValue
    }

    @objc
    public init(uuidValue: UUID) {
        self.wrappedValue = ServiceId(uuidValue)
    }

    @objc
    public init?(uuidString: String?) {
        guard let uuidString, let wrappedValue = ServiceId(uuidString: uuidString) else {
            return nil
        }
        self.wrappedValue = wrappedValue
    }

    @objc
    public var uuidValue: UUID { wrappedValue.uuidValue }

    @objc
    public override var hash: Int { uuidValue.hashValue }

    @objc
    public override func isEqual(_ object: Any?) -> Bool { uuidValue == (object as? ServiceIdObjC)?.uuidValue }

    @objc
    public func copy(with zone: NSZone? = nil) -> Any { self }

    @objc
    public override var description: String { wrappedValue.debugDescription }
}

// MARK: - DatabaseValueConvertible

extension ServiceId: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue { uuidValue.databaseValue }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> ServiceId? {
        UUID.fromDatabaseValue(dbValue).map { ServiceId($0) }
    }
}
