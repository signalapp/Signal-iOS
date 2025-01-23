//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct CombinedGroupSendEndorsementRecord {
    let threadId: Int64
    let endorsement: Data
    let expiration: Date

    var expirationTimestamp: UInt64 {
        return UInt64(expiration.timeIntervalSince1970)
    }
}

struct IndividualGroupSendEndorsementRecord {
    let threadId: Int64
    let recipientId: Int64
    let endorsement: Data
}
