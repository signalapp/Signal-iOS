//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import SignalCoreKit

// NOTE: This file is generated by /Scripts/sds_codegen/sds_generate.py.
// Do not manually edit it, instead run `sds_codegen.sh`.

// MARK: - Typed Convenience Methods

@objc
public extension OWSLocalUserLeaveGroupJobRecord {
    // NOTE: This method will fail if the object has unexpected type.
    class func anyFetchLocalUserLeaveGroupJobRecord(
        uniqueId: String,
        transaction: SDSAnyReadTransaction
    ) -> OWSLocalUserLeaveGroupJobRecord? {
        assert(uniqueId.count > 0)

        guard let object = anyFetch(uniqueId: uniqueId,
                                    transaction: transaction) else {
                                        return nil
        }
        guard let instance = object as? OWSLocalUserLeaveGroupJobRecord else {
            owsFailDebug("Object has unexpected type: \(type(of: object))")
            return nil
        }
        return instance
    }

    // NOTE: This method will fail if the object has unexpected type.
    func anyUpdateLocalUserLeaveGroupJobRecord(transaction: SDSAnyWriteTransaction, block: (OWSLocalUserLeaveGroupJobRecord) -> Void) {
        anyUpdate(transaction: transaction) { (object) in
            guard let instance = object as? OWSLocalUserLeaveGroupJobRecord else {
                owsFailDebug("Object has unexpected type: \(type(of: object))")
                return
            }
            block(instance)
        }
    }
}

// MARK: - SDSSerializer

// The SDSSerializer protocol specifies how to insert and update the
// row that corresponds to this model.
class OWSLocalUserLeaveGroupJobRecordSerializer: SDSSerializer {

    private let model: OWSLocalUserLeaveGroupJobRecord
    public required init(model: OWSLocalUserLeaveGroupJobRecord) {
        self.model = model
    }

    // MARK: - Record

    func asRecord() throws -> SDSRecord {
        let id: Int64? = model.sortId > 0 ? Int64(model.sortId) : model.grdbId?.int64Value

        let recordType: SDSRecordType = .localUserLeaveGroupJobRecord
        let uniqueId: String = model.uniqueId

        // Properties
        let failureCount: UInt = model.failureCount
        let label: String = model.label
        let status: SSKJobRecordStatus = model.status
        let attachmentIdMap: Data? = nil
        let contactThreadId: String? = nil
        let envelopeData: Data? = nil
        let invisibleMessage: Data? = nil
        let messageId: String? = nil
        let removeMessageAfterSending: Bool? = nil
        let threadId: String? = model.threadId
        let attachmentId: String? = nil
        let isMediaMessage: Bool? = nil
        let serverDeliveryTimestamp: UInt64? = nil
        let exclusiveProcessIdentifier: String? = model.exclusiveProcessIdentifier
        let isHighPriority: Bool? = nil
        let receiptCredentailRequest: Data? = nil
        let receiptCredentailRequestContext: Data? = nil
        let priorSubscriptionLevel: UInt? = nil
        let subscriberID: Data? = nil
        let targetSubscriptionLevel: UInt? = nil
        let boostPaymentIntentID: String? = nil
        let isBoost: Bool? = nil
        let receiptCredentialPresentation: Data? = nil
        let amount: Data? = nil
        let currencyCode: String? = nil
        let unsavedMessagesToSend: Data? = nil
        let messageText: String? = nil
        let paymentIntentClientSecret: String? = nil
        let paymentMethodId: String? = nil
        let replacementAdminUuid: String? = model.replacementAdminUuid
        let waitForMessageProcessing: Bool? = model.waitForMessageProcessing

        return JobRecordRecord(delegate: model, id: id, recordType: recordType, uniqueId: uniqueId, failureCount: failureCount, label: label, status: status, attachmentIdMap: attachmentIdMap, contactThreadId: contactThreadId, envelopeData: envelopeData, invisibleMessage: invisibleMessage, messageId: messageId, removeMessageAfterSending: removeMessageAfterSending, threadId: threadId, attachmentId: attachmentId, isMediaMessage: isMediaMessage, serverDeliveryTimestamp: serverDeliveryTimestamp, exclusiveProcessIdentifier: exclusiveProcessIdentifier, isHighPriority: isHighPriority, receiptCredentailRequest: receiptCredentailRequest, receiptCredentailRequestContext: receiptCredentailRequestContext, priorSubscriptionLevel: priorSubscriptionLevel, subscriberID: subscriberID, targetSubscriptionLevel: targetSubscriptionLevel, boostPaymentIntentID: boostPaymentIntentID, isBoost: isBoost, receiptCredentialPresentation: receiptCredentialPresentation, amount: amount, currencyCode: currencyCode, unsavedMessagesToSend: unsavedMessagesToSend, messageText: messageText, paymentIntentClientSecret: paymentIntentClientSecret, paymentMethodId: paymentMethodId, replacementAdminUuid: replacementAdminUuid, waitForMessageProcessing: waitForMessageProcessing)
    }
}
