//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public final class OWSSyncContactsMessage: OWSOutgoingSyncMessage {

    private let uploadedAttachment: Upload.Result<Upload.LocalUploadMetadata>

    public init(
        uploadedAttachment: Upload.Result<Upload.LocalUploadMetadata>,
        thread: TSThread,
        tx: SDSAnyReadTransaction
    ) {
        self.uploadedAttachment = uploadedAttachment
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

        let attachmentBuilder = SSKProtoAttachmentPointer.builder()

        // contact proto has a fixed type
        attachmentBuilder.setContentType(MimeType.applicationOctetStream.rawValue)
        attachmentBuilder.setCdnNumber(uploadedAttachment.cdnNumber)
        attachmentBuilder.setCdnKey(uploadedAttachment.cdnKey)
        attachmentBuilder.setSize(uploadedAttachment.localUploadMetadata.plaintextDataLength)
        attachmentBuilder.setKey(uploadedAttachment.localUploadMetadata.key)
        attachmentBuilder.setDigest(uploadedAttachment.localUploadMetadata.digest)

        let attachmentProto = attachmentBuilder.buildInfallibly()

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
