//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension JobRecord {
    /// Represents all of the columns in the job record database table. There
    /// are many jobs that all share the same table, and therefore the columns
    /// here are the set-union of the columns used by each individual job
    /// record. While most columns are uniquely used for a single type of job,
    /// some columns have been reused across multiple job types.
    public enum JobRecordColumns: String, CodingKey, ColumnExpression, CaseIterable {

        // MARK: GRDB columns

        case id
        case recordType
        case uniqueId

        // MARK: Base columns

        case exclusiveProcessIdentifier
        case failureCount
        case label
        case status

        // MARK: LegacyMessageDecryptJobRecord

        case envelopeData
        case serverDeliveryTimestamp

        // MARK: MessageSenderJobRecord

        case invisibleMessage
        case isHighPriority
        case isMediaMessage
        case messageId
        case removeMessageAfterSending

        // MARK: IncomingContactSyncJobRecord

        case isCompleteContactSync

        // MARK: IncomingContactSyncJobRecord & IncomingGroupSyncJobRecord

        case attachmentId

        // MARK: LocalUserLeaveGroupJobRecord

        case replacementAdminAciString = "replacementAdminUuid"
        case waitForMessageProcessing

        // MARK: BroadcastMediaMessageJobRecord

        case attachmentIdMap
        case unsavedMessagesToSend

        // MARK: SessionResetJobRecord

        case contactThreadId

        // MARK: SendGiftBadgeJobRecord

        case messageText
        case paymentIntentClientSecret
        case paymentMethodId
        case paypalPayerId
        case paypalPaymentId
        case paypalPaymentToken

        // MARK: ReceiptCredentialRedemptionJobRecord

        case isBoost
        case priorSubscriptionLevel
        case receiptCredentialPresentation
        case subscriberID
        case targetSubscriptionLevel

        // MARK: SendGiftBadgeJobRecord & ReceiptCredentialRedemptionJobRecord

        case amount
        case currencyCode
        case boostPaymentIntentID
        case paymentProcessor
        /// Uses a misspelled raw value for historical compatibility.
        case receiptCredentialRequest = "receiptCredentailRequest"
        /// Uses a misspelled raw value for historical compatibility.
        case receiptCredentialRequestContext = "receiptCredentailRequestContext"

        // MARK: LocalUserLeaveGroupJobRecord & MessageSenderJobRecord & SendGiftBadgeJobRecord

        case threadId
    }
}
