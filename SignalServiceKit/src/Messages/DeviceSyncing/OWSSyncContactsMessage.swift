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
        owsAssertDebug(attachmentIds.count == 1, "Contact sync message should have exactly one attachment.")
        guard let attachmentId = attachmentIds.first else {
            owsFailDebug("couldn't build protobuf")
            return nil
        }
        guard let attachmentProto = TSAttachmentStream.buildProto(
            attachmentId: attachmentId,
            caption: nil,
            attachmentType: .default,
            transaction: tx
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
