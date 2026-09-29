//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

/// This is deprecated and should not be used.
public struct EquatableReregisteringLocalIdentifiers: Equatable {
    public let wrappedValue: ReregisteringLocalIdentifiers

    public init(_ wrappedValue: ReregisteringLocalIdentifiers) {
        self.wrappedValue = wrappedValue
    }

    public static func ==(lhs: Self, rhs: Self) -> Bool {
        switch (lhs.wrappedValue, rhs.wrappedValue) {
        case (.phoneNumberfull(let lhsPhoneNumber, let lhsAci), .phoneNumberfull(let rhsPhoneNumber, let rhsAci)):
            return lhsPhoneNumber == rhsPhoneNumber && lhsAci == rhsAci
        case (.phoneNumberless(let lhsAci), .phoneNumberless(let rhsAci)):
            return lhsAci == rhsAci
        default:
            return false
        }
    }
}

public enum ReregisteringLocalIdentifiers: Codable {
    case phoneNumberfull(phoneNumber: String, aci: Aci?)
    case phoneNumberless(aci: Aci)

    public var phoneNumber: String? {
        switch self {
        case .phoneNumberfull(let phoneNumber, aci: _):
            return phoneNumber
        case .phoneNumberless:
            return nil
        }
    }

    public var aci: Aci? {
        switch self {
        case .phoneNumberfull(phoneNumber: _, let aci):
            return aci
        case .phoneNumberless(let aci):
            return aci
        }
    }

    static func parseFrom(phoneNumber: String?, aci: Aci?) -> Self? {
        if let phoneNumber {
            return .phoneNumberfull(phoneNumber: phoneNumber, aci: aci)
        } else if let aci {
            return .phoneNumberless(aci: aci)
        } else {
            return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case phoneNumber = "e164"
        case aci
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        let aci = try container.decodeIfPresent(AciUuid.self, forKey: .aci)?.wrappedValue
        guard let result = Self.parseFrom(phoneNumber: phoneNumber, aci: aci) else {
            throw DecodingError.dataCorruptedError(
                forKey: .aci,
                in: container,
                debugDescription: "ACI is required when E164 is absent",
            )
        }
        self = result
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .phoneNumberfull(let phoneNumber, let aci):
            try container.encode(phoneNumber, forKey: .phoneNumber)
            try container.encodeIfPresent(aci?.rawUUID, forKey: .aci)
        case .phoneNumberless(let aci):
            try container.encode(aci.rawUUID, forKey: .aci)
        }
    }
}
