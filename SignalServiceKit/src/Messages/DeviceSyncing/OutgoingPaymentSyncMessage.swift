//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension OutgoingPaymentSyncMessage {

    @objc(syncMessageBuilderWithMobileCoin:transaction:)
    func syncMessageBuilder(mobileCoin: OutgoingPaymentMobileCoin,
                            transaction: SDSAnyReadTransaction) -> SSKProtoSyncMessage.SSKProtoSyncMessageBuilder? {
        // TODO: Support requests.

        do {
            var amountPicoMob = mobileCoin.amountPicoMob
            var feePicoMob = mobileCoin.feePicoMob
            var ledgerBlockIndex = mobileCoin.blockIndex
            var spentKeyImages = mobileCoin.spentKeyImages
            var outputPublicKeys = mobileCoin.outputPublicKeys
            var receiptData = mobileCoin.receiptData
            if DebugFlags.paymentsMalformedMessages.get() {
                amountPicoMob = 0
                feePicoMob = 0
                ledgerBlockIndex = 0
                spentKeyImages = []
                outputPublicKeys = []
                receiptData = Randomness.generateRandomBytes(Int32(receiptData.count))
            }
            let mobileCoinBuilder = SSKProtoSyncMessageOutgoingPaymentMobileCoin.builder(amountPicoMob: amountPicoMob,
                                                                                         feePicoMob: feePicoMob,
                                                                                         ledgerBlockIndex: ledgerBlockIndex)
            mobileCoinBuilder.setSpentKeyImages(spentKeyImages)
            mobileCoinBuilder.setOutputPublicKeys(outputPublicKeys)
            if let recipientAddress = mobileCoin.recipientAddress {
                mobileCoinBuilder.setRecipientAddress(recipientAddress)
            }
            if mobileCoin.blockTimestamp > 0 {
                mobileCoinBuilder.setLedgerBlockTimestamp(mobileCoin.blockTimestamp)
            }
            mobileCoinBuilder.setReceipt(receiptData)

            let outgoingPaymentBuilder = SSKProtoSyncMessageOutgoingPayment.builder()
            if let recipientUuidString = mobileCoin.recipientUuidString {
                outgoingPaymentBuilder.setRecipientUuid(recipientUuidString)
            }
            outgoingPaymentBuilder.setMobileCoin(try mobileCoinBuilder.build())
            if let memoMessage = mobileCoin.memoMessage {
                outgoingPaymentBuilder.setNote(memoMessage)
            }

            let builder = SSKProtoSyncMessage.builder()
            builder.setOutgoingPayment(try outgoingPaymentBuilder.build())
            return builder
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }
}
