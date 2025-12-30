//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension Notification.Name {

    /// Fire this notification to trigger an asynchronous upload of all attachments in the upload queue
    public static let startBackupAttachmentUploadQueue = Notification.Name("Signal.startBackupAttachmentUploadQueue")
}

/// Coordinates backup attachment operations (upload, download, deletions, reconciliation)
/// which must all be locked relative to each other to prevent races with their async state updates.
///
/// Callers that wish to start or await uploads/downloads should go through this class.
public protocol BackupAttachmentCoordinator {

    // MARK: - Downloads

    /// Restores all pending attachments in the BackupAttachmentDownloadQueue.
    ///
    /// Will keep restoring attachments until there are none left, then returns.
    /// Is cooperatively cancellable; will check and early terminate if the task is cancelled
    /// in between individual attachments.
    ///
    /// Returns immediately if there's no attachments left to restore.
    ///
    /// Each individual attachments has its thumbnail and fullsize data downloaded as appropriate.
    ///
    /// Throws an error IFF something would prevent all attachments from restoring (e.g. network issue).
    func restoreAttachmentsIfNeeded() async throws

    // MARK: - Uploads

    /// Backs up all pending attachments in the BackupAttachmentUploadQueue.
    ///
    /// Will keep backing up attachments until there are none left, then returns.
    /// Is cooperatively cancellable; will check and early terminate if the task is cancelled
    /// in between individual attachments.
    ///
    /// Returns immediately if there's no attachments left to back up.
    ///
    /// Each individual attachments is either freshly uploaded or copied from the transit
    /// tier to the media tier as needed. Thumbnail versions are also created, uploaded, and
    /// backed up as needed.
    ///
    /// Throws an error IFF something would prevent all attachments from backing up (e.g. network issue).
    func backUpAllAttachments(waitOnThumbnails: Bool) async throws

    // MARK: - List Media

    func queryListMediaIfNeeded() async throws

    // MARK: - Orphaning

    /// Run all remote deletions, returning when finished. Supports cooperative cancellation.
    /// Should only be run after backup uploads have finished to avoid races.
    func deleteOrphansIfNeeded() async throws

    // MARK: - Offloading

    /// Walk over all attachments and delete local files for any that are eligible to be
    /// offloaded.
    /// This can be a very expensive operation (e.g. if "optimize local storage" was
    /// just enabled and there's a lot to clean up) so it is best to call this in a
    /// non-user-blocking context, e.g. during an overnight backup BGProcessingTask.
    ///
    /// Supports cooperative cancellation; makes incremental progress if cancelled.
    func offloadAttachmentsIfNeeded() async throws
}

public actor BackupAttachmentCoordinatorImpl: BackupAttachmentCoordinator {

    private let appContext: AppContext
    private let appReadiness: AppReadiness
    private let backupSettingsStore: BackupSettingsStore
    private let db: any DB
    private let downloadRunner: BackupAttachmentDownloadQueueRunner
    private let listMediaManager: BackupListMediaManager
    private let offloadingManager: AttachmentOffloadingManager
    private let orphanRunner: OrphanedBackupAttachmentQueueRunner
    private let orphanStore: OrphanedBackupAttachmentStore
    private nonisolated let tsAccountManager: TSAccountManager
    private nonisolated let uploadRunner: BackupAttachmentUploadQueueRunner

    public init(
        appContext: AppContext,
        appReadiness: AppReadiness,
        backupSettingsStore: BackupSettingsStore,
        db: any DB,
        downloadRunner: BackupAttachmentDownloadQueueRunner,
        listMediaManager: BackupListMediaManager,
        offloadingManager: AttachmentOffloadingManager,
        orphanRunner: OrphanedBackupAttachmentQueueRunner,
        orphanStore: OrphanedBackupAttachmentStore,
        tsAccountManager: TSAccountManager,
        uploadRunner: BackupAttachmentUploadQueueRunner,
    ) {
        self.appContext = appContext
        self.appReadiness = appReadiness
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.downloadRunner = downloadRunner
        self.listMediaManager = listMediaManager
        self.offloadingManager = offloadingManager
        self.orphanRunner = orphanRunner
        self.orphanStore = orphanStore
        self.tsAccountManager = tsAccountManager
        self.uploadRunner = uploadRunner

        let weakSelf = Weak(value: self)
        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            weakSelf.value?.startObservingExternalEvents()
            Task {
                await weakSelf.value?.scheduleOperations([
                    .listMedia,
                    .downloadFullsize,
                    .downloadThumbnail,
                    .uploadFullsize,
                    .uploadThumbnail,
                ])
            }
        }
    }

    // MARK: - Downloads

    public func restoreAttachmentsIfNeeded() async throws {
        try await awaitOperations([.downloadFullsize, .downloadThumbnail])
    }

    // MARK: - Uploads

    public func backUpAllAttachments(waitOnThumbnails: Bool) async throws {
        var operations: [Operation] = [.uploadFullsize]
        if waitOnThumbnails {
            operations.append(.uploadThumbnail)
        }
        try await awaitOperations(operations)
    }

    // MARK: - List Media

    public func queryListMediaIfNeeded() async throws {
        if !(isRunning(.listMedia) || db.read(block: listMediaManager.getNeedsQueryListMedia(tx:))) {
            // Early exit if we don't need to run list media at all and aren't currently running.
            return
        }
        try await self.awaitOperation(.listMedia)
    }

    // MARK: - Orphaning

    public func deleteOrphansIfNeeded() async throws {
        try await self.awaitOperation(.deleteOrphans)
    }

    // MARK: - Offloading

    public func offloadAttachmentsIfNeeded() async throws {
        try await self.awaitOperation(.offloading)
    }

    // MARK: - Status Observation

    private nonisolated func startObservingExternalEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(backUpAllAttachmentsFromNotification),
            name: .startBackupAttachmentUploadQueue,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fullsizeDownloadQueueStatusDidChange),
            name: .backupAttachmentDownloadQueueStatusDidChange(mode: .fullsize),
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thumbnailDownloadQueueStatusDidChange),
            name: .backupAttachmentDownloadQueueStatusDidChange(mode: .thumbnail),
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fullsizeUploadQueueStatusDidChange),
            name: .backupAttachmentUploadQueueStatusDidChange(for: .fullsize),
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thumbnailUploadQueueStatusDidChange),
            name: .backupAttachmentUploadQueueStatusDidChange(for: .thumbnail),
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(backupPlanDidChange),
            name: .backupPlanChanged,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationStateDidChange),
            name: .registrationStateDidChange,
            object: nil,
        )
    }

    @objc
    private nonisolated func fullsizeDownloadQueueStatusDidChange() {
        Task { [weak self] in
            await self?.scheduleOperation(.downloadFullsize)
        }
    }

    @objc
    private nonisolated func thumbnailDownloadQueueStatusDidChange() {
        Task { [weak self] in
            await self?.scheduleOperation(.downloadThumbnail)
        }
    }

    @objc
    private nonisolated func fullsizeUploadQueueStatusDidChange() {
        Task { [weak self] in
            await self?.scheduleOperation(.uploadFullsize)
        }
    }

    @objc
    private nonisolated func thumbnailUploadQueueStatusDidChange() {
        Task { [weak self] in
            await self?.scheduleOperation(.uploadThumbnail)
        }
    }

    @objc
    private nonisolated func backupPlanDidChange() {
        Task { [weak self] in
            await self?.scheduleOperations([
                .listMedia,
                .downloadFullsize,
                .downloadThumbnail,
                .uploadFullsize,
                .uploadThumbnail,
            ])
        }
    }

    @objc
    private nonisolated func registrationStateDidChange() {
        Task { [weak self] in
            await self?.scheduleOperations([
                .listMedia,
                .downloadFullsize,
                .downloadThumbnail,
                .uploadFullsize,
                .uploadThumbnail,
            ])
        }
    }

    @objc
    private nonisolated func backUpAllAttachmentsFromNotification() {
        Task { [weak self] in
            await self?.scheduleOperations([.uploadFullsize, .uploadThumbnail])
        }
    }

    // MARK: - State Management

    private struct Observer {
        let id: UUID
        let continuation: CancellableContinuation<Void>?

        var isCancellable: Bool { continuation != nil }

        init(_ continuation: CancellableContinuation<Void>? = nil) {
            self.id = UUID()
            self.continuation = continuation
        }
    }

    private enum Operation: Hashable, CaseIterable {
        case listMedia
        case downloadFullsize
        case downloadThumbnail
        case uploadFullsize
        case uploadThumbnail
        case deleteOrphans
        case offloading
    }

    private var runningTasks = [Operation: Task<Void, Error>]()
    /// When an operation starts to run, we snapshot the observers at the time.
    /// If an observer is added while running, it goes into pendingObservers instead
    /// so that it can trigger a second run of the operation after the current one finishes.
    private var runningTaskObservers = [Operation: [Observer]]()
    private var pendingObservers = [Operation: [Observer]]()

    private func needsToRun(_ operation: Operation) -> Bool {
        return !(pendingObservers[operation]?.isEmpty ?? true)
    }

    private func isRunning(_ operation: Operation) -> Bool {
        return runningTasks[operation] != nil
    }

    private func scheduleOperation(_ operation: Operation) {
        self.scheduleOperations([operation])
    }

    private func scheduleOperations(_ operations: [Operation]) {
        guard appContext.isMainApp, tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }

        operations.forEach { operation in
            self.pendingObservers[operation, default: []] += [Observer()]
        }
        kickOffNextOperation()
    }

    private func awaitOperation(_ operation: Operation) async throws {
        try await awaitOperations([operation])
    }

    private func awaitOperations(_ operations: [Operation]) async throws {
        guard appContext.isMainApp else {
            return
        }

        let observers = operations.map { operation in
            let observer = Observer(CancellableContinuation())
            self.pendingObservers[operation, default: []] += [observer]
            return (operation, observer)
        }

        kickOffNextOperation()

        let weakSelf = Weak(value: self)
        try await withThrowingTaskGroup { taskGroup in
            for (operation, observer) in observers {
                let observerId = observer.id
                let continuation = observer.continuation
                taskGroup.addTask {
                    try await withTaskCancellationHandler(
                        operation: {
                            try await continuation?.wait()
                        },
                        onCancel: {
                            Task {
                                await weakSelf.value?.cancelOperation(
                                    operation,
                                    observerId: observerId,
                                )
                            }
                        },
                    )
                }
            }
            try await taskGroup.waitForAll()
        }
    }

    private func cancelOperation(
        _ operation: Operation,
        observerId: UUID,
    ) {
        var pendingObservers = self.pendingObservers[operation] ?? []
        if let observer = pendingObservers.removeFirst(where: { $0.isCancellable && $0.id == observerId }) {
            self.pendingObservers[operation] = pendingObservers
            observer.continuation?.cancel()
            return
        }
        var runningTaskObservers = self.runningTaskObservers[operation] ?? []
        if nil != runningTaskObservers.removeFirst(where: { $0.isCancellable && $0.id == observerId }) {
            self.runningTaskObservers[operation] = runningTaskObservers
            if runningTaskObservers.isEmpty {
                // Cancel the actual operation if this is the only observer.
                self.runningTasks[operation]?.cancel()
            }
        }
    }

    private func kickOffNextOperation() {
        guard appReadiness.isAppReady && appContext.isMainApp && tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            // We will kick off again when the app is ready; whatever
            // got scheduled will run then.
            return
        }

        // Always check if we need to run list media and do so aggresively
        // even if there are no observers. The other operations rely on this.
        let hasUncancellableListMediaObserver = (self.pendingObservers[.listMedia] ?? [])
            .contains(where: \.isCancellable.negated)
        if !hasUncancellableListMediaObserver, self.runningTasks.isEmpty {
            let needsListMedia = db.read { tx in
                return listMediaManager.getNeedsQueryListMedia(tx: tx)
            }
            if needsListMedia {
                var listMediaObservers = self.pendingObservers[.listMedia] ?? []
                listMediaObservers.append(Observer())
                self.pendingObservers[.listMedia] = listMediaObservers
            }
        }

        if needsToRun(.listMedia) {
            // List media cannot run in parallel with anything;
            // only run if nothing is running.
            // Other operations stop themselves if list media is
            // needed; when they do we will loop back here and
            // run list media then.
            if self.runningTasks.isEmpty {
                self.runOperation(.listMedia)
            }
            // If we need to list media, we never run anything else.
            // Return now whether we started list media this run
            // loop or not.
            return
        }

        func canRunDeleteOrphans() -> Bool {
            let isRunningExclusiveOperation = runningTasks.contains(where: {
                switch $0.key {
                case .downloadThumbnail, .uploadThumbnail:
                    // These can run in parallel with the rest
                    return false
                case .downloadFullsize:
                    // Downloads and orphaning can run in parallel
                    return false
                case
                    .listMedia, .uploadFullsize,
                    .deleteOrphans, .offloading:
                    return true
                }
            })
            return !isRunningExclusiveOperation
        }

        let hasConsumedMediaTierCapacity = db.read { tx in
            backupSettingsStore.hasConsumedMediaTierCapacity(tx: tx)
        }
        if hasConsumedMediaTierCapacity {
            // If we are out of storage space...
            // * issue deletes if we can, to free up space
            if canRunDeleteOrphans(), needsToRun(.deleteOrphans) {

                let orphanCount = db.read { tx in
                    (try? orphanStore.peek(count: 1, tx: tx))?.count ?? 1
                }
                if orphanCount > 0 {
                    self.runOperation(.deleteOrphans)
                    // * do NOT run anything else until we can run deletes
                    // Other operations stop themselves if out of space;
                    // when they do we will loop back here and run deletes.
                    return
                }
            }
        }

        // Thumbnail upload and download can run in parallel with
        // any of the other operations:
        // * no overlap/races with fullsize upload download
        // * orphaning does have a race: delete an attachment, issue
        //   delete request for media tier thumbnail, wait on response,
        //   recreate same media bytes, upload thumbnail, delete finishes.
        //   That deletes the upload, but note this requires an enormous
        //   gap between delete request/response large enough to do a whole
        //   upload so in practice not a concern. (And even if it happens
        //   we just lose a thumbnail which is recoverable from fullsize.)
        // * offloading may generate thumbnails from already-downloaded
        //   fullsize media, but we don't download thumbnails if we
        //   already have fullsize, anyway
        if needsToRun(.downloadThumbnail) && !isRunning(.downloadThumbnail) {
            runOperation(.downloadThumbnail)
        }
        if needsToRun(.uploadThumbnail) && !isRunning(.uploadThumbnail) {
            runOperation(.uploadThumbnail)
        }

        if needsToRun(.uploadFullsize) || needsToRun(.downloadFullsize) {
            // Upload and download can run in parallel, but cannot
            // run if anything else is running.
            let isRunningNonUploadDownload: Bool = runningTasks.contains(where: {
                switch $0.key {
                case
                    .downloadFullsize, .downloadThumbnail,
                    .uploadFullsize, .uploadThumbnail:
                    return false
                case .listMedia, .deleteOrphans, .offloading:
                    return true
                }
            })
            if !isRunningNonUploadDownload {
                if needsToRun(.downloadFullsize), !isRunning(.downloadFullsize) {
                    self.runOperation(.downloadFullsize)
                }
                if needsToRun(.uploadFullsize), !isRunning(.uploadFullsize) {
                    self.runOperation(.uploadFullsize)
                }
            }
        }

        func canRunOffloading() -> Bool {
            let isRunningExclusiveOperation = runningTasks.contains(where: {
                switch $0.key {
                case .downloadThumbnail, .uploadThumbnail:
                    // These can run in parallel with the rest
                    return false
                case
                    .listMedia, .downloadFullsize, .uploadFullsize,
                    .deleteOrphans, .offloading:
                    return true
                }
            })
            return !isRunningExclusiveOperation
        }

        if canRunDeleteOrphans(), needsToRun(.deleteOrphans) {
            self.runOperation(.deleteOrphans)
        } else if canRunOffloading(), needsToRun(.offloading) {
            self.runOperation(.offloading)
        }
    }

    private func runOperation(_ operation: Operation) {
        let task: Task = switch operation {
        case .listMedia:
            Task { [appReadiness, listMediaManager] in
                try await appReadiness.waitForAppReady()
                try await listMediaManager.queryListMediaIfNeeded()
            }
        case .downloadFullsize:
            Task { [appReadiness, downloadRunner] in
                try await appReadiness.waitForAppReady()
                try await downloadRunner.restoreAttachmentsIfNeeded(mode: .fullsize)
            }
        case .downloadThumbnail:
            Task { [appReadiness, downloadRunner] in
                try await appReadiness.waitForAppReady()
                try await downloadRunner.restoreAttachmentsIfNeeded(mode: .thumbnail)
            }
        case .uploadFullsize:
            Task { [appReadiness, uploadRunner] in
                try await appReadiness.waitForAppReady()
                try await uploadRunner.backUpAllAttachments(mode: .fullsize)
            }
        case .uploadThumbnail:
            Task { [appReadiness, uploadRunner] in
                try await appReadiness.waitForAppReady()
                try await uploadRunner.backUpAllAttachments(mode: .thumbnail)
            }
        case .deleteOrphans:
            Task { [appReadiness, orphanRunner] in
                try await appReadiness.waitForAppReady()
                try await orphanRunner.runIfNeeded()
            }
        case .offloading:
            Task { [appReadiness, offloadingManager] in
                try await appReadiness.waitForAppReady()
                try await offloadingManager.offloadAttachmentsIfNeeded()
            }
        }
        self.runningTasks[operation] = task
        self.runningTaskObservers[operation] = self.pendingObservers[operation]
        self.pendingObservers[operation] = nil
        Task { [weak self] in
            let result = await Result(catching: {
                try await task.value
            })
            await self?.didFinishOperation(operation, result)
        }
    }

    private func didFinishOperation(
        _ operation: Operation,
        _ result: Result<Void, Error>,
    ) {
        self.runningTasks[operation] = nil
        switch result {
        case .failure(let error) where error is NeedsListMediaError:
            // If we stopped because we need to list media,
            // do that by inserting a list media operation observer.
            // (Even if there was already an observer, insert a new one
            // so that it can't be cancelled).
            var listMediaObservers = self.pendingObservers[.listMedia] ?? []
            listMediaObservers.append(Observer())
            self.pendingObservers[.listMedia] = listMediaObservers

            // Do not mark the current operation finished, it will
            // run again after list media is done. Mark all observers
            // pending instead.
            var pendingObservers = self.pendingObservers[operation] ?? []
            pendingObservers.append(contentsOf: self.runningTaskObservers[operation] ?? [])
            self.pendingObservers[operation] = pendingObservers
        case .success, .failure:
            self.runningTaskObservers[operation]?.forEach { observer in
                observer.continuation?.resume(with: result)
            }
            self.runningTaskObservers[operation] = nil
        }

        self.kickOffNextOperation()
    }
}

#if TESTABLE_BUILD

open class MockBackupAttachmentCoordinator: BackupAttachmentCoordinator {
    open func restoreAttachmentsIfNeeded() async throws {
        // Do nothing
    }

    open func backUpAllAttachments(waitOnThumbnails: Bool) async throws {
        // Do nothing
    }

    open func queryListMediaIfNeeded() async throws {
        // Do nothing
    }

    open func deleteOrphansIfNeeded() async throws {
        // Do nothing
    }

    open func offloadAttachmentsIfNeeded() async throws {
        // Do nothing
    }
}

#endif
