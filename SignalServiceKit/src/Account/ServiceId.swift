//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import GRDB

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
    public var rawUUID: UUID { wrappedValue.rawUUID }

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
public struct ServiceIdString: Codable, Hashable {
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
        try container.encode(self.wrappedValue.serviceIdString)
    }
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
