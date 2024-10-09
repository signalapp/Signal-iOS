//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public protocol CallRecordSyncMessageConversationIdAdapter {
    /// Fetch the ``CallRecord`` for the given call and conversation ID, if one
    /// exists.
    func hydrate(
        conversationId: Data,
        callId: UInt64,
        tx: DBReadTransaction
    ) throws -> CallRecord?

    /// Generates a conversation ID for use in call-related sync messages, from
    /// a ``CallRecord``.
    func getConversationId(
        callRecord: CallRecord,
        tx: DBReadTransaction
    ) throws -> Data
}

class CallRecordSyncMessageConversationIdAdapterImpl: CallRecordSyncMessageConversationIdAdapter {

    private let callLinkStore: any CallLinkRecordStore
    private let callRecordStore: CallRecordStore
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let threadStore: ThreadStore

    init(
        callLinkStore: any CallLinkRecordStore,
        callRecordStore: CallRecordStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        threadStore: ThreadStore
    ) {
        self.callLinkStore = callLinkStore
        self.callRecordStore = callRecordStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.threadStore = threadStore
    }

    // MARK: -

    func hydrate(
        conversationId: Data,
        callId: UInt64,
        tx: DBReadTransaction
    ) throws -> CallRecord? {
        return try parse(conversationId: conversationId, tx: tx).flatMap {
            return callRecordStore.fetch(callId: callId, conversationId: $0, tx: tx).unwrapped
        }
    }

    private func parse(conversationId: Data, tx: DBReadTransaction) throws -> CallRecord.ConversationID? {
        if let serviceId = try? ServiceId.parseFrom(serviceIdBinary: conversationId) {
            guard
                let recipient = recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx),
                let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx)
            else {
                return nil
            }
            return .thread(threadRowId: contactThread.sqliteRowId!)
        }
        if
            let groupId = try? GroupIdentifier(contents: [UInt8](conversationId)),
            let groupThread = threadStore.fetchGroupThread(groupId: groupId.serialize().asData, tx: tx)
        {
            return .thread(threadRowId: groupThread.sqliteRowId!)
        }
        if let callLinkRecord = try callLinkStore.fetch(roomId: conversationId, tx: tx) {
            return .callLink(callLinkRowId: callLinkRecord.id)
        }
        return nil
    }

    func getConversationId(
        callRecord: CallRecord,
        tx: DBReadTransaction
    ) throws -> Data {
        switch callRecord.conversationId {
        case .thread(let threadRowId):
            switch threadStore.fetchThread(rowId: threadRowId, tx: tx) {
            case let thread as TSContactThread:
                if let serviceId = recipientDatabaseTable.fetchServiceId(contactThread: thread, tx: tx) {
                    return serviceId.serviceIdBinary.asData
                }
                throw OWSAssertionError("Missing contact service ID - how did we get here?")
            case let thread as TSGroupThread:
                return thread.groupId
            default:
                throw OWSAssertionError("Unexpected thread type for call record!")
            }
        case .callLink(let callLinkRowId):
            guard let callLinkRecord = try callLinkStore.fetch(rowId: callLinkRowId, tx: tx) else {
                throw OWSAssertionError("Missing CallLinkRecord - how did we get here?")
            }
            return callLinkRecord.roomId
        }
    }
}
