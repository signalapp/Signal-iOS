//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

class FakeMessageSender: MessageSender {
    var stubbedFailingErrors = [Error?]()
    var sentMessages = [TSOutgoingMessage]()
    var sendMessageWasCalledBlock: ((TSOutgoingMessage) -> Void)?

    init(accountChecker: AccountChecker) {
        super.init(accountChecker: accountChecker, groupSendEndorsementStore: GroupSendEndorsementStoreImpl())
    }

    override func sendMessage(_ preparedMessage: PreparedOutgoingMessage) async -> MessageSender.SendResult {
        do {
            try await preparedMessage.send { message in
                sentMessages.append(message)
                sendMessageWasCalledBlock?(message)
            }
        } catch {
            return .overallFailure(error)
        }
        if let stubbedFailingError = stubbedFailingErrors.removeFirst() {
            return .overallFailure(stubbedFailingError)
        }
        return .success
    }
}

#endif
