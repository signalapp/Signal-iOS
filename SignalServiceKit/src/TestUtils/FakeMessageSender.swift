//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

class FakeMessageSender: MessageSender {
    public var stubbedFailingError: Error?
    public var sendMessageWasCalledBlock: ((TSOutgoingMessage) -> Void)?

    public override func sendMessage(
        _ outgoingMessagePreparer: OutgoingMessagePreparer,
        success: @escaping () -> Void,
        failure: @escaping (Error) -> Void
    ) {
        fakeCompletion(success: success, failure: failure)
        sendMessageWasCalledBlock?(outgoingMessagePreparer.message)
    }

    public override func sendAttachment(
        _ dataSource: DataSource,
        contentType: String,
        sourceFilename: String?,
        albumMessageId: String?,
        in: TSOutgoingMessage,
        success: @escaping () -> Void,
        failure: @escaping (Error) -> Void
    ) {
        fakeCompletion(success: success, failure: failure)
    }

    public override func sendTemporaryAttachment(
        _ dataSource: DataSource,
        contentType: String,
        in: TSOutgoingMessage,
        success: @escaping () -> Void,
        failure: @escaping (Error) -> Void
    ) {
        fakeCompletion(success: success, failure: failure)
    }

    private func fakeCompletion(success: () -> Void, failure: (Error) -> Void) {
        if let stubbedFailingError = stubbedFailingError {
            failure(stubbedFailingError)
        } else {
            success()
        }
    }
}

#endif
