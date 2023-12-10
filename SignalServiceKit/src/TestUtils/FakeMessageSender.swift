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

    override func sendMessage(_ outgoingMessagePreparer: OutgoingMessagePreparer) async throws {
        sendMessageWasCalledBlock?(outgoingMessagePreparer.message)
        sentMessages.append(outgoingMessagePreparer.message)
        if let stubbedFailingError = stubbedFailingErrors.removeFirst() { throw stubbedFailingError }
    }

    override func sendTemporaryAttachment(dataSource: DataSource, contentType: String, message: TSOutgoingMessage) async throws {
        if let stubbedFailingError = stubbedFailingErrors.removeFirst() { throw stubbedFailingError }
    }
}

#endif
