//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public class BackupAttachmentDownloadProgressObserver {
    fileprivate let id: UUID = UUID()
    fileprivate let block: (OWSProgress) -> Void

    fileprivate init(block: @escaping (OWSProgress) -> Void) {
        self.block = block
    }
}

/// Tracks and reports progress for backup (media tier) attachment downloads.
///
/// When we restore a backup (or disable backups or other state changes that trigger bulk rescheduling
/// of media tier downloads) we compute and store the total bytes to download. This class counts
/// up to that number until all downloads finish; this ensures we show a stable total even as we make
/// partial progress.
///
/// - SeeAlso `BackupAttachmentDownloadTracker`
public protocol BackupAttachmentDownloadProgress: AnyObject {

    typealias Observer = BackupAttachmentDownloadProgressObserver

    /// Begin observing progress of all backup attachment downloads.
    ///
    /// The observer will be called with the current progress if available, and
    /// updated as progress changes in the future.
    func addObserver(_ block: @escaping (OWSProgress) -> Void) -> Observer

    func removeObserver(_ observer: Observer)

    /// Compute total pending bytes to download, and set up observation for attachments to be downloaded.
    /// - Important
    /// Reads from the database; avoid calling on the main thread.
    func beginObserving()

    /// Create an OWSProgressSink for a single attachment to be downloaded.
    /// Should be called prior to downloading any backup attachment.
    func willBeginDownloadingFullsizeAttachment(
        withId id: Attachment.IDType,
    ) -> OWSProgressSink

    /// Stopgap to inform that an attachment finished downloading.
    /// There are a couple edge cases (e.g. we already have a stream) that result in downloads
    /// finishing without reporting any progress updates. This method ensures we always mark
    /// attachments as finished in all cases.
    func didFinishDownloadOfFullsizeAttachment(
        withId id: Attachment.IDType,
        byteCount: UInt64,
    )

    /// Called when there are no more enqueued downloads.
    /// As a final stopgap, in case we missed some bytes and counting got out of sync,
    /// this should fully advance the downloaded byte count to the total byte count.
    func didEmptyFullsizeDownloadQueue()
}

// MARK: -

class BackupAttachmentDownloadProgressImpl: BackupAttachmentDownloadProgress {

    func addObserver(_ block: @escaping (OWSProgress) -> Void) -> Observer {
        let observer = Observer(block: block)
        let latestProgress = state.update { _state -> OWSProgress? in
            _state.observers.append(observer)
            return _state.latestProgress
        }
        // If we don't have progress yet, the observer will be called back
        // when we do; see `initializeProgress`.
        if let latestProgress {
            block(latestProgress)
        }
        return observer
    }

    func removeObserver(_ observer: Observer) {
        state.update {
            $0.observers.removeAll(where: { $0.id == observer.id })
        }
    }

    func beginObserving() {
        let (pendingByteCount, finishedByteCount) = fetchEstimatedByteCounts()
        let totalByteCount = pendingByteCount + finishedByteCount

        guard pendingByteCount > 0 else {
            // Nothing left to download, so we're already done.
            updateObservers(OWSProgress(
                completedUnitCount: totalByteCount,
                totalUnitCount: totalByteCount,
            ))
            return
        }

        updateObservers(OWSProgress(
            completedUnitCount: finishedByteCount,
            totalUnitCount: totalByteCount,
        ))

        let sink = OWSProgress.createSink { [weak self] progress in
            self?.updateObservers(progress)
        }

        let source = sink.addSource(withLabel: "", unitCount: totalByteCount)
        if finishedByteCount > 0 {
            source.incrementCompletedUnitCount(by: finishedByteCount)
        }
        state.update { _state in
            _state.sink = sink
            _state.source = source
        }
    }

    func willBeginDownloadingFullsizeAttachment(
        withId id: Attachment.IDType,
    ) -> OWSProgressSink {
        return OWSProgress.createSink { [weak self] progress in
            self?.didUpdateProgressForActiveDownload(
                id: id,
                completedByteCount: progress.completedUnitCount,
                totalByteCount: progress.totalUnitCount,
            )
        }
    }

    func didFinishDownloadOfFullsizeAttachment(
        withId id: Attachment.IDType,
        byteCount: UInt64,
    ) {
        didUpdateProgressForActiveDownload(
            id: id,
            completedByteCount: byteCount,
            totalByteCount: byteCount,
        )
    }

    func didEmptyFullsizeDownloadQueue() {
        state.update { _state in
            _state.activeDownloadByteCounts = [:]
            if
                let source = _state.source,
                source.totalUnitCount > 0,
                source.totalUnitCount > source.completedUnitCount
            {
                source.incrementCompletedUnitCount(by: source.totalUnitCount - source.completedUnitCount)
            }
        }
    }

    // MARK: -

    private struct State {
        var observers = WeakArray<BackupAttachmentDownloadProgressObserver>()

        /// Seeded from the queue's estimated byte counts, and updated as
        /// downloads increment the completed byte count.
        var latestProgress: OWSProgress?

        /// Set up in `beginObserving`
        var sink: OWSProgressSink?
        var source: OWSProgressSource?

        /// Currently active downloads for which we update progress byte-by-byte.
        var activeDownloadByteCounts = [Attachment.IDType: UInt64]()
    }

    private let appContext: AppContext
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupSettingsStore: BackupSettingsStore
    private let dateProvider: DateProvider
    private let db: DB
    private let remoteConfigProvider: RemoteConfigProvider

    private let state = AtomicValue<State>(State(), lock: .init())

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
            self?.initializeProgress()
        }
    }

    /// Populate an initial progress value at launch, so we can report progress
    /// for a queue that has downloads pending but isn't running yet.
    private func initializeProgress() {
        Task { @concurrent [self] in
            guard
                appContext.isMainApp,
                state.get().latestProgress == nil
            else {
                return
            }

            let (pendingByteCount, finishedByteCount) = fetchEstimatedByteCounts()
            let totalByteCount = pendingByteCount + finishedByteCount

            guard totalByteCount > 0 else {
                return
            }

            updateObservers(OWSProgress(
                completedUnitCount: finishedByteCount,
                totalUnitCount: totalByteCount,
            ))
        }
    }

    private func fetchEstimatedByteCounts() -> (pendingByteCount: UInt64, finishedByteCount: UInt64) {
        return db.read { tx -> (UInt64, UInt64) in
            return (
                backupAttachmentDownloadStore.computeEstimatedRemainingFullsizeByteCount(tx: tx) ?? 0,
                backupAttachmentDownloadStore.computeEstimatedFinishedFullsizeByteCount(tx: tx) ?? 0,
            )
        }
    }

    private func didUpdateProgressForActiveDownload(
        id: Attachment.IDType,
        completedByteCount: UInt64,
        totalByteCount: UInt64,
    ) {
        guard totalByteCount != 0 else {
            return
        }
        state.update { _state in
            _didUpdateProgressForActiveDownload(
                state: &_state,
                id: id,
                completedByteCount: completedByteCount,
                totalByteCount: totalByteCount,
            )
        }
    }

    private func _didUpdateProgressForActiveDownload(
        state: inout State,
        id: Attachment.IDType,
        completedByteCount: UInt64,
        totalByteCount: UInt64,
    ) {
        let prevByteCount = state.activeDownloadByteCounts[id] ?? 0
        if let source = state.source {
            let diff = min(max(completedByteCount, prevByteCount) - prevByteCount, source.totalUnitCount - source.completedUnitCount)
            if diff > 0 {
                source.incrementCompletedUnitCount(by: diff)
            }
        }
        if completedByteCount < totalByteCount {
            state.activeDownloadByteCounts[id] = completedByteCount
        }
    }

    // MARK: -

    /// Serializes potentially-concurrent progress updates being stored and
    /// published to observers.
    private let updateObserversTaskQueue = SerialTaskQueue()

    private func updateObservers(_ progress: OWSProgress) {
        updateObserversTaskQueue.enqueue { [self] in
            let observers = state.update { _state -> [Observer] in
                _state.latestProgress = progress
                return _state.observers.elements
            }
            for observer in observers {
                observer.block(progress)
            }
        }
    }
}

// MARK: -

#if TESTABLE_BUILD

open class BackupAttachmentDownloadProgressMock: BackupAttachmentDownloadProgress {

    init() {}

    open func addObserver(
        _ block: @escaping (OWSProgress) -> Void,
    ) -> Observer {
        return Observer(block: block)
    }

    open func removeObserver(_ observer: Observer) {
        // Do nothing
    }

    open func removeObserver(_ id: UUID) {
        // Do nothing
    }

    open func beginObserving() {
        // Do nothing
    }

    open func willBeginDownloadingFullsizeAttachment(
        withId id: Attachment.IDType,
    ) -> any OWSProgressSink {
        return OWSProgress.createSink({ _ in })
    }

    open func didFinishDownloadOfFullsizeAttachment(
        withId id: Attachment.IDType,
        byteCount: UInt64,
    ) {
        // Do nothing
    }

    open func didEmptyFullsizeDownloadQueue() {
        // Do nothing
    }
}

#endif
