//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit

public enum RegistrationMode {
    case registering
    case reRegistering(ReregistrationParams)
    case changingNumber(ChangeNumberParams)

    public struct ReregistrationParams: Codable, Equatable {
        public let e164: E164
        @AciUuid public var aci: Aci
    }

    public struct ChangeNumberParams: Codable, Equatable {
        public let oldE164: E164
        public let oldAuthToken: String
        @AciUuid public var localAci: Aci
        public let localAccountId: String
        public let localDeviceId: UInt32
        public let localUserAllDeviceIds: [UInt32]
    }
}
