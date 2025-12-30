//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension OWSOutgoingPaymentMessage {

    public convenience init(
        thread: TSThread,
        messageBody: ValidatedInlineMessageBody?,
        paymentNotification: TSPaymentNotification,
        expiresInSeconds: UInt32,
        expireTimerVersion: UInt32?,
        tx: DBReadTransaction,
    ) {
        let messageBuilder = TSOutgoingMessageBuilder.outgoingMessageBuilder(thread: thread)
        messageBuilder.setMessageBody(messageBody)
        messageBuilder.isViewOnceMessage = false
        messageBuilder.expiresInSeconds = expiresInSeconds
        messageBuilder.expireTimerVersion = expireTimerVersion.map(NSNumber.init(value:))

        self.init(
            builder: messageBuilder,
            paymentNotification: paymentNotification,
            transaction: tx,
        )
    }
}
