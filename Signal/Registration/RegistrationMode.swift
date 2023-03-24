//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum RegistrationMode {
    case registering
    case reRegistering(e164: E164, aci: UUID)
    case changingNumber(ChangeNumberParams)

    public struct ChangeNumberParams: Codable, Equatable {
        public let oldE164: E164
        public let oldAuthToken: String
        public let localAci: UUID
        public let localAccountId: String
        public let localDeviceId: UInt32
        public let localUserAllDeviceIds: [UInt32]
    }
}
