//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public extension OutgoingPaymentSyncMessage {

    @objc(syncMessageBuilderWithMobileCoin:transaction:)
    func syncMessageBuilder(
        mobileCoin: OutgoingPaymentMobileCoin,
        transaction: DBReadTransaction,
    ) -> SSKProtoSyncMessageBuilder? {
        do {
            let amountPicoMob = mobileCoin.amountPicoMob
            let feePicoMob = mobileCoin.feePicoMob
            let ledgerBlockIndex = mobileCoin.blockIndex
            let spentKeyImages = mobileCoin.spentKeyImages
            let outputPublicKeys = mobileCoin.outputPublicKeys
            let receiptData = mobileCoin.receiptData
            let mobileCoinBuilder = SSKProtoSyncMessageOutgoingPaymentMobileCoin.builder(
                amountPicoMob: amountPicoMob,
                feePicoMob: feePicoMob,
                ledgerBlockIndex: ledgerBlockIndex,
            )
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
            if let recipientAci = mobileCoin.recipientAci {
                outgoingPaymentBuilder.setRecipientServiceID(recipientAci.wrappedAciValue.serviceIdString)
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
