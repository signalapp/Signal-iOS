//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

class MockCallRecordSyncMessageConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter {
    var mockHydratedCallRecord: CallRecord?
    func hydrate(
        conversationId: Data,
        callId: UInt64,
        tx: DBReadTransaction
    ) -> CallRecord? {
        return mockHydratedCallRecord
    }

    var mockConversationId: Data?
    func getConversationId(
        callRecord: CallRecord,
        tx: DBReadTransaction
    ) throws -> Data {
        return mockConversationId!
    }
}

#endif
