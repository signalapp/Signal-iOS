//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public final class OWSSyncContactsMessage: OWSOutgoingSyncMessage {

    public init(thread: TSThread, tx: SDSAnyReadTransaction) {
        super.init(thread: thread, transaction: tx)
    }

    required init?(coder: NSCoder) {
        // Doesn't support serialization.
        return nil
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        throw OWSAssertionError("Doesn't support serialization.")
    }

    public override var isUrgent: Bool { false }

    public override func syncMessageBuilder(transaction tx: SDSAnyReadTransaction) -> SSKProtoSyncMessageBuilder? {
        let attachmentIds = self.bodyAttachmentIds(transaction: tx)
        owsAssertDebug(attachmentIds.count == 1, "Contact sync message should have exactly one attachment.")
        guard let attachmentId = attachmentIds.first else {
            owsFailDebug("couldn't build protobuf")
            return nil
        }
        // TODO: this object will never exist as a v2 Attachment, because
        // the parent message is never saved to the database.
        // Need to figure out how to represent it; it should just live in memory.
        guard
            let stream = TSAttachmentStream.anyFetchAttachmentStream(uniqueId: attachmentId, transaction: tx),
            stream.cdnKey.isEmpty.negated,
            stream.cdnNumber > 0
        else {
            return nil
        }
        let resourceReference = TSAttachmentReference(uniqueId: attachmentId, attachment: stream)
        let pointer = TSResourcePointer(resource: stream, cdnNumber: stream.cdnNumber, cdnKey: stream.cdnKey)
        guard let attachmentProto = DependenciesBridge.shared.tsResourceManager.buildProtoForSending(
            from: resourceReference,
            pointer: pointer
        ) else {
            owsFailDebug("couldn't build protobuf")
            return nil
        }

        let contactsBuilder = SSKProtoSyncMessageContacts.builder(blob: attachmentProto)
        contactsBuilder.setIsComplete(true)

        let contactsProto: SSKProtoSyncMessageContacts
        do {
            contactsProto = try contactsBuilder.build()
        } catch {
            owsFailDebug("Couldn't build protobuf: \(error)")
            return nil
        }

        let syncMessageBuilder = SSKProtoSyncMessage.builder()
        syncMessageBuilder.setContacts(contactsProto)
        return syncMessageBuilder
    }
}
