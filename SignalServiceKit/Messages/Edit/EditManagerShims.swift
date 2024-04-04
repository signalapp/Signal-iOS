//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension EditManagerImpl {
    public enum Shims {
        public typealias DataStore = _EditManagerImpl_DataStore
        public typealias Groups = _EditManagerImpl_GroupsShim
        public typealias ReceiptManager = _EditManagerImpl_ReceiptManagerShim
    }

    public enum Wrappers {
        public typealias DataStore = _EditManagerImpl_DataStoreWrapper
        public typealias Groups = _EditManagerImpl_GroupsWrapper
        public typealias ReceiptManager = _EditManagerImpl_ReceiptManagerWrapper
    }
}

// MARK: - EditManager.DataStore

public protocol _EditManagerImpl_DataStore {

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

    func getIsVoiceMessage(
        forAttachment attachment: TSAttachment,
        on message: TSMessage,
        tx: DBReadTransaction
    ) -> Bool

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
        authorAci: Aci?,
        tx: DBReadTransaction
    ) -> EditMessageTarget?

    func findEditHistory(
        for message: TSMessage,
        tx: DBReadTransaction
    ) throws -> [(EditRecord, TSMessage?)]

    func update(
        editRecord: EditRecord,
        tx: DBWriteTransaction
    ) throws
}

public class _EditManagerImpl_DataStoreWrapper: EditManagerImpl.Shims.DataStore {

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

    public func getIsVoiceMessage(
        forAttachment attachment: TSAttachment,
        on message: TSMessage,
        tx: DBReadTransaction
    ) -> Bool {
        attachment.isVoiceMessage(inContainingMessage: message, transaction: SDSDB.shimOnlyBridge(tx))
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
        authorAci: Aci?,
        tx: DBReadTransaction
    ) -> EditMessageTarget? {
        return EditMessageFinder.editTarget(
            timestamp: timestamp,
            authorAci: authorAci,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func findEditHistory(
        for message: TSMessage,
        tx: DBReadTransaction
    ) throws -> [(EditRecord, TSMessage?)] {
        return try EditMessageFinder.findEditHistory(
            for: message,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func update(
        editRecord: EditRecord,
        tx: DBWriteTransaction
    ) throws {
        try editRecord.update(SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database)
    }
}

// MARK: - EditManager.Groups

public protocol _EditManagerImpl_GroupsShim {
    func groupId(for message: SSKProtoDataMessage) -> GroupV2ContextInfo?
}

public class _EditManagerImpl_GroupsWrapper: EditManagerImpl.Shims.Groups {

    private let groupsV2: GroupsV2
    public init(groupsV2: GroupsV2) { self.groupsV2 = groupsV2 }

    public func groupId(for message: SSKProtoDataMessage) -> GroupV2ContextInfo? {
        guard let masterKey = message.groupV2?.masterKey else { return nil }
        return try? groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
    }
}

public protocol _EditManagerImpl_ReceiptManagerShim {
    func messageWasRead(
        _ message: TSIncomingMessage,
        thread: TSThread,
        circumstance: OWSReceiptCircumstance,
        tx: DBWriteTransaction
    )
}

public struct _EditManagerImpl_ReceiptManagerWrapper: EditManagerImpl.Shims.ReceiptManager {

    private let receiptManager: OWSReceiptManager
    public init(receiptManager: OWSReceiptManager) {
        self.receiptManager = receiptManager
    }

    public func messageWasRead(
        _ message: TSIncomingMessage,
        thread: TSThread,
        circumstance: OWSReceiptCircumstance,
        tx: DBWriteTransaction
    ) {
        receiptManager.messageWasRead(
            message,
            thread: thread,
            circumstance: circumstance,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}
