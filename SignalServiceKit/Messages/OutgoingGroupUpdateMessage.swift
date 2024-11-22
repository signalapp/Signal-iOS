//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// An outgoing group v2 update.
public class OutgoingGroupUpdateMessage: TSOutgoingMessage {
    public init(
        in thread: TSGroupThread,
        groupMetaMessage: TSGroupMetaMessage,
        expiresInSeconds: UInt32 = 0,
        groupChangeProtoData: Data? = nil,
        additionalRecipients: some Sequence<SignalServiceAddress>,
        transaction: SDSAnyReadTransaction
    ) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            expiresInSeconds: expiresInSeconds,
            groupMetaMessage: groupMetaMessage,
            groupChangeProtoData: groupChangeProtoData
        )

        super.init(
            outgoingMessageWith: builder,
            additionalRecipients: Array(additionalRecipients),
            explicitRecipients: [],
            skippedRecipients: [],
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

    public override var shouldBeSaved: Bool { false }
}
