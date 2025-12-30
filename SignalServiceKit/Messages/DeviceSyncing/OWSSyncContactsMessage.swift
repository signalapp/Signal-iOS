//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public final class OWSSyncContactsMessage: OWSOutgoingSyncMessage {

    private let uploadedAttachment: Upload.Result<Upload.LocalUploadMetadata>

    public init(
        uploadedAttachment: Upload.Result<Upload.LocalUploadMetadata>,
        localThread: TSContactThread,
        tx: DBReadTransaction,
    ) {
        self.uploadedAttachment = uploadedAttachment
        super.init(localThread: localThread, transaction: tx)
    }

    override public func encode(with coder: NSCoder) {
        owsFail("Doesn't support serialization.")
    }

    required init?(coder: NSCoder) {
        // Doesn't support serialization.
        return nil
    }

    override public var isUrgent: Bool { false }

    override public func syncMessageBuilder(transaction tx: DBReadTransaction) -> SSKProtoSyncMessageBuilder? {

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
