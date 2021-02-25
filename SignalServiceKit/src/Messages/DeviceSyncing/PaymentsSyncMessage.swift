//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension PaymentsSyncMessage {

    @objc(syncMessageBuilderWithMCOutgoing:transaction:)
    func syncMessageBuilder(mcOutgoing: PaymentsSyncMobileCoinOutgoing?,
                            transaction: SDSAnyReadTransaction) -> SSKProtoSyncMessage.SSKProtoSyncMessageBuilder? {
        // TODO: Support defrags.
        // TODO: Support requests.

        do {
            let paymentBuilder = SSKProtoSyncMessagePayment.builder()

            if let mcOutgoing = mcOutgoing {
                paymentBuilder.setOutgoing(try outgoingBuilder(mcOutgoing: mcOutgoing))
            }

            let builder = SSKProtoSyncMessage.builder()
            builder.setPayment(try paymentBuilder.build())
            return builder
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    private func outgoingBuilder(mcOutgoing: PaymentsSyncMobileCoinOutgoing) throws -> SSKProtoSyncMessagePaymentOutgoing {
        let outgoingBuilder = SSKProtoSyncMessagePaymentOutgoing.builder()

        let mobileCoinBuilder = SSKProtoSyncMessagePaymentOutgoingMobileCoin.builder(recipientUuid: mcOutgoing.recipientUuidString,
                                                                                     picoMob: mcOutgoing.picoMob,
                                                                                     receipt: mcOutgoing.receipt,
                                                                                     ledgerBlockIndex: mcOutgoing.blockIndex)
        if mcOutgoing.blockTimestamp > 0 {
            mobileCoinBuilder.setLedgerBlockTimestamp(mcOutgoing.blockTimestamp)
        }
        if !mcOutgoing.spentKeyImages.isEmpty {
            mobileCoinBuilder.setSpentKeyImage(mcOutgoing.spentKeyImages)
        }
        if !mcOutgoing.outputPublicKeys.isEmpty {
            mobileCoinBuilder.setOutputPublicKey(mcOutgoing.outputPublicKeys)
        }
        if let memoMessage = mcOutgoing.memoMessage {
            mobileCoinBuilder.setMemoMessage(memoMessage)
        }

        outgoingBuilder.setMobileCoin(try mobileCoinBuilder.build())

        return try outgoingBuilder.build()
    }
}
