//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import GRDB

public struct UntypedServiceId: Equatable, Hashable, Codable, CustomDebugStringConvertible {
    private enum Constant {
        static let myStory = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        static let systemStory = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    }

    public static var myStory: UntypedServiceId { UntypedServiceId(Constant.myStory) }
    public static var systemStory: UntypedServiceId { UntypedServiceId(Constant.myStory) }

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

    public static func expectNilOrValid(uuidString: String?) -> UntypedServiceId? {
        let result = UntypedServiceId(uuidString: uuidString)
        owsAssertDebug(uuidString == nil || result != nil, "Couldn't parse a ServiceId that should be valid")
        return result
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
public class UntypedServiceIdObjC: NSObject, NSCopying {
    public let wrappedValue: UntypedServiceId

    public init(_ wrappedValue: UntypedServiceId) {
        self.wrappedValue = wrappedValue
    }

    @objc
    public init(uuidValue: UUID) {
        self.wrappedValue = UntypedServiceId(uuidValue)
    }

    @objc
    public init?(uuidString: String?) {
        guard let uuidString, let wrappedValue = UntypedServiceId(uuidString: uuidString) else {
            return nil
        }
        self.wrappedValue = wrappedValue
    }

    @objc
    public var uuidValue: UUID { wrappedValue.uuidValue }

    @objc
    public override var hash: Int { uuidValue.hashValue }

    @objc
    public override func isEqual(_ object: Any?) -> Bool { uuidValue == (object as? UntypedServiceIdObjC)?.uuidValue }

    @objc
    public func copy(with zone: NSZone? = nil) -> Any { self }

    @objc
    public override var description: String { wrappedValue.debugDescription }
}

// MARK: - DatabaseValueConvertible

extension UntypedServiceId: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue { uuidValue.databaseValue }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> UntypedServiceId? {
        UUID.fromDatabaseValue(dbValue).map { UntypedServiceId($0) }
    }
}

// MARK: - LibSignalClient.ServiceId

public typealias FutureAci = UntypedServiceId
public typealias FuturePni = UntypedServiceId

extension Aci {
    /// Parses an ACI from its string representation.
    ///
    /// - Note: Call this only if you **expect** an `Aci` (or nil). If the
    /// result could be a `Pni`, you shouldn't call this method.
    public static func parseFrom(aciString: String?) -> Aci? {
        guard let aciString else { return nil }
        guard let serviceId = try? ServiceId.parseFrom(serviceIdString: aciString) else { return nil }
        guard let aci = serviceId as? Aci else {
            owsFailDebug("Expected an ACI but found something else.")
            return nil
        }
        return aci
    }
}

extension ServiceId {
    public var temporary_rawUUID: UUID { rawUUID }
    public var untypedServiceId: UntypedServiceId { UntypedServiceId(rawUUID) }
}

@objc
public class ServiceIdObjC: NSObject, NSCopying {
    public var wrappedValue: ServiceId { owsFail("Subclasses must implement.") }

    fileprivate override init() { super.init() }

    public static func wrapValue(_ wrappedValue: ServiceId) -> ServiceIdObjC {
        switch wrappedValue.kind {
        case .aci:
            return AciObjC(wrappedValue as! Aci)
        case .pni:
            return PniObjC(wrappedValue as! Pni)
        }
    }

    @objc
    public static func parseFrom(serviceIdString: String?) -> ServiceIdObjC? {
        guard let serviceIdString, let wrappedValue = try? ServiceId.parseFrom(serviceIdString: serviceIdString) else {
            return nil
        }
        return wrapValue(wrappedValue)
    }

    @objc
    public var serviceIdString: String { wrappedValue.serviceIdString }

    @objc
    public var serviceIdUppercaseString: String { wrappedValue.serviceIdUppercaseString }

    @objc
    public override var hash: Int { wrappedValue.hashValue }

    @objc
    public override func isEqual(_ object: Any?) -> Bool { wrappedValue == (object as? ServiceIdObjC)?.wrappedValue }

    @objc
    public func copy(with zone: NSZone? = nil) -> Any { self }

    @objc
    public override var description: String { wrappedValue.debugDescription }
}

@objc
public final class AciObjC: ServiceIdObjC {
    public let wrappedAciValue: Aci

    public override var wrappedValue: ServiceId { wrappedAciValue }

    public init(_ wrappedValue: Aci) {
        self.wrappedAciValue = wrappedValue
    }

    @objc
    public init(uuidValue: UUID) {
        self.wrappedAciValue = Aci(fromUUID: uuidValue)
    }

    @objc
    public init?(aciString: String?) {
        guard let aciValue = Aci.parseFrom(aciString: aciString) else {
            return nil
        }
        self.wrappedAciValue = aciValue
    }
}

@objc
public final class PniObjC: ServiceIdObjC {
    public let wrappedPniValue: Pni

    public override var wrappedValue: ServiceId { wrappedPniValue }

    public init(_ wrappedValue: Pni) {
        self.wrappedPniValue = wrappedValue
    }

    @objc
    public init(uuidValue: UUID) {
        self.wrappedPniValue = Pni(fromUUID: uuidValue)
    }
}

// MARK: - Codable

@propertyWrapper
public struct AciUuid: Codable, Equatable, Hashable, DatabaseValueConvertible {
    public let wrappedValue: Aci

    public init(wrappedValue: Aci) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        self.wrappedValue = Aci(fromUUID: try decoder.singleValueContainer().decode(UUID.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wrappedValue.rawUUID)
    }

    public var databaseValue: DatabaseValue { wrappedValue.rawUUID.databaseValue }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Self? {
        UUID.fromDatabaseValue(dbValue).map { Self(wrappedValue: Aci(fromUUID: $0)) }
    }
}

extension Aci {
    public var codableUuid: AciUuid { .init(wrappedValue: self) }
}

@propertyWrapper
public struct PniUuid: Codable, Equatable, Hashable, DatabaseValueConvertible {
    public let wrappedValue: Pni

    public init(wrappedValue: Pni) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        self.wrappedValue = Pni(fromUUID: try decoder.singleValueContainer().decode(UUID.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wrappedValue.rawUUID)
    }

    public var databaseValue: DatabaseValue { wrappedValue.rawUUID.databaseValue }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Self? {
        UUID.fromDatabaseValue(dbValue).map { Self(wrappedValue: Pni(fromUUID: $0)) }
    }
}

extension Pni {
    public var codableUuid: PniUuid { .init(wrappedValue: self) }
}

@propertyWrapper
public struct ServiceIdUppercaseString: Codable, Hashable {
    public let wrappedValue: ServiceId

    public init(wrappedValue: ServiceId) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        self.wrappedValue = try ServiceId.parseFrom(
            serviceIdString: try decoder.singleValueContainer().decode(String.self)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wrappedValue.serviceIdUppercaseString)
    }
}

extension ServiceId {
    public var codableUppercaseString: ServiceIdUppercaseString { .init(wrappedValue: self) }
}

// MARK: - Unit Tests

#if TESTABLE_BUILD

extension UntypedServiceId {
    public static func randomForTesting() -> UntypedServiceId {
        return UntypedServiceId(UUID())
    }

    public static func constantForTesting(_ serviceIdString: String) -> UntypedServiceId {
        return UntypedServiceId((try! ServiceId.parseFrom(serviceIdString: serviceIdString)).rawUUID)
    }
}

extension Aci {
    public static func randomForTesting() -> Aci {
        Aci(fromUUID: UUID())
    }

    public static func constantForTesting(_ uuidString: String) -> Aci {
        try! ServiceId.parseFrom(serviceIdString: uuidString) as! Aci
     }
 }

extension Pni {
    public static func randomForTesting() -> Pni {
        Pni(fromUUID: UUID())
    }

    public static func constantForTesting(_ serviceIdString: String) -> Pni {
        try! ServiceId.parseFrom(serviceIdString: serviceIdString) as! Pni
    }
}

#endif
