//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

class FakeMessageSender: MessageSender {
    public var stubbedFailingErrors = [Error?]()
    public var sentMessages = [TSOutgoingMessage]()
    public var sendMessageWasCalledBlock: ((TSOutgoingMessage) -> Void)?

    init() {
        super.init(groupSendEndorsementStore: GroupSendEndorsementStoreImpl())
    }

    override func sendMessage(_ preparedMessage: PreparedOutgoingMessage) async throws {
        try await preparedMessage.send { message in
            sentMessages.append(message)
            sendMessageWasCalledBlock?(message)
        }
        if let stubbedFailingError = stubbedFailingErrors.removeFirst() { throw stubbedFailingError }
    }

    override func sendTransientContactSyncAttachment(
        dataSource: DataSource,
        localThread: TSContactThread
    ) async throws {
        if let stubbedFailingError = stubbedFailingErrors.removeFirst() { throw stubbedFailingError }
    }
}

#endif
