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
        public typealias LinkPreview = _EditManager_LinkPreviewWrapper
        public typealias DataStore = _EditManager_DataStoreWrapper
        public typealias Groups = _EditManager_GroupsWrapper
    }
}

// MARK: - EditManager.DataStore

public protocol _EditManager_DataStore {

    func createOutgoingMessage(
        with builder: TSOutgoingMessageBuilder,
        tx: DBReadTransaction
    ) -> TSOutgoingMessage

    func createOutgoingEditMessage(
        thread: TSThread,
        targetMessageTimestamp: UInt64,
        editMessage: TSOutgoingMessage,
        tx: DBReadTransaction
    ) -> OutgoingEditMessage

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

    func numberOfEdits(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> Int

    func findEditTarget(
        timestamp: UInt64,
        authorAci: ServiceId?,
        tx: DBReadTransaction
    ) -> EditMessageTarget?
}

public class _EditManager_DataStoreWrapper: EditManager.Shims.DataStore {

    public func createOutgoingEditMessage(
        thread: TSThread,
        targetMessageTimestamp: UInt64,
        editMessage: TSOutgoingMessage,
        tx: DBReadTransaction
    ) -> OutgoingEditMessage {
        return OutgoingEditMessage(
            thread: thread,
            targetMessageTimestamp: targetMessageTimestamp,
            editMessage: editMessage,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func createOutgoingMessage(
        with builder: TSOutgoingMessageBuilder,
        tx: DBReadTransaction
    ) -> TSOutgoingMessage {
        return builder.build(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func copyRecipients(
        from source: TSOutgoingMessage,
        to target: TSOutgoingMessage,
        tx: DBWriteTransaction
    ) {
        target.updateWith(
            recipientAddressStates: source.recipientAddressStates,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func getMediaAttachments(
        message: TSMessage,
        tx: DBReadTransaction
    ) -> [TSAttachment] {
        message.mediaAttachments(with: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead)
    }

    public func getOversizedTextAttachments(
        message: TSMessage,
        tx: DBReadTransaction
    ) -> TSAttachment? {
        message.oversizeTextAttachment(with: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead)
    }

    public func insertMessageCopy(
        message: TSMessage,
        tx: DBWriteTransaction
    ) {
        message.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func updateEditedMessage(
        message: TSMessage,
        tx: DBWriteTransaction
    ) {
        message.anyOverwritingUpdate(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func insertEditRecord(
        record: EditRecord,
        tx: DBWriteTransaction
    ) {
        do {
            try record.insert(SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database)
        } catch {
            owsFailDebug("Unexpected edit record insertion error \(error)")
        }
    }

    public func insertAttachment(
        attachment: TSAttachmentPointer,
        tx: DBWriteTransaction
    ) {
        attachment.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func numberOfEdits(for message: TSMessage, tx: DBReadTransaction) -> Int {
        return EditMessageFinder.numberOfEdits(for: message, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func findEditTarget(
        timestamp: UInt64,
        authorAci: ServiceId?,
        tx: DBReadTransaction
    ) -> EditMessageTarget? {
        return EditMessageFinder.editTarget(
            timestamp: timestamp,
            authorAci: authorAci,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}

// MARK: - EditManager.Groups

public protocol _EditManager_GroupsShim {
    func groupId(for message: SSKProtoDataMessage) -> GroupV2ContextInfo?
}

public class _EditManager_GroupsWrapper: EditManager.Shims.Groups {

    private let groupsV2: GroupsV2
    public init(groupsV2: GroupsV2) { self.groupsV2 = groupsV2 }

    public func groupId(for message: SSKProtoDataMessage) -> GroupV2ContextInfo? {
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

public class _EditManager_LinkPreviewWrapper: EditManager.Shims.LinkPreview {

    public init() { }

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
