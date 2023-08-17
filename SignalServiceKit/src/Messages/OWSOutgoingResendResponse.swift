//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension OWSOutgoingResendResponse {
    convenience init?(
        aci: Aci,
        deviceId: UInt32,
        failedTimestamp: UInt64,
        didResetSession: Bool,
        tx: SDSAnyWriteTransaction
    ) {
        let targetThread = TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(aci), transaction: tx)
        let builder = TSOutgoingMessageBuilder(thread: targetThread)

        let messageSendLog = SSKEnvironment.shared.messageSendLogRef
        if let payloadRecord = messageSendLog.fetchPayload(
            recipientServiceId: aci,
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
                Self.senderKeyStore.resetSenderKeyDeliveryRecord(for: originalThread, serviceId: aci, writeTx: tx)
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
