//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

public class BackupAttachmentDownloadProgressObserver {
    private weak var progress: BackupAttachmentDownloadProgress?
    fileprivate let id: UUID = UUID()
    fileprivate let block: (OWSProgress) -> Void

    fileprivate init(progress: BackupAttachmentDownloadProgress? = nil, block: @escaping (OWSProgress) -> Void) {
        self.progress = progress
        self.block = block
    }

    deinit {
        Task { [weak progress, id] in
            await progress?.removeObserver(id)
        }
    }
}

/// Tracks and reports progress for backup (media tier) attachment downloads.
///
/// When we restore a backup (or disable backups or other state changes that trigger bulk rescheduling
/// of media tier downloads) we compute and store the total bytes to download. This class counts
/// up to that number until all downloads finish; this ensures we show a stable total even as we make
/// partial progress.
public protocol BackupAttachmentDownloadProgress: AnyObject {

    typealias Observer = BackupAttachmentDownloadProgressObserver

    /// Begin observing progress of all backup attachment downloads.
    /// The observer will immediately be provided the current progress if any, and then updated with future progress state.
    func addObserver(_ block: @escaping (OWSProgress) -> Void) async -> Observer

    func removeObserver(_ observer: Observer) async

    func removeObserver(_ id: UUID) async

    /// Compute total pending bytes to download, and set up observation for attachments to be downloaded.
    func beginObserving() async throws

    /// Create an OWSProgressSink for a single attachment to be downloaded.
    /// Should be called prior to downloading any backup attachment.
    func willBeginDownloadingFullsizeAttachment(
        withId id: Attachment.IDType,
    ) async -> OWSProgressSink

    /// Stopgap to inform that an attachment finished downloading.
    /// There are a couple edge cases (e.g. we already have a stream) that result in downloads
    /// finishing without reporting any progress updates. This method ensures we always mark
    /// attachments as finished in all cases.
    func didFinishDownloadOfFullsizeAttachment(
        withId id: Attachment.IDType,
        byteCount: UInt64,
    ) async

    /// Called when there are no more enqueued downloads.
    /// As a final stopgap, in case we missed some bytes and counting got out of sync,
    /// this should fully advance the downloaded byte count to the total byte count.
    func didEmptyFullsizeDownloadQueue() async
}

public actor BackupAttachmentDownloadProgressImpl: BackupAttachmentDownloadProgress {

    // MARK: - Public API

    public func addObserver(_ block: @escaping (OWSProgress) -> Void) async -> Observer {
        let observer = Observer(block: block)
        if let latestProgress {
            block(latestProgress)
        } else {
            await initializeProgress()
            latestProgress.map(block)
        }
        observers.append(observer)
        return observer
    }

    public func removeObserver(_ observer: Observer) {
        self.removeObserver(observer.id)
    }

    // MARK: - BackupAttachmentDownloadManager API

    public func beginObserving() async throws {
        await initializeProgress()

        let pendingByteCount: UInt64
        let finishedByteCount: UInt64
        (pendingByteCount, finishedByteCount) = db.read { tx -> (UInt64, UInt64) in
            return (
                backupAttachmentDownloadStore.computeEstimatedRemainingFullsizeByteCount(tx: tx) ?? 0,
                backupAttachmentDownloadStore.computeEstimatedFinishedFullsizeByteCount(tx: tx) ?? 0,
            )
        }
        let totalByteCount = pendingByteCount + finishedByteCount

        if pendingByteCount == 0 {
            updateObservers(OWSProgress(
                completedUnitCount: totalByteCount,
                totalUnitCount: totalByteCount,
            ))
            return
        }

        if totalByteCount == 0 {
            return
        }

        didEmptyFullsizeQueue = false

        let sink = OWSProgress.createSink({ [weak self] progress in
            await self?.updateObservers(progress)
        })

        let source = await sink.addSource(withLabel: "", unitCount: totalByteCount)
        if totalByteCount > pendingByteCount {
            source.incrementCompletedUnitCount(by: totalByteCount - pendingByteCount)
        }
        self.sink = sink
        self.source = source
    }

    /// Create an OWSProgressSink for a single attachment to be downloaded.
    /// Should be called prior to downloading any backup attachment.
    public func willBeginDownloadingFullsizeAttachment(
        withId id: Attachment.IDType,
    ) async -> OWSProgressSink {
        let sink = OWSProgress.createSink { [weak self] progress in
            Task { await self?.didUpdateProgressForActiveDownload(
                id: .init(atachmentId: id),
                completedByteCount: progress.completedUnitCount,
                totalByteCount: progress.totalUnitCount,
            )
            }
        }
        return sink
    }

    public func didFinishDownloadOfFullsizeAttachment(
        withId id: Attachment.IDType,
        byteCount: UInt64,
    ) {
        didUpdateProgressForActiveDownload(
            id: .init(atachmentId: id),
            completedByteCount: byteCount,
            totalByteCount: byteCount,
        )
    }

    public func didEmptyFullsizeDownloadQueue() async {
        didEmptyFullsizeQueue = true

        activeDownloadByteCounts = [:]
        if let source {
            if source.totalUnitCount > 0, source.totalUnitCount > source.completedUnitCount {
                source.incrementCompletedUnitCount(by: source.totalUnitCount - source.completedUnitCount)
            }
        }
    }

    // MARK: - Private

    private nonisolated let appContext: AppContext
    private nonisolated let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private nonisolated let backupSettingsStore: BackupSettingsStore
    private nonisolated let dateProvider: DateProvider
    private nonisolated let db: DB
    private nonisolated let remoteConfigProvider: RemoteConfigProvider
    private var didEmptyFullsizeQueue: Bool = false

    init(
        appContext: AppContext,
        appReadiness: AppReadiness,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        db: DB,
        remoteConfigProvider: RemoteConfigProvider,
    ) {
        self.appContext = appContext
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.db = db
        self.remoteConfigProvider = remoteConfigProvider

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            Task {
                await self?.initializeProgress()
            }
        }
    }

    private var initializationTask: Task<Void, Never>?

    private func initializeProgress() async {
        guard appContext.isMainApp else { return }
        if let initializationTask {
            await initializationTask.value
            return
        }
        initializationTask = Task { [weak self] in
            await self?._initializeProgress()
        }
    }

    private func _initializeProgress() {
        if latestProgress != nil { return }
        // Initialize the `latestProgress` value using the on-disk cached values.
        // Later we will (expensively) recompute the remaining byte count.
        let pendingByteCount: UInt64
        let finishedByteCount: UInt64
        (pendingByteCount, finishedByteCount) = db.read { tx -> (UInt64, UInt64) in
            return (
                backupAttachmentDownloadStore.computeEstimatedRemainingFullsizeByteCount(tx: tx) ?? 0,
                backupAttachmentDownloadStore.computeEstimatedFinishedFullsizeByteCount(tx: tx) ?? 0,
            )
        }
        let totalByteCount = pendingByteCount + finishedByteCount
        if totalByteCount > 0 {
            updateObservers(OWSProgress(
                completedUnitCount: finishedByteCount,
                totalUnitCount: totalByteCount,
            ))
        }
    }

    private var observers = WeakArray<Observer>()

    /// Initialized to cached values (if available) and updated as
    /// downloads increment the completed byte count.
    private var latestProgress: OWSProgress?

    /// Set up in `beginObserving`
    private var sink: OWSProgressSink?
    private var source: OWSProgressSource?

    private struct DownloadId: Equatable, Hashable {
        let atachmentId: Attachment.IDType
    }

    /// Currently active downloads for which we update progress byte-by-byte.
    private var activeDownloadByteCounts = [DownloadId: UInt64]()

    private func didUpdateProgressForActiveDownload(
        id: DownloadId,
        completedByteCount: UInt64,
        totalByteCount: UInt64,
    ) {
        guard totalByteCount != 0 else {
            return
        }
        let prevByteCount = activeDownloadByteCounts[id] ?? 0
        if let source {
            let diff = min(max(completedByteCount, prevByteCount) - prevByteCount, source.totalUnitCount - source.completedUnitCount)
            owsAssertDebug(self.source != nil, "Updating progress before setting up observation!")
            if diff > 0 {
                self.source?.incrementCompletedUnitCount(by: diff)
            }
        }
        if completedByteCount < totalByteCount {
            activeDownloadByteCounts[id] = completedByteCount
        }
    }

    private func updateObservers(_ progress: OWSProgress) {
        self.latestProgress = progress
        observers.elements.forEach { $0.block(progress) }
    }

    public func removeObserver(_ id: UUID) {
        observers.removeAll(where: { $0.id == id })
    }
}

extension QueuedBackupAttachmentDownload: TableRecord {
    static let attachment = belongsTo(
        Attachment.Record.self,
        using: ForeignKey([QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId.rawValue]),
    )
}

#if TESTABLE_BUILD

open class BackupAttachmentDownloadProgressMock: BackupAttachmentDownloadProgress {

    init() {}

    open func addObserver(
        _ block: @escaping (OWSProgress) -> Void,
    ) async -> BackupAttachmentDownloadProgressObserver {
        return BackupAttachmentDownloadProgressObserver(block: block)
    }

    open func removeObserver(_ observer: Observer) async {
        // Do nothing
    }

    open func removeObserver(_ id: UUID) async {
        // Do nothing
    }

    open func beginObserving() async throws {
        // Do nothing
    }

    open func willBeginDownloadingFullsizeAttachment(
        withId id: Attachment.IDType,
    ) async -> any OWSProgressSink {
        return OWSProgress.createSink({ _ in })
    }

    open func didFinishDownloadOfFullsizeAttachment(
        withId id: Attachment.IDType,
        byteCount: UInt64,
    ) async {
        // Do nothing
    }

    open func didEmptyFullsizeDownloadQueue() async {
        // Do nothing
    }
}

#endif
