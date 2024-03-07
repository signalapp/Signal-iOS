//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc(OWSSyncContactsMessage)
public final class OWSSyncContactsMessage: OWSOutgoingSyncMessage {

    /// Deprecated. It's always true for new instances, but it might be false
    /// for jobs enqueued by prior versions of the application. (These would be
    /// safe to drop, but they're also harmless to send.)
    @objc // for Mantle
    private(set) public var isFullSync = false

    public init(thread: TSThread, isFullSync: Bool, tx: SDSAnyReadTransaction) {
        self.isFullSync = isFullSync
        super.init(thread: thread, transaction: tx)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
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
        contactsBuilder.setIsComplete(isFullSync)

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
