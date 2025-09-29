//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

final class FakeMessageSender: MessageSender {
    public var stubbedFailingErrors = [Error?]()
    public var sentMessages = [TSOutgoingMessage]()
    public var sendMessageWasCalledBlock: ((TSOutgoingMessage) -> Void)?

    init(accountChecker: AccountChecker) {
        super.init(accountChecker: accountChecker, groupSendEndorsementStore: GroupSendEndorsementStoreImpl())
    }

    override func sendMessage(_ preparedMessage: PreparedOutgoingMessage) async throws {
        try await preparedMessage.send { message in
            sentMessages.append(message)
            sendMessageWasCalledBlock?(message)
        }
        if let stubbedFailingError = stubbedFailingErrors.removeFirst() { throw stubbedFailingError }
    }
}

#endif
