//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

public class BackupAttachmentUploadProgressObserver {
    fileprivate let queueSnapshot: BackupAttachmentUploadProgressImpl.UploadQueueSnapshot
    fileprivate let sink: OWSProgressSink
    fileprivate let source: OWSProgressSource
    private weak var progress: BackupAttachmentUploadProgress?
    fileprivate let id: UUID = UUID()

    fileprivate init(
        queueSnapshot: BackupAttachmentUploadProgressImpl.UploadQueueSnapshot,
        sink: OWSProgressSink,
        source: OWSProgressSource,
        progress: BackupAttachmentUploadProgress?
    ) {
        self.queueSnapshot = queueSnapshot
        self.sink = sink
        self.source = source
        self.progress = progress
    }

    deinit {
        Task { [weak progress, id] in
            await progress?.removeObserver(id)
        }
    }
}

/// Tracks and reports progress for backup (media tier) attachment uploads.
///
/// At observation time, checks the current total scheduled bytes to upload, and uses that
/// as the fixed total for the lifetime of the observation. Creating a new observation recomputes
/// the remaining total (which may have gone up if new attachments have been scheduled,
/// or gone down, including to 0, if uploads completed).
/// Note this contrasts with BackupAttachmentDownloadProgress, which is a singleton observer
/// and "remembers" the total bytes to download.
///
/// Note: ignores/excludes thumbnail uploads; just deals with fullsize attachments.
public protocol BackupAttachmentUploadProgress: AnyObject {

    typealias Observer = BackupAttachmentUploadProgressObserver

    /// Begin observing progress of all backup attachment uploads that are scheduled as of the time this method is called.
    /// The total count will not change over the lifetime of the observer, even if new attachments are scheduled for upload.
    /// The returned observer must be retained to continue receiving updates (Careful of retain cycles; the observer retains the block).
    func addObserver(_ block: @escaping (OWSProgress) -> Void) async throws -> Observer

    func removeObserver(_ observer: Observer) async

    func removeObserver(_ id: UUID) async

    /// Create an OWSProgressSink for a single attachment to be uploaded.
    /// Should be called prior to uploading any backup attachment.
    func willBeginUploadingAttachment(
        uploadRecord: QueuedBackupAttachmentUpload
    ) async -> OWSProgressSink

    /// Stopgap to inform that an attachment finished uploading.
    /// There are a couple edge cases (e.g. already uploaded) that result in uploads
    /// finishing without reporting any progress updates. This method ensures we always mark
    /// attachments as finished in all cases.
    func didFinishUploadOfAttachment(
        uploadRecord: QueuedBackupAttachmentUpload
    ) async

    /// Called when there are no more enqueued uploads.
    /// As a final stopgap, in case we missed some bytes and counting got out of sync,
    /// this should fully advance the uploaded byte count to the total byte count.
    func didEmptyUploadQueue() async
}

public actor BackupAttachmentUploadProgressImpl: BackupAttachmentUploadProgress {

    // MARK: - Public API

    public func addObserver(_ block: @escaping (OWSProgress) -> Void) async throws -> Observer {
        let queueSnapshot = try self.computeRemainingUnuploadedByteCount()
        let sink = OWSProgress.createSink(block)
        let source = await sink.addSource(withLabel: "", unitCount: queueSnapshot.totalByteCount)
        let observer = Observer(
            queueSnapshot: queueSnapshot,
            sink: sink,
            source: source,
            progress: self
        )
        observers.append(observer)
        return observer
    }

    public func removeObserver(_ observer: Observer) {
        self.removeObserver(observer.id)
    }

    // MARK: - BackupAttachmentUploadManager API

    public func willBeginUploadingAttachment(
        uploadRecord: QueuedBackupAttachmentUpload
    ) async -> OWSProgressSink {
        let sink = OWSProgress.createSink { [weak self] progress in
            Task {
                await self?.didUpdateProgressForActiveUpload(
                    uploadRecord: uploadRecord,
                    completedByteCount: progress.completedUnitCount,
                    totalByteCount: progress.totalUnitCount
                )
            }
        }
        return sink
    }

    public func didFinishUploadOfAttachment(
        uploadRecord: QueuedBackupAttachmentUpload
    ) {
        didUpdateProgressForActiveUpload(
            uploadRecord: uploadRecord,
            completedByteCount: UInt64(uploadRecord.estimatedByteCount),
            totalByteCount: UInt64(uploadRecord.estimatedByteCount)
        )
    }

    public func didEmptyUploadQueue() async {
        activeUploadByteCounts.keys.forEach {
            recentlyCompletedUploads.set(key: $0, value: ())
        }
        activeUploadByteCounts = [:]
        observers.cullExpired()
        observers.elements.forEach { observer in
            let source = observer.source
            if source.totalUnitCount > 0, source.totalUnitCount > source.completedUnitCount {
                source.incrementCompletedUnitCount(by: source.totalUnitCount - source.completedUnitCount)
            }
        }
    }

    // MARK: - Private

    private nonisolated let db: DB

    init(db: DB) {
        self.db = db
    }

    private var observers = WeakArray<Observer>()

    private struct PerObserverUploadId: Hashable {
        let observerId: UUID
        let attachmentId: Attachment.IDType
        let isFullsize: Bool
    }

    /// Currently active uploads for which we update progress byte-by-byte.
    private var activeUploadByteCounts = [PerObserverUploadId: UInt64]()
    /// There is a race between receiving the final OWSProgress update for a given attachment
    /// and being told the attachment finished uploading by BackupAttachmentUploadManager.
    /// To resolve this race, track recently completed uploads so we know not to double count.
    /// There could be tens of thousands of attachments, so to minimize memory usage only keep
    /// an LRUCache. In practice that will catch all races. Even if it doesn't, the downside
    /// is we misreport progress until we hit 100%, big whoop.
    private var recentlyCompletedUploads = LRUCache<PerObserverUploadId, Void>(maxSize: 100)

    private func didUpdateProgressForActiveUpload(
        uploadRecord: QueuedBackupAttachmentUpload,
        completedByteCount: UInt64,
        totalByteCount: UInt64
    ) {
        guard
            totalByteCount != 0
        else {
            return
        }

        observers.elements.forEach { observer in
            guard
                let maxRowId = observer.queueSnapshot.maxRowId,
                maxRowId >= uploadRecord.id ?? 0
            else {
                return
            }
            let uploadId = PerObserverUploadId(
                observerId: observer.id,
                attachmentId: uploadRecord.attachmentRowId,
                isFullsize: uploadRecord.isFullsize
            )
            let source = observer.source

            let prevByteCount = activeUploadByteCounts[uploadId] ?? 0
            source.incrementCompletedUnitCount(by: completedByteCount - prevByteCount)
            activeUploadByteCounts[uploadId] = completedByteCount

            if completedByteCount >= totalByteCount {
                recentlyCompletedUploads.set(key: uploadId, value: ())
            }
        }
    }

    public func removeObserver(_ id: UUID) {
        observers.removeAll(where: { $0.id == id })
    }

    fileprivate struct UploadQueueSnapshot {
        let totalByteCount: UInt64
        // We want to ignore updates from uploads that were scheduled after
        // we started observing. Take advantage of sequential row ids by
        // ignoring updates from ids that came after initial setup.
        let maxRowId: QueuedBackupAttachmentUpload.IDType?
    }

    private nonisolated func computeRemainingUnuploadedByteCount() throws -> UploadQueueSnapshot {
        return try db.read { tx in
            var totalByteCount: UInt64 = 0
            var maxRowId: Int64?

            let cursor = try QueuedBackupAttachmentUpload
                .fetchCursor(tx.database)

            while let uploadRecord = try cursor.next() {
                totalByteCount += UInt64(uploadRecord.estimatedByteCount)
                if let existingMaxRowId = maxRowId {
                    maxRowId = max(existingMaxRowId, uploadRecord.id!)
                } else {
                    maxRowId = uploadRecord.id
                }
            }

            return UploadQueueSnapshot(totalByteCount: totalByteCount, maxRowId: maxRowId)
        }
    }
}

extension QueuedBackupAttachmentUpload: TableRecord {
    static let attachment = belongsTo(
        Attachment.Record.self,
        using: ForeignKey([QueuedBackupAttachmentUpload.CodingKeys.attachmentRowId.rawValue])
    )
}

#if TESTABLE_BUILD

open class BackuAttachmentUploadProgressMock: BackupAttachmentUploadProgress {

    init() {}

    open func addObserver(
        _ block: @escaping (OWSProgress) -> Void
    ) async throws -> BackupAttachmentUploadProgressObserver {
        let sink = OWSProgress.createSink(block)
        let source = await sink.addSource(withLabel: "", unitCount: 100)
        return BackupAttachmentUploadProgressObserver(
            queueSnapshot: .init(
                totalByteCount: 100,
                maxRowId: nil
            ),
            sink: sink,
            source: source,
            progress: nil
        )
    }

    open func removeObserver(_ observer: Observer) async {
        // Do nothing
    }

    open func removeObserver(_ id: UUID) async {
        // Do nothing
    }

    open func willBeginUploadingAttachment(
        uploadRecord: QueuedBackupAttachmentUpload
    ) async -> any OWSProgressSink {
        OWSProgress.createSink({ _ in })
    }

    open func didFinishUploadOfAttachment(
        uploadRecord: QueuedBackupAttachmentUpload
    ) async {
        // Do nothing
    }

    open func didEmptyUploadQueue() async {
        // Do nothing
    }
}

#endif
