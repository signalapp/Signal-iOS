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
    ) -> CallRecord?

    /// Generates a conversation ID for use in call-related sync messages, from
    /// a ``CallRecord``.
    func getConversationId(
        callRecord: CallRecord,
        tx: DBReadTransaction
    ) -> Data?
}

class CallRecordSyncMessageConversationIdAdapterImpl: CallRecordSyncMessageConversationIdAdapter {

    private let callRecordStore: CallRecordStore
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let threadStore: ThreadStore

    init(
        callRecordStore: CallRecordStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        threadStore: ThreadStore
    ) {
        self.callRecordStore = callRecordStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.threadStore = threadStore
    }

    // MARK: -

    func hydrate(
        conversationId: Data,
        callId: UInt64,
        tx: DBReadTransaction
    ) -> CallRecord? {
        let threadRowId = { () -> Int64? in
            if let serviceId = try? ServiceId.parseFrom(serviceIdBinary: conversationId) {
                guard
                    let recipient = recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx),
                    let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx)
                else {
                    return nil
                }
                return contactThread.sqliteRowId!
            }
            // [CallLink] TODO: Generalize this because group IDs/room IDs are ambiguous.
            if let groupId = try? GroupIdentifier(contents: [UInt8](conversationId)) {
                return threadStore.fetchGroupThread(groupId: groupId.serialize().asData, tx: tx)?.sqliteRowId!
            }
            return nil
        }()

        guard let threadRowId else { return nil }

        return callRecordStore.fetch(
            callId: callId,
            conversationId: .thread(threadRowId: threadRowId),
            tx: tx
        ).unwrapped
    }

    func getConversationId(
        callRecord: CallRecord,
        tx: DBReadTransaction
    ) -> Data? {
        switch callRecord.conversationId {
        case .thread(let threadRowId):
            switch threadStore.fetchThread(rowId: threadRowId, tx: tx) {
            case let thread as TSContactThread:
                if let serviceId = recipientDatabaseTable.fetchServiceId(contactThread: thread, tx: tx) {
                    return serviceId.serviceIdBinary.asData
                }
                owsFailBeta("Missing contact service ID - how did we get here?")
                return nil
            case let thread as TSGroupThread:
                return thread.groupId
            default:
                owsFailBeta("Unexpected thread type for call record!")
                return nil
            }
        case .callLink(_):
            // [CallLink] TODO: .
            return nil
        }
    }
}
