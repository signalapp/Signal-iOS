//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol SignalTSResourceCloner {

    func cloneAsSignalAttachment(
        attachment: ReferencedTSResourceStream
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
        attachment: ReferencedTSResourceStream
    ) throws -> SignalAttachment {
        switch (attachment.attachmentStream.concreteStreamType, attachment.reference.concreteType) {
        case (.legacy(let tsAttachmentStream), .legacy(_)):
            return try SignalTSAttachmentCloner.cloneAsSignalAttachment(
                attachment: tsAttachmentStream
            )
        case (.v2(let attachmentStream), .v2(let reference)):
            return try attachmentCloner.cloneAsSignalAttachment(
                attachment: .init(reference: reference, attachmentStream: attachmentStream)
            )
        case (.legacy, .v2), (.v2, .legacy):
            throw OWSAssertionError("Invalid combination!")
        }
    }
}

#if TESTABLE_BUILD

public class SignalTSResourceClonerMock: SignalTSResourceCloner {

    public init() {}

    public func cloneAsSignalAttachment(
        attachment: ReferencedTSResourceStream
    ) throws -> SignalAttachment {
        throw OWSAssertionError("Unimplemented")
    }
}

#endif
