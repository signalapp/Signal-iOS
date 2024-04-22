//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol SignalTSResourceCloner {

    func cloneAsSignalAttachment(
        attachment: TSAttachmentStream,
        sourceMessage: TSMessage,
        tx: DBReadTransaction
    ) throws -> SignalAttachment

    func cloneAsSignalAttachment(
        attachment: TSAttachmentStream,
        sourceStoryMessage: StoryMessage,
        tx: DBReadTransaction
    ) throws -> SignalAttachment
}

public class SignalTSResourceClonerImpl: SignalTSResourceCloner {

    private let attachmentCloner: SignalAttachmentCloner

    public init(
        attachmentCloner: SignalAttachmentCloner
    ) {
        self.attachmentCloner = attachmentCloner
    }

    public func cloneAsSignalAttachment(
        attachment: TSAttachmentStream,
        sourceMessage: TSMessage,
        tx: DBReadTransaction
    ) throws -> SignalAttachment {
        let request = try SignalTSAttachmentCloner.cloneAsSignalAttachmentRequest(
            attachment: attachment,
            sourceMessage: sourceMessage,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
        return try attachmentCloner.cloneAsSignalAttachment(request: request)
    }

    public func cloneAsSignalAttachment(
        attachment: TSAttachmentStream,
        sourceStoryMessage: StoryMessage,
        tx: DBReadTransaction
    ) throws -> SignalAttachment {
        let request = try SignalTSAttachmentCloner.cloneAsSignalAttachmentRequest(
            attachment: attachment,
            sourceStoryMessage: sourceStoryMessage,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
        return try attachmentCloner.cloneAsSignalAttachment(request: request)
    }
}

#if TESTABLE_BUILD

public class SignalTSResourceClonerMock: SignalTSResourceCloner {

    public init() {}

    public func cloneAsSignalAttachment(
        attachment: TSAttachmentStream,
        sourceMessage: TSMessage,
        tx: DBReadTransaction
    ) throws -> SignalAttachment {
        throw OWSAssertionError("Unimplemented")
    }

    public func cloneAsSignalAttachment(
        attachment: TSAttachmentStream,
        sourceStoryMessage: StoryMessage,
        tx: DBReadTransaction
    ) throws -> SignalAttachment {
        throw OWSAssertionError("Unimplemented")
    }
}

#endif
