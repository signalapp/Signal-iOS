//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

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
        case ICSJR_cdnNumber
        case ICSJR_cdnKey
        case ICSJR_encryptionKey
        case ICSJR_digest
        case ICSJR_plaintextLength

        // MARK: LocalUserLeaveGroupJobRecord

        case replacementAdminAciString = "replacementAdminUuid"
        case waitForMessageProcessing

        // MARK: SessionResetJobRecord

        case contactThreadId

        // MARK: SendGiftBadgeJobRecord

        case messageText
        case paymentIntentClientSecret
        case paymentMethodId
        case paypalPayerId
        case paypalPaymentId
        case paypalPaymentToken

        // MARK: DonationReceiptCredentialRedemptionJobRecord

        case _receiptCredentialPresentation = "receiptCredentialPresentation"
        case _receiptCredential = "receiptCredential"

        case isBoost

        case subscriberID
        case targetSubscriptionLevel
        case priorSubscriptionLevel
        case isNewSubscription
        case shouldSuppressPaymentAlreadyRedeemed

        // MARK: SendGiftBadgeJobRecord & DonationReceiptCredentialRedemptionJobRecord

        case amount
        case currencyCode
        case boostPaymentIntentID
        case paymentProcessor
        case paymentMethod
        /// Uses a misspelled raw value for historical compatibility.
        case receiptCredentialRequest = "receiptCredentailRequest"
        /// Uses a misspelled raw value for historical compatibility.
        case receiptCredentialRequestContext = "receiptCredentailRequestContext"

        // MARK: LocalUserLeaveGroupJobRecord & MessageSenderJobRecord & SendGiftBadgeJobRecord

        case threadId

        // MARK: CallRecordDeleteAllJobRecord

        case sendDeleteAllSyncMessage = "CRDAJR_sendDeleteAllSyncMessage"
        case deleteAllBeforeCallId = "CRDAJR_deleteAllBeforeCallId"
        case deleteAllBeforeConversationId = "CRDAJR_deleteAllBeforeConversationId"
        case deleteAllBeforeTimestamp = "CRDAJR_deleteAllBeforeTimestamp"

        // MARK: BulkDeleteInteractionJobRecord

        case BDIJR_anchorMessageRowId = "BDIJR_anchorMessageRowId"
        case BDIJR_fullThreadDeletionAnchorMessageRowId = "BDIJR_fullThreadDeletionAnchorMessageRowId"
        case BDIJR_threadUniqueId = "BDIJR_threadUniqueId"

        // MARK: BackupReceiptCredentialRedemptionJobRecord

        case BRCRJR_state = "BRCRJR_state"
    }
}
