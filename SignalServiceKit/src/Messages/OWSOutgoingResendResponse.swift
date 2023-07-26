//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension OWSOutgoingResendResponse {
    @objc
    convenience init?(
        address: SignalServiceAddress,
        deviceId: UInt32,
        failedTimestamp: UInt64,
        didResetSession: Bool,
        tx: SDSAnyWriteTransaction
    ) {
        let targetThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: tx)
        let builder = TSOutgoingMessageBuilder(thread: targetThread)

        let messageSendLog = SSKEnvironment.shared.messageSendLogRef
        if let serviceId = address.untypedServiceId, let payloadRecord = messageSendLog.fetchPayload(
            recipientServiceId: serviceId,
            recipientDeviceId: deviceId,
            timestamp: failedTimestamp,
            tx: tx
        ) {
            Logger.info("Found an MSL record for resend request: \(failedTimestamp)")
            let originalThread = TSThread.anyFetch(uniqueId: payloadRecord.uniqueThreadId, transaction: tx)

            // We should inherit the timestamp of the failed message. This allows the
            // recipient of this message to correlate the resend response with the
            // original failed message.
            builder.timestamp = payloadRecord.sentTimestamp

            // We also want to reset the delivery record for the failing address if
            // this was a sender key group. This will be re-marked as delivered on
            // success if we included an SKDM in the resend response
            if let originalThread, originalThread.isGroupThread {
                Self.senderKeyStore.resetSenderKeyDeliveryRecord(for: originalThread, serviceId: serviceId, writeTx: tx)
            }

            self.init(
                outgoingMessageBuilder: builder,
                originalMessagePlaintext: payloadRecord.plaintextContent,
                originalThreadId: payloadRecord.uniqueThreadId,
                originalGroupId: (originalThread as? TSGroupThread)?.groupId,
                derivedContentHint: payloadRecord.contentHint.rawValue,
                transaction: tx
            )
        } else if didResetSession {
            Logger.info("Failed to find MSL record for resend request: \(failedTimestamp). Will reply with Null message")
            self.init(
                outgoingMessageBuilder: builder,
                originalMessagePlaintext: nil,
                originalThreadId: nil,
                originalGroupId: nil,
                derivedContentHint: SealedSenderContentHint.implicit.rawValue,
                transaction: tx
            )
        } else {
            Logger.info("Failed to find MSL record for resend request: \(failedTimestamp). Declining to respond.")
            return nil
        }
    }
}
