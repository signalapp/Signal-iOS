//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

class TSAttachmentDownloadManagerTest: SSKBaseTest {

    func testEnumerateMessagesWithLegacyAttachments() throws {
        func makeRandomAttachment(tx: SDSAnyWriteTransaction) -> TSAttachment {
            let attachmentData = Randomness.generateRandomBytes(1024)
            let attachment = TSAttachmentStream(
                contentType: MimeType.imageGif.rawValue,
                byteCount: UInt32(attachmentData.count),
                sourceFilename: "some.gif",
                caption: nil,
                attachmentType: .default,
                albumMessageId: nil
            )
            attachment.anyInsert(transaction: tx)
            return attachment
        }

        // Create some messages with attachments.
        let threads = ContactThreadFactory().create(count: 2)
        let threadMessages = threads.map { thread in
            let messageFactory = IncomingMessageFactory()
            messageFactory.threadCreator = { _ in thread }
            var n = 0
            messageFactory.attachmentIdsBuilder = { tx in
                defer { n += 1 }
                return (0..<n).map { _ in
                    return makeRandomAttachment(tx: tx).uniqueId
                }
            }
            return messageFactory.create(count: 3)
        }

        // Query for the attachments in one specific thread.
        var actualUniqueIds = Set<String>()
        read { transaction in
            try! TSAttachmentDownloadManager.enumerateMessagesWithLegacyAttachments(
                inThreadUniqueId: threads[0].uniqueId,
                transaction: transaction
            ) { message, _ in
                actualUniqueIds.insert(message.uniqueId)
            }
        }

        // Make sure we got back the right messages from the right thread.
        let expectedUniqueIds = Set(threadMessages[0].dropFirst().lazy.map { $0.uniqueId })
        XCTAssertEqual(actualUniqueIds, expectedUniqueIds)
    }
}
