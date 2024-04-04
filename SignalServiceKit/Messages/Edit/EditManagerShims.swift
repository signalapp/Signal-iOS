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

    func build(
        _ builder: TSOutgoingMessageBuilder,
        tx: DBReadTransaction
    ) -> TSOutgoingMessage

    func createOutgoingEditMessage(
        thread: TSThread,
        targetMessageTimestamp: UInt64,
        editMessage: TSOutgoingMessage,
        tx: DBReadTransaction
    ) -> OutgoingEditMessage

    func update(
        _ message: TSOutgoingMessage,
        withRecipientAddressStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]?,
        tx: DBWriteTransaction
    )

    func isVoiceMessageAttachment(
        _ attachment: TSAttachment,
        inContainingMessage message: TSMessage,
        tx: DBReadTransaction
    ) -> Bool

    func insert(
        _ message: TSMessage,
        tx: DBWriteTransaction
    )

    func overwritingUpdate(
        _ message: TSMessage,
        tx: DBWriteTransaction
    )

    // TODO: remove this
    func insertAttachment(
        attachment: TSAttachmentPointer,
        tx: DBWriteTransaction
    )
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

    public func build(
        _ builder: TSOutgoingMessageBuilder,
        tx: DBReadTransaction
    ) -> TSOutgoingMessage {
        return builder.build(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func update(
        _ message: TSOutgoingMessage,
        withRecipientAddressStates recipientAddressStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]?,
        tx: DBWriteTransaction
    ) {
        message.updateWith(
            recipientAddressStates: recipientAddressStates,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func isVoiceMessageAttachment(
        _ attachment: TSAttachment,
        inContainingMessage message: TSMessage,
        tx: DBReadTransaction
    ) -> Bool {
        attachment.isVoiceMessage(inContainingMessage: message, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func insert(
        _ message: TSMessage,
        tx: DBWriteTransaction
    ) {
        message.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func overwritingUpdate(
        _ message: TSMessage,
        tx: DBWriteTransaction
    ) {
        message.anyOverwritingUpdate(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func insertAttachment(
        attachment: TSAttachmentPointer,
        tx: DBWriteTransaction
    ) {
        attachment.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
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

// MARK: - OWSReceiptManager

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
