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
        progress: BackupAttachmentUploadProgress?,
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
    func willBeginUploadingFullsizeAttachment(
        uploadRecord: QueuedBackupAttachmentUpload,
    ) async -> OWSProgressSink

    /// Stopgap to inform that an attachment finished uploading.
    /// There are a couple edge cases (e.g. already uploaded) that result in uploads
    /// finishing without reporting any progress updates. This method ensures we always mark
    /// attachments as finished in all cases.
    func didFinishUploadOfFullsizeAttachment(
        uploadRecord: QueuedBackupAttachmentUpload,
    ) async

    /// Called when there are no more enqueued uploads.
    /// As a final stopgap, in case we missed some bytes and counting got out of sync,
    /// this should fully advance the uploaded byte count to the total byte count.
    func didEmptyFullsizeUploadQueue() async

    /// Called when the BackupPlan changes, allowing us to reset progress-related
    /// state.
    func backupPlanDidChange(
        oldBackupPlan: BackupPlan,
        newBackupPlan: BackupPlan,
        tx: DBWriteTransaction,
    )
}

public actor BackupAttachmentUploadProgressImpl: BackupAttachmentUploadProgress {

    // MARK: - Public API

    public func addObserver(_ block: @escaping (OWSProgress) -> Void) async throws -> Observer {
        let queueSnapshot = try self.computeRemainingUnuploadedByteCount()
        let sink = OWSProgress.createSink(block)
        let source = await sink.addSource(withLabel: "", unitCount: queueSnapshot.totalByteCount)
        source.incrementCompletedUnitCount(by: queueSnapshot.completedByteCount)
        let observer = Observer(
            queueSnapshot: queueSnapshot,
            sink: sink,
            source: source,
            progress: self,
        )
        observers.append(observer)
        return observer
    }

    public func removeObserver(_ observer: Observer) {
        self.removeObserver(observer.id)
    }

    // MARK: - BackupAttachmentUploadManager API

    public func willBeginUploadingFullsizeAttachment(
        uploadRecord: QueuedBackupAttachmentUpload,
    ) async -> OWSProgressSink {
        guard uploadRecord.isFullsize else {
            owsFailDebug("Attempting to count thumbnail upload!")
            return OWSProgress.createSink({ _ in })
        }
        let sink = OWSProgress.createSink { [weak self] progress in
            Task {
                await self?.didUpdateProgressForActiveUpload(
                    uploadRecord: uploadRecord,
                    completedByteCount: progress.completedUnitCount,
                    totalByteCount: progress.totalUnitCount,
                )
            }
        }
        return sink
    }

    public func didFinishUploadOfFullsizeAttachment(
        uploadRecord: QueuedBackupAttachmentUpload,
    ) {
        guard uploadRecord.isFullsize else {
            owsFailDebug("Attempting to count thumbnail upload!")
            return
        }
        didUpdateProgressForActiveUpload(
            uploadRecord: uploadRecord,
            completedByteCount: UInt64(uploadRecord.estimatedByteCount),
            totalByteCount: UInt64(uploadRecord.estimatedByteCount),
        )
    }

    public func didEmptyFullsizeUploadQueue() async {
        activeUploadCompletedByteCounts.keys.forEach {
            recentlyCompletedUploads.set(key: $0, value: ())
        }
        activeUploadCompletedByteCounts = [:]
        activeUploadTotalByteCounts = [:]
        observers.cullExpired()
        observers.elements.forEach { observer in
            let source = observer.source
            if source.totalUnitCount > 0, source.totalUnitCount > source.completedUnitCount {
                source.incrementCompletedUnitCount(by: source.totalUnitCount - source.completedUnitCount)
            }
        }
    }

    public nonisolated func backupPlanDidChange(
        oldBackupPlan: BackupPlan,
        newBackupPlan: BackupPlan,
        tx: DBWriteTransaction,
    ) {
        if oldBackupPlan.isPaidPlan() == newBackupPlan.isPaidPlan() {
            // If paid-plan status isn't changing then we're not starting new
            // uploads or stopping ongoing ones, so we can bail early.
            return
        }

        let maxAttachmentRowId: Attachment.IDType = computeMaxAttachmentRowId(
            currentBackupPlan: newBackupPlan,
            tx: tx,
        )

        kvStore.writeValue(
            maxAttachmentRowId,
            forKey: StoreKeys.maxAttachmentRowId,
            tx: tx,
        )
    }

    // MARK: - Init

    private enum StoreKeys {
        static let maxAttachmentRowId: String = "maxAttachmentRowId"
    }

    private nonisolated let attachmentStore: AttachmentStore
    private nonisolated let backupSettingsStore: BackupSettingsStore
    private nonisolated let db: DB
    private nonisolated let kvStore: NewKeyValueStore

    init(
        attachmentStore: AttachmentStore,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
    ) {
        self.attachmentStore = attachmentStore
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.kvStore = NewKeyValueStore(collection: "BackupAttachmentUploadProgress")
    }

    // MARK: -

    private var observers = WeakArray<Observer>()

    private struct PerObserverUploadId: Hashable {
        let observerId: UUID
        let attachmentId: Attachment.IDType
    }

    /// Currently active uploads for which we update progress byte-by-byte.
    private var activeUploadCompletedByteCounts = [PerObserverUploadId: UInt64]()
    private var activeUploadTotalByteCounts = [PerObserverUploadId: UInt64]()
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
        totalByteCount totalByteCountInput: UInt64,
    ) {
        guard
            totalByteCountInput != 0
        else {
            return
        }

        observers.elements.forEach { observer in
            guard
                observer.queueSnapshot.maxAttachmentRowId >= uploadRecord.attachmentRowId
            else {
                return
            }
            let uploadId = PerObserverUploadId(
                observerId: observer.id,
                attachmentId: uploadRecord.attachmentRowId,
            )
            let source = observer.source

            let prevCompletedByteCount = activeUploadCompletedByteCounts[uploadId] ?? 0
            let totalByteCount = activeUploadTotalByteCounts[uploadId] ?? totalByteCountInput
            activeUploadTotalByteCounts[uploadId] = totalByteCount
            if completedByteCount >= totalByteCountInput {
                // If the caller's intent is to complete to 100%, complete
                // to 100% even if the caller got the unit count wrong
                // (e.g. because it was only doing an estimated byte count).
                if prevCompletedByteCount < totalByteCount {
                    source.incrementCompletedUnitCount(by: totalByteCount - prevCompletedByteCount)
                    activeUploadCompletedByteCounts[uploadId] = totalByteCount
                    recentlyCompletedUploads.set(key: uploadId, value: ())
                }
            } else if completedByteCount > prevCompletedByteCount {
                source.incrementCompletedUnitCount(by: completedByteCount - prevCompletedByteCount)
                activeUploadCompletedByteCounts[uploadId] = completedByteCount
            } else {
                // The completed byte count is less than the previous completed
                // byte count, which is strange but not impossible given that we
                // have both estimated and actual byte counts flowing through
                // here. Nothing to increment.
            }
        }
    }

    public func removeObserver(_ id: UUID) {
        observers.removeAll(where: { $0.id == id })
    }

    fileprivate struct UploadQueueSnapshot {
        let totalByteCount: UInt64
        let completedByteCount: UInt64
        // We want to ignore updates from uploads for attachments that were
        // inserted after specific points. Take advantage of sequential row ids.
        let maxAttachmentRowId: Attachment.IDType
    }

    private nonisolated func computeMaxAttachmentRowId(
        currentBackupPlan: BackupPlan,
        tx: DBReadTransaction,
    ) -> Attachment.IDType {
        guard currentBackupPlan.isPaidPlan() else {
            // We don't care about upload progress on non-paid plans.
            return 0
        }

        do {
            return try attachmentStore.fetchMaxRowId(tx: tx) ?? 0
        } catch {
            owsFailDebug("Failed to get max attachment row ID! \(error)")
            return 0
        }
    }

    private nonisolated func computeRemainingUnuploadedByteCount() throws -> UploadQueueSnapshot {
        return try db.read { tx in
            let maxAttachmentRowId: Attachment.IDType = {
                if
                    let persistedValue = kvStore.fetchValue(
                        Attachment.IDType.self,
                        forKey: StoreKeys.maxAttachmentRowId,
                        tx: tx,
                    )
                {
                    return persistedValue
                }

                // It's possible we've never persisted a value, so fall back to
                // the "live" value if necessary.
                return computeMaxAttachmentRowId(
                    currentBackupPlan: backupSettingsStore.backupPlan(tx: tx),
                    tx: tx,
                )
            }()

            func fetchBackupAttachmentUploadCursor(
                state: QueuedBackupAttachmentUpload.State,
            ) throws -> RecordCursor<QueuedBackupAttachmentUpload> {
                return try QueuedBackupAttachmentUpload
                    .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.isFullsize) == true)
                    .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.state) == state.rawValue)
                    .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.attachmentRowId) <= maxAttachmentRowId)
                    .fetchCursor(tx.database)
            }

            var remainingByteCount: UInt64 = 0
            let remainingCursor = try fetchBackupAttachmentUploadCursor(
                state: .ready,
            )
            while let uploadRecord = try remainingCursor.next() {
                remainingByteCount += UInt64(uploadRecord.estimatedByteCount)
            }

            var completedByteCount: UInt64 = 0
            let completedCursor = try fetchBackupAttachmentUploadCursor(
                state: .done,
            )
            while let uploadRecord = try completedCursor.next() {
                completedByteCount += UInt64(uploadRecord.estimatedByteCount)
            }

            return UploadQueueSnapshot(
                totalByteCount: remainingByteCount + completedByteCount,
                completedByteCount: completedByteCount,
                maxAttachmentRowId: maxAttachmentRowId,
            )
        }
    }
}

// MARK: -

private extension BackupPlan {
    func isPaidPlan() -> Bool {
        switch self {
        case .disabled, .disabling, .free: false
        case .paid, .paidExpiringSoon, .paidAsTester: true
        }
    }
}

// MARK: -

#if TESTABLE_BUILD

open class BackupAttachmentUploadProgressMock: BackupAttachmentUploadProgress {

    init() {}

    open func addObserver(
        _ block: @escaping (OWSProgress) -> Void,
    ) async throws -> BackupAttachmentUploadProgressObserver {
        let sink = OWSProgress.createSink(block)
        let source = await sink.addSource(withLabel: "", unitCount: 100)
        return BackupAttachmentUploadProgressObserver(
            queueSnapshot: .init(
                totalByteCount: 100,
                completedByteCount: 0,
                maxAttachmentRowId: 0,
            ),
            sink: sink,
            source: source,
            progress: nil,
        )
    }

    open func removeObserver(_ observer: Observer) async {
        // Do nothing
    }

    open func removeObserver(_ id: UUID) async {
        // Do nothing
    }

    open func willBeginUploadingFullsizeAttachment(
        uploadRecord: QueuedBackupAttachmentUpload,
    ) async -> any OWSProgressSink {
        OWSProgress.createSink({ _ in })
    }

    open func didFinishUploadOfFullsizeAttachment(
        uploadRecord: QueuedBackupAttachmentUpload,
    ) async {
        // Do nothing
    }

    open func didEmptyFullsizeUploadQueue() async {
        // Do nothing
    }

    open func backupPlanDidChange(
        oldBackupPlan: BackupPlan,
        newBackupPlan: BackupPlan,
        tx: DBWriteTransaction,
    ) {
        // Do nothing
    }
}

#endif
