//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// An outgoing group v2 update.
public class OutgoingGroupUpdateMessage: TSOutgoingMessage {
    public init<T: Sequence>(
        in thread: TSGroupThread,
        groupMetaMessage: TSGroupMetaMessage,
        expiresInSeconds: UInt32 = 0,
        changeActionsProtoData: Data? = nil,
        additionalRecipients: T,
        transaction: SDSAnyReadTransaction
    ) where T.Element == SignalServiceAddress {
        let builder = TSOutgoingMessageBuilder(thread: thread)
        builder.groupMetaMessage = groupMetaMessage
        builder.expiresInSeconds = expiresInSeconds
        builder.changeActionsProtoData = changeActionsProtoData
        builder.additionalRecipients = Array(additionalRecipients)

        super.init(outgoingMessageWithBuilder: builder, transaction: transaction)
    }

    convenience init(
        in thread: TSGroupThread,
        groupMetaMessage: TSGroupMetaMessage,
        expiresInSeconds: UInt32 = 0,
        changeActionsProtoData: Data? = nil,
        transaction: SDSAnyReadTransaction
    ) {
        self.init(
            in: thread,
            groupMetaMessage: groupMetaMessage,
            expiresInSeconds: expiresInSeconds,
            changeActionsProtoData: changeActionsProtoData,
            additionalRecipients: [],
            transaction: transaction
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    required init(dictionary: [String: Any]!) throws {
        try super.init(dictionary: dictionary)
    }

    public override var isUrgent: Bool { false }
}
