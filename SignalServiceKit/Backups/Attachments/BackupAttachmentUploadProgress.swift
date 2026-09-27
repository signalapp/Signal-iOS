//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

public class BackupAttachmentUploadProgressObserver {
    fileprivate let queueSnapshot: BackupAttachmentUploadProgressImpl.UploadQueueSnapshot
    fileprivate let sink: OWSProgressSink
    fileprivate let source: OWSProgressSource
    fileprivate let id: UUID = UUID()

    fileprivate init(
        queueSnapshot: BackupAttachmentUploadProgressImpl.UploadQueueSnapshot,
        sink: OWSProgressSink,
        source: OWSProgressSource,
    ) {
        self.queueSnapshot = queueSnapshot
        self.sink = sink
        self.source = source
    }
}

/// Tracks and reports the progress of the "initial Backup attachment upload",
/// or the one-time upload of historical attachments performed when paid-tier
/// Backups are enabled.
///
/// If you have paid-tier Backups enabled, new attachments are backed up to the
/// media tier CDN as they are sent/received. However, when you first enable
/// paid-tier Backups you must also back up all of your historical attachments.
///
/// While this type tracks the progress of all Backup attachment uploads, it
/// filters internally to only report the progress of attachments included in
/// that "initial" upload.
///
/// - Note
/// Only considers fullsize attachments; ignores thumbnails.
///
/// - SeeAlso
/// `BackupAttachmentUploadTracker`
public protocol BackupAttachmentUploadProgress: AnyObject {

    typealias Observer = BackupAttachmentUploadProgressObserver

    /// Add an observer, calling the given `block` with progress updates.
    /// - Warning
    /// The returned observer must be caller-retained. Be careful of retain
    /// cycles, as the observer retains the passed block.
    func addObserver(_ block: @escaping (OWSProgress) -> Void) -> Observer

    func removeObserver(_ observer: Observer)

    func removeObserver(_ id: UUID)

    func didUpdateProgressForFullsizeAttachment(
        uploadRecord: QueuedBackupAttachmentUpload,
        completedByteCount: UInt64,
        totalByteCount: UInt64,
    )

    /// Called when there are no more enqueued uploads.
    /// As a final stopgap, in case we missed some bytes and counting got out of sync,
    /// this should fully advance the uploaded byte count to the total byte count.
    func didEmptyFullsizeUploadQueue()

    /// Called when the BackupPlan changes, allowing us to reset progress-related
    /// state.
    func backupPlanDidChange(
        oldBackupPlan: BackupPlan,
        newBackupPlan: BackupPlan,
        tx: DBWriteTransaction,
    )
}

public class BackupAttachmentUploadProgressImpl: BackupAttachmentUploadProgress {

    // MARK: - Public API

    public func addObserver(_ block: @escaping (OWSProgress) -> Void) -> Observer {
        let queueSnapshot = self.computeRemainingUnuploadedByteCount()
        let sink = OWSProgress.createSink(block)
        let source = sink.addSource(withLabel: "", unitCount: queueSnapshot.totalByteCount)
        source.incrementCompletedUnitCount(by: queueSnapshot.completedByteCount)
        let observer = Observer(
            queueSnapshot: queueSnapshot,
            sink: sink,
            source: source,
        )
        state.update { _state in
            _state.observers.append(observer)
        }
        return observer
    }

    public func removeObserver(_ observer: Observer) {
        self.removeObserver(observer.id)
    }

    // MARK: - BackupAttachmentUploadManager API

    public func didEmptyFullsizeUploadQueue() {
        state.update { _state in
            _state.activeUploadCompletedByteCounts = [:]
            _state.activeUploadTotalByteCounts = [:]
            _state.observers.cullExpired()
            _state.observers.elements.forEach { observer in
                let source = observer.source
                if source.totalUnitCount > 0, source.totalUnitCount > source.completedUnitCount {
                    source.incrementCompletedUnitCount(by: source.totalUnitCount - source.completedUnitCount)
                }
            }
        }
    }

    public func backupPlanDidChange(
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

    private let attachmentStore: AttachmentStore
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let kvStore: NewKeyValueStore

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

    private struct PerObserverUploadId: Hashable {
        let observerId: UUID
        let attachmentId: Attachment.IDType
    }

    private struct State {
        var observers = WeakArray<BackupAttachmentUploadProgressObserver>()

        /// Currently active uploads for which we update progress byte-by-byte.
        var activeUploadCompletedByteCounts = [PerObserverUploadId: UInt64]()
        var activeUploadTotalByteCounts = [PerObserverUploadId: UInt64]()
    }

    private let state = AtomicValue<State>(State(), lock: .init())

    public func didUpdateProgressForFullsizeAttachment(
        uploadRecord: QueuedBackupAttachmentUpload,
        completedByteCount: UInt64,
        totalByteCount totalByteCountInput: UInt64,
    ) {
        guard totalByteCountInput != 0 else {
            return
        }

        state.update { _state in
            _didUpdateProgressForFullsizeAttachment(
                state: &_state,
                uploadRecord: uploadRecord,
                completedByteCount: completedByteCount,
                totalByteCount: totalByteCountInput,
            )
        }
    }

    private func _didUpdateProgressForFullsizeAttachment(
        state: inout State,
        uploadRecord: QueuedBackupAttachmentUpload,
        completedByteCount: UInt64,
        totalByteCount totalByteCountInput: UInt64,
    ) {
        for observer in state.observers.elements {
            guard
                observer.queueSnapshot.maxAttachmentRowId >= uploadRecord.attachmentRowId
            else {
                continue
            }
            let uploadId = PerObserverUploadId(
                observerId: observer.id,
                attachmentId: uploadRecord.attachmentRowId,
            )
            let source = observer.source

            let prevCompletedByteCount = state.activeUploadCompletedByteCounts[uploadId] ?? 0
            let totalByteCount = state.activeUploadTotalByteCounts[uploadId] ?? totalByteCountInput
            state.activeUploadTotalByteCounts[uploadId] = totalByteCount

            if completedByteCount >= totalByteCountInput {
                // If the caller's intent is to complete to 100%, complete
                // to 100% even if the caller got the unit count wrong
                // (e.g. because it was only doing an estimated byte count).
                if prevCompletedByteCount < totalByteCount {
                    source.incrementCompletedUnitCount(by: totalByteCount - prevCompletedByteCount)
                    state.activeUploadCompletedByteCounts[uploadId] = totalByteCount
                }
            } else if completedByteCount > prevCompletedByteCount {
                source.incrementCompletedUnitCount(by: completedByteCount - prevCompletedByteCount)
                state.activeUploadCompletedByteCounts[uploadId] = completedByteCount
            } else {
                // The completed byte count is less than the previous completed
                // byte count, which is strange but not impossible given that we
                // have both estimated and actual byte counts flowing through
                // here. Nothing to increment.
            }
        }
    }

    public func removeObserver(_ id: UUID) {
        state.update {
            $0.observers.removeAll(where: { $0.id == id })
        }
    }

    fileprivate struct UploadQueueSnapshot {
        let totalByteCount: UInt64
        let completedByteCount: UInt64
        // We want to ignore updates from uploads for attachments that were
        // inserted after specific points. Take advantage of sequential row ids.
        let maxAttachmentRowId: Attachment.IDType
    }

    private func computeMaxAttachmentRowId(
        currentBackupPlan: BackupPlan,
        tx: DBReadTransaction,
    ) -> Attachment.IDType {
        guard currentBackupPlan.isPaidPlan() else {
            // We don't care about upload progress on non-paid plans.
            return 0
        }

        return attachmentStore.fetchMaxRowId(tx: tx) ?? 0
    }

    private func computeRemainingUnuploadedByteCount() -> UploadQueueSnapshot {
        return db.read { tx in
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
            ) -> FailIfThrowsRecordCursor<QueuedBackupAttachmentUpload> {
                let query = QueuedBackupAttachmentUpload
                    .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.isFullsize) == true)
                    .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.state) == state.rawValue)
                    .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.attachmentRowId) <= maxAttachmentRowId)

                return FailIfThrowsRecordCursor {
                    try query.fetchCursor(tx.database)
                }
            }

            var remainingByteCount: UInt64 = 0
            var remainingCursor = fetchBackupAttachmentUploadCursor(
                state: .ready,
            )
            while let uploadRecord = remainingCursor.next() {
                remainingByteCount += UInt64(uploadRecord.estimatedByteCount)
            }

            var completedByteCount: UInt64 = 0
            var completedCursor = fetchBackupAttachmentUploadCursor(
                state: .done,
            )
            while let uploadRecord = completedCursor.next() {
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
    var progressMock: OWSProgress {
        didSet {
            mockObserverBlocks.get().forEach { $0(progressMock) }
        }
    }

    private let mockObserverBlocks: AtomicValue<[(OWSProgress) -> Void]>

    init(
        initialCompleted: UInt64,
        total: UInt64,
    ) {
        self.progressMock = OWSProgress(
            completedUnitCount: initialCompleted,
            totalUnitCount: total,
        )
        self.mockObserverBlocks = AtomicValue([], lock: .init())
    }

    open func addObserver(
        _ block: @escaping (OWSProgress) -> Void,
    ) -> BackupAttachmentUploadProgressObserver {
        mockObserverBlocks.update { $0.append(block) }

        let sink = OWSProgress.createSink(block)
        let source = sink.addSource(withLabel: "", unitCount: progressMock.totalUnitCount)
        return BackupAttachmentUploadProgressObserver(
            queueSnapshot: BackupAttachmentUploadProgressImpl.UploadQueueSnapshot(
                totalByteCount: progressMock.totalUnitCount,
                completedByteCount: progressMock.completedUnitCount,
                maxAttachmentRowId: 0,
            ),
            sink: sink,
            source: source,
        )
    }

    open func removeObserver(_ observer: Observer) {
        // Do nothing
    }

    open func removeObserver(_ id: UUID) {
        // Do nothing
    }

    open func didUpdateProgressForFullsizeAttachment(
        uploadRecord: QueuedBackupAttachmentUpload,
        completedByteCount: UInt64,
        totalByteCount: UInt64,
    ) {
        // Do nothing
    }

    open func didEmptyFullsizeUploadQueue() {
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
