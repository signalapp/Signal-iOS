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
            let mobileCoinBuilder = SSKProtoSyncMessageOutgoingPaymentMobileCoin.builder(amountPicoMob: mobileCoin.amountPicoMob,
                                                                                         feePicoMob: mobileCoin.feePicoMob,
                                                                                         ledgerBlockIndex: mobileCoin.blockIndex)
            mobileCoinBuilder.setSpentKeyImages(mobileCoin.spentKeyImages)
            mobileCoinBuilder.setOutputPublicKeys(mobileCoin.outputPublicKeys)
            if let recipientAddress = mobileCoin.recipientAddress {
                mobileCoinBuilder.setRecipientAddress(recipientAddress)
            }
            if mobileCoin.blockTimestamp > 0 {
                mobileCoinBuilder.setLedgerBlockTimestamp(mobileCoin.blockTimestamp)
            }

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
