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

    override func sendMessage(_ preparedMessage: PreparedOutgoingMessage) async throws {
        sendMessageWasCalledBlock?(preparedMessage.testOnly_messageForSending)
        sentMessages.append(preparedMessage.testOnly_messageForSending)
        if let stubbedFailingError = stubbedFailingErrors.removeFirst() { throw stubbedFailingError }
    }

    override func sendTransientContactSyncAttachment(
        dataSource: DataSource,
        thread: TSThread
    ) async throws {
        if let stubbedFailingError = stubbedFailingErrors.removeFirst() { throw stubbedFailingError }
    }
}

#endif
