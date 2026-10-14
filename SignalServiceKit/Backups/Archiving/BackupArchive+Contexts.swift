//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension BackupArchive {

    /// Base context class used for archiving (creating a backup).
    ///
    /// Requires a write tx on init; we want to hold the write lock while
    /// creating a backup to avoid races with e.g. message processing.
    ///
    /// But only exposes a read tx, because we explicitly do not want
    /// archiving to be updating the database, just reading from it.
    /// (The exception to this is enqueuing attachment uploads.)
    class ArchivingContext {
        /// `LocalIdentifiers` for the user doing the archiving.
        let localIdentifiers: LocalIdentifiers
        /// The timestamp at which the archiving process started.
        let startDate: Date
        /// The remote config at the start of archiving.
        let remoteConfig: RemoteConfig
        /// The upload era at the start of archiving.
        /// - SeeAlso ``BackupAttachmentUploadEraStore``
        let currentUploadEra: String
        /// For benchmarking archive steps.
        let bencher: BackupArchive.ArchiveBencher
        /// Parameters configuring what content is included in this archive.
        let includedContentFilter: IncludedContentFilter
        /// Holds data for the frame being archived. Shared by all contexts in
        /// a single archive.
        private let perFrameAccumulator: PerFrameAccumulator
        /// The single transaction used to create the archive.
        let tx: DBReadTransaction

        init(
            localIdentifiers: LocalIdentifiers,
            startDate: Date,
            remoteConfig: RemoteConfig,
            currentUploadEra: String,
            bencher: BackupArchive.ArchiveBencher,
            includedContentFilter: IncludedContentFilter,
            perFrameAccumulator: PerFrameAccumulator,
            tx: DBReadTransaction,
        ) {
            self.localIdentifiers = localIdentifiers
            self.startDate = startDate
            self.remoteConfig = remoteConfig
            self.currentUploadEra = currentUploadEra
            self.bencher = bencher
            self.includedContentFilter = includedContentFilter
            self.perFrameAccumulator = perFrameAccumulator
            self.tx = tx
        }

        // MARK: - Frames

        /// Enumerate models, archiving a frame for each.
        ///
        /// - SeeAlso `ArchiveBencher/wrapEnumeration`.
        func wrapEnumeration<Enumerant>(
            enumerationBlock: (DBReadTransaction, (Enumerant) throws(CancellationError) -> Bool) throws(CancellationError) -> Void,
            perEnumerantBlock: @escaping (Enumerant, Bencher.FrameBencher) -> Bool,
        ) throws(CancellationError) {
            try bencher.wrapEnumeration(
                tx: tx,
                enumerationBlock: enumerationBlock,
                perEnumerantBlock: { [self] enumerant, frameBencher in
                    archiveFrame {
                        perEnumerantBlock(enumerant, frameBencher)
                    }
                },
            )
        }

        /// Archive a single frame.
        ///
        /// - SeeAlso `Bencher/processFrame`.
        func processFrame<T>(_ block: (Bencher.FrameBencher) throws -> T) rethrows -> T {
            return try bencher.processFrame { frameBencher in
                try archiveFrame {
                    try block(frameBencher)
                }
            }
        }

        /// Per-frame data accumulated in `block` is discarded unless the frame
        /// is written via `writeFrame`.
        private func archiveFrame<T>(_ block: () throws -> T) rethrows -> T {
            defer { perFrameAccumulator.resetFrameData() }
            return try block()
        }

        /// Build a frame and write it to the stream. If successful, keeps the
        /// per-frame data accumulated for the frame.
        func writeFrame(
            toStream stream: BackupArchiveOutputStream,
            flush: BackupArchiveFlushBehavior,
            frameBencher: Bencher.FrameBencher,
            frameBuilder: () -> BackupProto_Frame,
        ) -> ArchiveFrameError? {
            let frame = frameBuilder()
            frameBencher.didProcessFrame(frame)

            do {
                try stream.writeFrame(frame, flush: flush)
            } catch {
                return .archiveFrameError(.streamWriteError(error))
            }

            perFrameAccumulator.commitFrameData()
            return nil
        }

        // MARK: - Per-frame data

        /// Whether we're collecting attachments for a Local File Backup; i.e.,
        /// are we performing a Local File Backup.
        var isCollectingLocalFileBackupAttachments: Bool {
            return perFrameAccumulator.localFileBackupAttachmentCollector != nil
        }

        /// Collect the given attachment to be exported alongside a Local File
        /// Backup.
        func collectLocalFileBackupAttachment(attachmentStream: AttachmentStream) {
            owsPrecondition(isCollectingLocalFileBackupAttachments)
            perFrameAccumulator.attachmentIdsToCollect.append(attachmentStream.attachment.id)
        }

        func addToLocalAttachmentByteCount(attachmentId: Attachment.IDType, byteCount: UInt64) {
            let byteCount = PerFrameAccumulator.AttachmentByteCount(
                attachmentId: attachmentId,
                byteCount: byteCount,
            )
            perFrameAccumulator.localAttachmentByteCounts.append(byteCount)
        }

        func addToRemoteAttachmentByteCount(attachmentId: Attachment.IDType, byteCount: UInt64) {
            let byteCount = PerFrameAccumulator.AttachmentByteCount(
                attachmentId: attachmentId,
                byteCount: byteCount,
            )
            perFrameAccumulator.remoteAttachmentByteCounts.append(byteCount)
        }

        // MARK: -

        /// Holds data derived while archiving a frame that isn't captured in
        /// the frame itself, such as the attachments the frame references.
        ///
        /// The accumulator is "committed" if we successfully write a frame, and
        /// "reset" when we finish archiving the frame. As a result, any
        /// accumulated data for frames that are discarded or fail to write is
        /// discarded.
        ///
        /// - Note
        /// One accumulator is shared by all contexts for a given archive, since
        /// a frame's data may be accumulated by multiple different contexts;
        /// for example, a chat's wallpaper is archived via its `customChatColorContext`.
        class PerFrameAccumulator {
            fileprivate struct AttachmentByteCount {
                let attachmentId: Attachment.IDType
                let byteCount: UInt64
            }

            fileprivate let attachmentByteCounter: BackupArchiveAttachmentByteCounter
            fileprivate let localFileBackupAttachmentCollector: LocalFileBackupAttachmentCollector?

            fileprivate var attachmentIdsToCollect: [Attachment.IDType] = []
            fileprivate var localAttachmentByteCounts: [AttachmentByteCount] = []
            fileprivate var remoteAttachmentByteCounts: [AttachmentByteCount] = []

            /// - Parameter localFileBackupAttachmentCollector
            /// Collects attachments to be exported alongside a local-file export.
            /// Presence indicates we are archiving a local-file export.
            init(
                attachmentByteCounter: BackupArchiveAttachmentByteCounter,
                localFileBackupAttachmentCollector: LocalFileBackupAttachmentCollector?,
            ) {
                self.attachmentByteCounter = attachmentByteCounter
                self.localFileBackupAttachmentCollector = localFileBackupAttachmentCollector
            }

            fileprivate func commitFrameData() {
                for attachmentId in attachmentIdsToCollect {
                    localFileBackupAttachmentCollector?.append(id: attachmentId)
                }
                for byteCount in localAttachmentByteCounts {
                    attachmentByteCounter.addToLocalByteCount(
                        attachmentID: byteCount.attachmentId,
                        byteCount: byteCount.byteCount,
                    )
                }
                for byteCount in remoteAttachmentByteCounts {
                    attachmentByteCounter.addToRemoteByteCount(
                        attachmentID: byteCount.attachmentId,
                        byteCount: byteCount.byteCount,
                    )
                }

                resetFrameData()
            }

            fileprivate func resetFrameData() {
                attachmentIdsToCollect = []
                localAttachmentByteCounts = []
                remoteAttachmentByteCounts = []
            }
        }
    }

    // MARK: -

    /// Base context class used for restoring from a backup.
    class RestoringContext {
        /// `LocalIdentifiers` for the user doing the restore.
        let localIdentifiers: LocalIdentifiers
        /// The timestamp at which we began restoring.
        let startDate: Date
        /// The remote config at the start of restoring.
        let remoteConfig: RemoteConfig
        /// Counts restored attachment bytes for future progress reporting.
        let attachmentByteCounter: BackupArchiveAttachmentByteCounter
        /// Are we restoring onto a primary?
        let isPrimaryDevice: Bool
        /// The single transaction used to restore the archive.
        let tx: DBWriteTransaction

        init(
            localIdentifiers: LocalIdentifiers,
            startDate: Date,
            remoteConfig: RemoteConfig,
            attachmentByteCounter: BackupArchiveAttachmentByteCounter,
            isPrimaryDevice: Bool,
            tx: DBWriteTransaction,
        ) {
            self.localIdentifiers = localIdentifiers
            self.startDate = startDate
            self.remoteConfig = remoteConfig
            self.attachmentByteCounter = attachmentByteCounter
            self.isPrimaryDevice = isPrimaryDevice
            self.tx = tx
        }
    }
}
