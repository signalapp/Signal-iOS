//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

class MockCallRecordSyncMessageConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter {
    var mockHydratedCallRecord: CallRecord?
    func hydrate(
        callId: UInt64,
        conversationId: CallSyncMessageConversationId,
        tx: DBReadTransaction
    ) -> CallRecord? {
        return mockHydratedCallRecord
    }

    var mockConversationId: CallSyncMessageConversationId?
    func getConversationId(
        callRecord: CallRecord,
        tx: DBReadTransaction
    ) -> CallSyncMessageConversationId? {
        return mockConversationId
    }
}

#endif
