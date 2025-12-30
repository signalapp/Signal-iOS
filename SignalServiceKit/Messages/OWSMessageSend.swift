//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// Provides parameters required for assembling a Sealed Sender message.
final class SealedSenderParameters {
    let message: TSOutgoingMessage
    let senderCertificate: SenderCertificate
    let accessKey: OWSUDAccess?
    let endorsement: GroupSendFullTokenBuilder?

    init?(
        message: TSOutgoingMessage,
        senderCertificate: SenderCertificate,
        accessKey: OWSUDAccess?,
        endorsement: GroupSendFullTokenBuilder?,
    ) {
        self.message = message
        self.senderCertificate = senderCertificate
        guard message.isStorySend || accessKey != nil || endorsement != nil else {
            return nil
        }
        self.accessKey = accessKey
        self.endorsement = endorsement
    }

    /// Indicates desired behavior on the case of decryption error.
    var contentHint: SealedSenderContentHint {
        return message.contentHint
    }

    /// Fetches a group ID to attache to the message envelope, to assist error
    /// handling in the case of decryption error.
    func envelopeGroupId(tx: DBReadTransaction) -> Data? {
        return message.envelopeGroupIdWithTransaction(tx)
    }
}

// Corresponds to a single effort to send a message to a given recipient,
// which may span multiple attempts. Note that group messages may be sent
// to multiple recipients and therefore require multiple instances of
// OWSMessageSend.
final class OWSMessageSend {
    let message: TSOutgoingMessage
    let plaintextContent: Data
    let plaintextPayloadId: Int64?
    let thread: TSThread
    let serviceId: ServiceId
    let localIdentifiers: LocalIdentifiers

    init(
        message: TSOutgoingMessage,
        plaintextContent: Data,
        plaintextPayloadId: Int64?,
        thread: TSThread,
        serviceId: ServiceId,
        localIdentifiers: LocalIdentifiers,
    ) {
        self.message = message
        self.plaintextContent = plaintextContent
        self.plaintextPayloadId = plaintextPayloadId
        self.thread = thread
        self.serviceId = serviceId
        self.localIdentifiers = localIdentifiers
    }

    var isSelfSend: Bool {
        return self.localIdentifiers.contains(serviceId: self.serviceId)
    }
}
