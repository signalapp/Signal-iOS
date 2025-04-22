//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// An outgoing group v2 update.
class OutgoingGroupUpdateMessage: TSOutgoingMessage {
    init(
        in thread: TSGroupThread,
        groupMetaMessage: TSGroupMetaMessage,
        expiresInSeconds: UInt32 = 0,
        groupChangeProtoData: Data? = nil,
        additionalRecipients: some Sequence<ServiceId>,
        transaction: DBReadTransaction
    ) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            expiresInSeconds: expiresInSeconds,
            groupMetaMessage: groupMetaMessage,
            groupChangeProtoData: groupChangeProtoData
        )

        super.init(
            outgoingMessageWith: builder,
            additionalRecipients: additionalRecipients.map { ServiceIdObjC.wrapValue($0) },
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

    override var isUrgent: Bool { false }

    override var shouldBeSaved: Bool { false }
}
