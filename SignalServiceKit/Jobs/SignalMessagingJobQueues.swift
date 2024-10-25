//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SignalMessagingJobQueues: NSObject {

    public init(appReadiness: AppReadiness, db: any DB, reachabilityManager: SSKReachabilityManager) {
        incomingContactSyncJobQueue = IncomingContactSyncJobQueue(appReadiness: appReadiness, db: db, reachabilityManager: reachabilityManager)
        sessionResetJobQueue = SessionResetJobQueue(db: db, reachabilityManager: reachabilityManager)
        tsAttachmentMultisendJobQueue = TSAttachmentMultisendJobQueue(db: db, reachabilityManager: reachabilityManager)
        receiptCredentialJobQueue = DonationReceiptCredentialRedemptionJobQueue(db: db, reachabilityManager: reachabilityManager)
        sendGiftBadgeJobQueue = SendGiftBadgeJobQueue(db: db, reachabilityManager: reachabilityManager)
    }

    // MARK: @objc

    @objc
    public let incomingContactSyncJobQueue: IncomingContactSyncJobQueue

    // MARK: Swift-only

    public let sessionResetJobQueue: SessionResetJobQueue
    public let tsAttachmentMultisendJobQueue: TSAttachmentMultisendJobQueue
    public let receiptCredentialJobQueue: DonationReceiptCredentialRedemptionJobQueue
    public let sendGiftBadgeJobQueue: SendGiftBadgeJobQueue
}
