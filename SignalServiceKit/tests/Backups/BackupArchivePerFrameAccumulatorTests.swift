//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
@testable import SignalServiceKit

struct BackupArchivePerFrameAccumulatorTests {
    private let attachmentByteCounter = BackupArchiveAttachmentByteCounter()
    private let attachmentCollector = LocalFileBackupAttachmentCollector()
    private let db = InMemoryDB()
    private let stream = MockOutputStream()

    // MARK: -

    @Test
    func testWrittenFrameKeepsAccumulatedData() {
        let attachmentStream = AttachmentStream.mock()

        withContext { context in
            context.processFrame { frameBencher in
                accumulate(attachmentStream: attachmentStream, context: context)
                #expect(writeFrame(context: context, frameBencher: frameBencher) == nil)
            }
        }

        #expect(stream.writtenFrameCount == 1)
        #expect(attachmentCollector.attachments == [attachmentStream.attachment.id])
        #expect(attachmentByteCounter.localAttachmentByteSize() == 10)
        #expect(attachmentByteCounter.remoteAttachmentByteSize() == 20)
    }

    @Test
    func testDroppedFrameDiscardsAccumulatedData() {
        let droppedAttachmentStream = AttachmentStream.mock()

        withContext { context in
            context.processFrame { _ in
                accumulate(attachmentStream: droppedAttachmentStream, context: context)
            }

            // A later frame shouldn't pick up the dropped frame's data.
            context.processFrame { frameBencher in
                #expect(writeFrame(context: context, frameBencher: frameBencher) == nil)
            }
        }

        #expect(stream.writtenFrameCount == 1)
        #expect(attachmentCollector.attachments.isEmpty)
        #expect(attachmentByteCounter.localAttachmentByteSize() == 0)
        #expect(attachmentByteCounter.remoteAttachmentByteSize() == 0)
    }

    @Test
    func testFailedWriteDiscardsAccumulatedData() {
        let failedAttachmentStream = AttachmentStream.mock()
        let writtenAttachmentStream = AttachmentStream.mock()

        withContext { context in
            stream.shouldFail = true
            context.processFrame { frameBencher in
                accumulate(attachmentStream: failedAttachmentStream, context: context)
                #expect(writeFrame(context: context, frameBencher: frameBencher) != nil)
            }

            stream.shouldFail = false
            context.processFrame { frameBencher in
                accumulate(attachmentStream: writtenAttachmentStream, context: context)
                #expect(writeFrame(context: context, frameBencher: frameBencher) == nil)
            }
        }

        #expect(stream.writtenFrameCount == 1)
        #expect(attachmentCollector.attachments == [writtenAttachmentStream.attachment.id])
        #expect(attachmentByteCounter.localAttachmentByteSize() == 10)
        #expect(attachmentByteCounter.remoteAttachmentByteSize() == 20)
    }

    @Test
    func testEnumeratedFramesKeepOnlyWrittenData() {
        let droppedAttachmentStream = AttachmentStream.mock()
        let writtenAttachmentStream = AttachmentStream.mock()

        withContext { context in
            try! context.wrapEnumeration(
                enumerationBlock: { _, block throws(CancellationError) in
                    for attachmentStream in [droppedAttachmentStream, writtenAttachmentStream] {
                        guard try block(attachmentStream) else { break }
                    }
                },
                perEnumerantBlock: { attachmentStream, frameBencher in
                    accumulate(attachmentStream: attachmentStream, context: context)
                    // Only write a frame for the second enumerant.
                    if attachmentStream === writtenAttachmentStream {
                        #expect(writeFrame(context: context, frameBencher: frameBencher) == nil)
                    }
                    return true
                },
            )
        }

        #expect(stream.writtenFrameCount == 1)
        #expect(attachmentCollector.attachments == [writtenAttachmentStream.attachment.id])
        #expect(attachmentByteCounter.localAttachmentByteSize() == 10)
        #expect(attachmentByteCounter.remoteAttachmentByteSize() == 20)
    }

    // MARK: -

    private func withContext(_ block: (BackupArchive.ArchivingContext) -> Void) {
        let bencher = BackupArchive.ArchiveBencher(
            dateProviderMonotonic: { MonotonicDate() },
            memorySampler: NoopMemorySampler(),
        )
        let perFrameAccumulator = BackupArchive.ArchivingContext.PerFrameAccumulator(
            attachmentByteCounter: attachmentByteCounter,
            localFileBackupAttachmentCollector: attachmentCollector,
        )

        db.read { tx in
            block(BackupArchive.ArchivingContext(
                localIdentifiers: .forUnitTests,
                startDate: Date(),
                remoteConfig: RemoteConfig(clockSkew: 0, valueFlags: [:]),
                currentUploadEra: "",
                bencher: bencher,
                includedContentFilter: BackupArchive.IncludedContentFilter(backupPurpose: .remoteBackup),
                perFrameAccumulator: perFrameAccumulator,
                tx: tx,
            ))
        }
    }

    private func accumulate(
        attachmentStream: AttachmentStream,
        context: BackupArchive.ArchivingContext,
    ) {
        let attachmentId = attachmentStream.attachment.id

        context.collectLocalFileBackupAttachment(attachmentStream: attachmentStream)
        context.addToLocalAttachmentByteCount(attachmentId: attachmentId, byteCount: 10)
        context.addToRemoteAttachmentByteCount(attachmentId: attachmentId, byteCount: 20)
    }

    private func writeFrame(
        context: BackupArchive.ArchivingContext,
        frameBencher: BackupArchive.Bencher.FrameBencher,
    ) -> BackupArchive.ArchiveFrameError? {
        return context.writeFrame(toStream: stream, flush: .none, frameBencher: frameBencher) {
            BackupProto_Frame()
        }
    }
}

// MARK: -

private class MockOutputStream: BackupArchiveOutputStream {
    var shouldFail = false
    private(set) var writtenFrameCount = 0

    func writeHeader(_ header: BackupProto_BackupInfo) throws {}

    func writeFrame(_ frame: BackupProto_Frame, flush: BackupArchiveFlushBehavior) throws {
        if shouldFail {
            throw OWSGenericError("Failing for tests!")
        }
        writtenFrameCount += 1
    }

    func closeFileStream() throws {}
}

private struct NoopMemorySampler: MemorySampler {
    func sample() {}
}
