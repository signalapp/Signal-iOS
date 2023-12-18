//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public class SignalMessagingJobQueues: NSObject {

    public init(db: DB, reachabilityManager: SSKReachabilityManager) {
        incomingContactSyncJobQueue = IncomingContactSyncJobQueue(db: db, reachabilityManager: reachabilityManager)
        incomingGroupSyncJobQueue = IncomingGroupSyncJobQueue()
        sessionResetJobQueue = SessionResetJobQueue()
        broadcastMediaMessageJobQueue = BroadcastMediaMessageJobQueue()
        receiptCredentialJobQueue = ReceiptCredentialRedemptionJobQueue(db: db, reachabilityManager: reachabilityManager)
        sendGiftBadgeJobQueue = SendGiftBadgeJobQueue()
    }

    // MARK: @objc

    @objc
    public let incomingContactSyncJobQueue: IncomingContactSyncJobQueue
    @objc
    public let incomingGroupSyncJobQueue: IncomingGroupSyncJobQueue

    // MARK: Swift-only

    public let sessionResetJobQueue: SessionResetJobQueue
    public let broadcastMediaMessageJobQueue: BroadcastMediaMessageJobQueue
    public let receiptCredentialJobQueue: ReceiptCredentialRedemptionJobQueue
    public let sendGiftBadgeJobQueue: SendGiftBadgeJobQueue
}
