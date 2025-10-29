//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// An outgoing group v2 update.
class OutgoingGroupUpdateMessage: TSOutgoingMessage {
    @objc
    private var isUpdateUrgent: Bool = false

    @objc
    private(set) var isDeletingAccount: Bool = false

    init(
        in thread: TSGroupThread,
        groupMetaMessage: TSGroupMetaMessage,
        expiresInSeconds: UInt32 = 0,
        groupChangeProtoData: Data? = nil,
        additionalRecipients: some Sequence<ServiceId>,
        isUrgent: Bool = false,
        isDeletingAccount: Bool = false,
        transaction: DBReadTransaction
    ) {
        let builder: TSOutgoingMessageBuilder = .withDefaultValues(
            thread: thread,
            expiresInSeconds: expiresInSeconds,
            groupMetaMessage: groupMetaMessage,
            groupChangeProtoData: groupChangeProtoData
        )
        self.isUpdateUrgent = isUrgent
        self.isDeletingAccount = isDeletingAccount
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

    override var isUrgent: Bool { self.isUpdateUrgent }

    override var shouldBeSaved: Bool { false }
}
