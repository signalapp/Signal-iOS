//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

struct GroupSendEndorsements {
    var secretParams: GroupSecretParams
    var expiration: Date
    var combined: GroupSendEndorsement
    var individual: [ServiceId: GroupSendEndorsement]

    func tokenBuilder(forServiceId serviceId: ServiceId) -> GroupSendFullTokenBuilder? {
        return individual[serviceId].map {
            return GroupSendFullTokenBuilder(secretParams: secretParams, expiration: expiration, endorsement: $0)
        }
    }
}
