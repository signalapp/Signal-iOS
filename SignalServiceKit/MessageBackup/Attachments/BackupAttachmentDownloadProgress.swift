//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

public actor BackupAttachmentDownloadProgress {

    // MARK: - Public API

    public class Observer {
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

    /// Begin observing progress of all backup attachment downloads.
    /// The observer will immediately be provided the current progress if any, and then updated with future progress state.
    public func addObserver(_ block: @escaping (OWSProgress) -> Void) -> Observer {
        let observer = Observer(block: block)
        latestProgress.map(block)
        observers.append(observer)
        return observer
    }

    public func removeObserver(_ observer: Observer) {
        self.removeObserver(observer.id)
    }

    // MARK: - BackupAttachmentDownloadManager API

    /// Compute total pending bytes to download, and set up observation for attachments to be downloaded.
    internal func beginObserving() async throws {
        await initializationTask.value

        let pendingByteCount: UInt64 = try computeRemainingUndownloadedByteCount()

        let totalByteCount: UInt64 = db.read { tx in
            backupAttachmentDownloadStore.getTotalPendingDownloadByteCount(tx: tx) ?? pendingByteCount
        }

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
    internal func willBeginDownloadingAttachment(withId id: Attachment.IDType) async -> OWSProgressSink {
        let sink = OWSProgress.createSink { [weak self] progress in
            Task { await self?.didUpdateProgressForActiveDownload(
                id: id,
                completedByteCount: progress.completedUnitCount,
                totalByteCount: progress.totalUnitCount
            )
            }
        }
        return sink
    }

    /// Stopgap to inform that an attachment finished downloading.
    /// There are a couple edge cases (e.g. we already have a stream) that result in downloads
    /// finishing without reporting any progress updates. This method ensures we always mark
    /// attachments as finished in all cases.
    internal func didFinishDownloadOfAttachment(
        withId id: Attachment.IDType,
        byteCount: UInt64
    ) {
        didUpdateProgressForActiveDownload(
            id: id,
            completedByteCount: byteCount,
            totalByteCount: byteCount
        )
    }

    /// Called when there are no more enqueued downloads.
    /// As a final stopgap, in case we missed some bytes and counting got out of sync,
    /// this should fully advance the downloaded byte count to the total byte count.
    internal func didEmptyDownloadQueue() async {
        activeDownloadByteCounts.keys.forEach {
            recentlyCompletedDownloads.set(key: $0, value: ())
        }
        activeDownloadByteCounts = [:]
        if let source {
            source.incrementCompletedUnitCount(by: source.totalUnitCount - source.completedUnitCount)
            await self.updateCache()
        }
    }

    // MARK: - Private

    private nonisolated let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private nonisolated let dateProvider: DateProvider
    private nonisolated let db: DB
    private nonisolated let remoteConfigProvider: RemoteConfigProvider

    init(
        appReadiness: AppReadiness,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        dateProvider: @escaping DateProvider,
        db: DB,
        remoteConfigProvider: RemoteConfigProvider
    ) {
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.dateProvider = dateProvider
        self.db = db
        self.remoteConfigProvider = remoteConfigProvider

        var selfRef: BackupAttachmentDownloadProgress?
        self.initializationTask = Task {
            await withCheckedContinuation { continuation in
                appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
                    Task {
                        await selfRef?.initializeProgress()
                        continuation.resume()
                    }
                }
            }
        }
        selfRef = self
    }

    private let initializationTask: Task<Void, Never>

    private func initializeProgress() {
        // Initialize the `latestProgress` value using the on-disk cached values.
        // Later we will (expensively) recompute the remaining byte count.
        let (totalByteCount, remainingByteCount) = db.read { tx in
            return (
                backupAttachmentDownloadStore.getTotalPendingDownloadByteCount(tx: tx),
                backupAttachmentDownloadStore.getCachedRemainingPendingDownloadByteCount(tx: tx)
            )
        }
        if let totalByteCount {
            self.latestProgress = OWSProgress(
                completedUnitCount: totalByteCount - (remainingByteCount ?? totalByteCount),
                totalUnitCount: totalByteCount,
                sourceProgresses: [:]
            )
        }
    }

    private var observers = WeakArray<Observer>()

    /// Initialized to cached values (if available) and updated as
    /// downloads increment the completed byte count.
    private var latestProgress: OWSProgress?

    /// Set up in `beginObserving`
    private var sink: OWSProgressSink?
    private var source: OWSProgressSource?

    /// Currently active downloads for which we update progress byte-by-byte.
    private var activeDownloadByteCounts = [Attachment.IDType: UInt64]()
    /// There is a race between receiving the final OWSProgress update for a given attachment
    /// and being told the attachment finished downloading by BackupAttachmentDownloadManager.
    /// To resolve this race, track recently completed downloads so we know not to double count.
    /// There could be tens of thousands of attachments, so to minimize memory usage only keep
    /// an LRUCache. In practice that will catch all races. Even if it doesn't, the downside
    /// is we misreport progress until we hit 100%, big whoop.
    private var recentlyCompletedDownloads = LRUCache<Attachment.IDType, Void>(maxSize: 100)

    private func didUpdateProgressForActiveDownload(
        id: Attachment.IDType,
        completedByteCount: UInt64,
        totalByteCount: UInt64
    ) {
        guard
            totalByteCount != 0,
            recentlyCompletedDownloads.get(key: id) == nil
        else {
            return
        }
        let prevByteCount = activeDownloadByteCounts[id] ?? 0
        let diff = completedByteCount - prevByteCount
        owsAssertDebug(self.source != nil, "Updating progress before setting up observation!")
        if diff > 0 {
            self.source?.incrementCompletedUnitCount(by: diff)
        }
        if completedByteCount >= totalByteCount {
            recentlyCompletedDownloads.set(key: id, value: ())
            // When some download completes, update the cache.
            Task { [weak self] in
                await self?.updateCache()
            }
        } else {
            activeDownloadByteCounts[id] = completedByteCount
        }
    }

    private func updateObservers(_ progress: OWSProgress) {
        self.latestProgress = progress
        observers.elements.forEach { $0.block(progress) }
    }

    func removeObserver(_ id: UUID) {
        observers.removeAll(where: { $0.id == id })
    }

    private nonisolated func computeRemainingUndownloadedByteCount() throws -> UInt64 {
        let remoteConfig = remoteConfigProvider.currentConfig()
        let now = dateProvider()

        return try db.read { tx in
            let shouldStoreAllMediaLocally = backupAttachmentDownloadStore.getShouldStoreAllMediaLocally(tx: tx)

            var totalByteCount: UInt64 = 0

            struct JoinedRecord: Decodable, FetchableRecord {
                var QueuedBackupAttachmentDownload: QueuedBackupAttachmentDownload
                var Attachment: Attachment.Record
            }

            let cursor = try QueuedBackupAttachmentDownload
                .including(required: QueuedBackupAttachmentDownload.attachment.self)
                .asRequest(of: JoinedRecord.self)
                .fetchCursor(tx.database)

            while let joinedRecord = try cursor.next() {
                guard let attachment = try? Attachment(record: joinedRecord.Attachment) else {
                    continue
                }
                let eligibility = BackupAttachmentDownloadEligibility.forAttachment(
                    attachment,
                    attachmentTimestamp: joinedRecord.QueuedBackupAttachmentDownload.timestamp,
                    now: now,
                    shouldStoreAllMediaLocally: shouldStoreAllMediaLocally,
                    remoteConfig: remoteConfig
                )
                if
                    eligibility.canDownloadMediaTierFullsize,
                    let byteCount = attachment.mediaTierInfo?.unencryptedByteCount
                {
                    totalByteCount += UInt64(byteCount)
                } else if
                    eligibility.canDownloadTransitTierFullsize,
                    let byteCount = attachment.transitTierInfo?.unencryptedByteCount
                {
                    totalByteCount += UInt64(byteCount)
                }
                // We don't count thumbnail downloads towards the total
                // download count we track the progress of.
            }
            return totalByteCount
        }
    }

    private nonisolated func updateCache() async {
        guard
            // Ensure we've started observing
            await self.sink != nil,
            let latestProgress = await self.latestProgress
        else {
            return
        }
        let pendingByteCount = latestProgress.totalUnitCount - latestProgress.completedUnitCount
        await db.awaitableWrite { tx in
            backupAttachmentDownloadStore.setCachedRemainingPendingDownloadByteCount(
                pendingByteCount,
                tx: tx
            )
        }
    }
}

extension QueuedBackupAttachmentDownload: TableRecord {
    static let attachment = belongsTo(
        Attachment.Record.self,
        using: ForeignKey([QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId.rawValue])
    )
}
