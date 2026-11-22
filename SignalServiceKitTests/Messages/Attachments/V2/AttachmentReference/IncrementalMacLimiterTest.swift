//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct IncrementalMacLimiterTest {

    @Test
    func capsIncrementalMacs() throws {
        let referencedAttachments = try [true, false, true, true, true].map {
            try makeReferencedAttachment(hasIncrementalMac: $0)
        }

        var incrementalMacLimiter = IncrementalMacLimiter(
            maxIncrementalMacs: 2,
        )
        let protos = try referencedAttachments.map {
            let proto = incrementalMacLimiter.buildProto(
                referencedAttachment: $0,
            )
            return try #require(proto)
        }

        #expect(
            protos.map { $0.hasIncrementalMac }
                == [true, false, true, false, false],
        )
        #expect(
            protos.map { $0.hasChunkSize }
                == [true, false, true, false, false],
        )
    }

    @Test
    func includesAllIncrementalMacsUnderLimit() throws {
        let referencedAttachments = try (0..<3).map { _ in
            try makeReferencedAttachment(hasIncrementalMac: true)
        }

        var incrementalMacLimiter = IncrementalMacLimiter(
            maxIncrementalMacs: 10,
        )
        let protos = try referencedAttachments.map {
            let proto = incrementalMacLimiter.buildProto(
                referencedAttachment: $0,
            )
            return try #require(proto)
        }

        #expect(protos.allSatisfy { $0.hasIncrementalMac })
    }

    // MARK: -

    private func makeReferencedAttachment(
        hasIncrementalMac: Bool,
    ) throws -> ReferencedAttachment {
        let incrementalMacInfo: Attachment.IncrementalMacInfo?
        if hasIncrementalMac {
            incrementalMacInfo = Attachment.IncrementalMacInfo(
                mac: Randomness.generateRandomBytes(32),
                chunkSize: 64 * 1024,
            )
        } else {
            incrementalMacInfo = nil
        }

        let attachment = Attachment.mock(
            transitTierInfo: .mock(incrementalMacInfo: incrementalMacInfo),
        )

        let referenceParams = AttachmentReference.ConstructionParams
            .mockMessageBodyAttachmentReference(
                attachmentRecord: Attachment.Record(attachment: attachment),
                messageRowId: 1,
                threadRowId: 1,
            )
        guard case .message(let messageSource) = referenceParams.owner else {
            throw OWSAssertionError("Unexpected owner")
        }
        let reference = try AttachmentReference(
            record: AttachmentReference.MessageAttachmentReferenceRecord(
                attachmentRowId: attachment.id,
                sourceFilename: referenceParams.sourceFilename,
                sourceUnencryptedByteCount: referenceParams
                    .sourceUnencryptedByteCount,
                sourceMediaSizePixels: referenceParams.sourceMediaSizePixels,
                messageSource: messageSource,
            ),
        )

        return ReferencedAttachment(reference: reference, attachment: attachment)
    }
}
