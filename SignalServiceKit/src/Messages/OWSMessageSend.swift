//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Provides parameters required for assembling a Sealed Sender message.
final class SealedSenderParameters {
    let message: TSOutgoingMessage
    let udSendingAccess: OWSUDSendingAccess

    init(message: TSOutgoingMessage, udSendingAccess: OWSUDSendingAccess) {
        self.message = message
        self.udSendingAccess = udSendingAccess
    }

    /// Indicates desired behavior on the case of decryption error.
    var contentHint: SealedSenderContentHint {
        return message.contentHint
    }

    /// Fetches a group ID to attache to the message envelope, to assist error
    /// handling in the case of decryption error.
    func envelopeGroupId(tx: DBReadTransaction) -> Data? {
        return message.envelopeGroupIdWithTransaction(SDSDB.shimOnlyBridge(tx))
    }
}

// Corresponds to a single effort to send a message to a given recipient,
// which may span multiple attempts. Note that group messages may be sent
// to multiple recipients and therefore require multiple instances of
// OWSMessageSend.
final class OWSMessageSend {
    public let message: TSOutgoingMessage
    public let plaintextContent: Data
    public let plaintextPayloadId: Int64?
    public let thread: TSThread
    public let serviceId: ServiceId
    public let localIdentifiers: LocalIdentifiers

    public init(
        message: TSOutgoingMessage,
        plaintextContent: Data,
        plaintextPayloadId: Int64?,
        thread: TSThread,
        serviceId: ServiceId,
        localIdentifiers: LocalIdentifiers
    ) {
        self.message = message
        self.plaintextContent = plaintextContent
        self.plaintextPayloadId = plaintextPayloadId
        self.thread = thread
        self.serviceId = serviceId
        self.localIdentifiers = localIdentifiers
    }
}
