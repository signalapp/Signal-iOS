//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
public import SignalServiceKit

public enum RegistrationMode: CustomDebugStringConvertible {
    case registering
    case reRegistering(ReregistrationParams)
    case changingNumber(ChangeNumberParams)

    public struct ReregistrationParams: Codable, Equatable {
        public let aci: Aci?
        public let e164: E164

        enum CodingKeys: String, CodingKey {
            case aci
            case e164
        }

        init(aci: Aci?, e164: E164) {
            self.aci = aci
            self.e164 = e164
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.aci = try container.decodeIfPresent(UUID.self, forKey: .aci).map({ Aci(fromUUID: $0) })
            self.e164 = try container.decode(E164.self, forKey: .e164)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(self.aci?.rawUUID, forKey: .aci)
            try container.encode(self.e164, forKey: .e164)
        }
    }

    public struct ChangeNumberParams: Codable, Equatable {
        public let oldE164: E164
        public let oldAuthToken: String
        @AciUuid public var localAci: Aci
        public let localDeviceId: DeviceId
    }

    public var debugDescription: String {
        switch self {
        case .registering:
            return "registering"
        case .reRegistering:
            return "reRegistering"
        case .changingNumber:
            return "changingNumber"
        }
    }
}
