//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension EditManager {
    public enum Shims {
        public typealias LinkPreview = _EditManager_LinkPreviewShim
        public typealias DataStore = _EditManager_DataStore
        public typealias Groups = _EditManager_GroupsShim
    }

    public enum Wrappers {
        internal typealias LinkPreview = _EditManager_LinkPreviewWrapper
        internal typealias DataStore = _EditManager_DataStoreWrapper
        internal typealias Groups = _EditManager_GroupsWrapper
    }
}

// MARK: - EditManager.DataStore

public protocol _EditManager_DataStore {

    func findTargetMessage(
        timestamp: UInt64,
        author: SignalServiceAddress,
        tx: DBReadTransaction
    ) -> TSInteraction?

    func createOutgoingMessage(
        with builder: TSOutgoingMessageBuilder,
        tx: DBReadTransaction
    ) -> TSOutgoingMessage

    func copyRecipients(
        from source: TSOutgoingMessage,
        to target: TSOutgoingMessage,
        tx: DBWriteTransaction
    )

    func getMediaAttachments(
        message: TSMessage,
        tx: DBReadTransaction
    ) -> [TSAttachment]

    func getOversizedTextAttachments(
        message: TSMessage,
        tx: DBReadTransaction
    ) -> TSAttachment?

    func insertMessageCopy(
        message: TSMessage,
        tx: DBWriteTransaction
    )

    func updateEditedMessage(
        message: TSMessage,
        tx: DBWriteTransaction
    )

    func insertEditRecord(
        record: EditRecord,
        tx: DBWriteTransaction
    )

    func insertAttachment(
        attachment: TSAttachmentPointer,
        tx: DBWriteTransaction
    )
}

internal class _EditManager_DataStoreWrapper: EditManager.Shims.DataStore {

    func findTargetMessage(
        timestamp: UInt64,
        author: SignalServiceAddress,
        tx: DBReadTransaction
    ) -> TSInteraction? {
        return EditMessageFinder.editTarget(
            timestamp: timestamp,
            author: author,
            tx: tx
        )
    }

    func createOutgoingMessage(
        with builder: TSOutgoingMessageBuilder,
        tx: DBReadTransaction
    ) -> TSOutgoingMessage {
        return builder.build(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func copyRecipients(
        from source: TSOutgoingMessage,
        to target: TSOutgoingMessage,
        tx: DBWriteTransaction
    ) {
        target.updateWith(
            recipientAddressStates: source.recipientAddressStates,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    func getMediaAttachments(
        message: TSMessage,
        tx: DBReadTransaction
    ) -> [TSAttachment] {
        message.mediaAttachments(with: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead)
    }

    func getOversizedTextAttachments(
        message: TSMessage,
        tx: DBReadTransaction
    ) -> TSAttachment? {
        message.oversizeTextAttachment(with: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead)
    }

    func insertMessageCopy(
        message: TSMessage,
        tx: DBWriteTransaction
    ) {
        message.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func updateEditedMessage(
        message: TSMessage,
        tx: DBWriteTransaction
    ) {
        message.anyOverwritingUpdate(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func insertEditRecord(
        record: EditRecord,
        tx: DBWriteTransaction
    ) {
        do {
            try record.insert(SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database)
        } catch {
            owsFailDebug("Unexpected edit record insertion error \(error)")
        }
    }

    func insertAttachment(
        attachment: TSAttachmentPointer,
        tx: DBWriteTransaction
    ) {
        attachment.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

// MARK: - EditManager.Groups

public protocol _EditManager_GroupsShim {
    func groupId(for message: SSKProtoDataMessage) -> GroupV2ContextInfo?
}

internal class _EditManager_GroupsWrapper: EditManager.Shims.Groups {

    private let groupsV2: GroupsV2
    init(groupsV2: GroupsV2) { self.groupsV2 = groupsV2 }

    func groupId(for message: SSKProtoDataMessage) -> GroupV2ContextInfo? {
        guard let masterKey = message.groupV2?.masterKey else { return nil }
        return try? groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
    }
}

// MARK: - EditManager.LinkPreview

public protocol _EditManager_LinkPreviewShim {

    func buildPreview(
        dataMessage: SSKProtoDataMessage,
        tx: DBWriteTransaction
    ) throws -> OWSLinkPreview
}

internal class _EditManager_LinkPreviewWrapper: EditManager.Shims.LinkPreview {

    public func buildPreview(
        dataMessage: SSKProtoDataMessage,
        tx: DBWriteTransaction
    ) throws -> OWSLinkPreview {
        return try OWSLinkPreview.buildValidatedLinkPreview(
            dataMessage: dataMessage,
            body: dataMessage.body,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}
