//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SignalMessagingJobQueues: NSObject {

    public override init() {
        incomingContactSyncJobQueue = IncomingContactSyncJobQueue()
        incomingGroupSyncJobQueue = IncomingGroupSyncJobQueue()
        sessionResetJobQueue = SessionResetJobQueue()

        broadcastMediaMessageJobQueue = BroadcastMediaMessageJobQueue()
        receiptCredentialJobQueue = ReceiptCredentialRedemptionJobQueue()
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
