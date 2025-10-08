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

    /// WARNING: DO NOT use this method if download or upload queues may be running in parallel.
    /// It can result in undefined behavior if list media and download/upload race with each other to
    /// update local state. This method overrides the checks that normally prevent that and should
    /// only be used when uploads and downloads are suspended.
    func forceQueryListMedia() async throws

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

    private let downloadRunner: BackupAttachmentDownloadQueueRunner
    private let listMediaManager: BackupListMediaManager
    private let offloadingManager: AttachmentOffloadingManager
    private let orphanRunner: OrphanedBackupAttachmentQueueRunner
    private nonisolated let uploadRunner: BackupAttachmentUploadQueueRunner

    public init(
        downloadRunner: BackupAttachmentDownloadQueueRunner,
        listMediaManager: BackupListMediaManager,
        offloadingManager: AttachmentOffloadingManager,
        orphanRunner: OrphanedBackupAttachmentQueueRunner,
        uploadRunner: BackupAttachmentUploadQueueRunner
    ) {
        self.downloadRunner = downloadRunner
        self.listMediaManager = listMediaManager
        self.offloadingManager = offloadingManager
        self.orphanRunner = orphanRunner
        self.uploadRunner = uploadRunner

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(backUpAllAttachmentsFromNotification),
            name: .startBackupAttachmentUploadQueue,
            object: nil
        )
    }

    // MARK: - Downloads

    public func restoreAttachmentsIfNeeded() async throws {
        try await downloadRunner.restoreAttachmentsIfNeeded()
    }

    // MARK: - Uploads

    public func backUpAllAttachments(waitOnThumbnails: Bool) async throws {
        try await uploadRunner.backUpAllAttachments(waitOnThumbnails: waitOnThumbnails)
    }

    @objc
    private nonisolated func backUpAllAttachmentsFromNotification() {
        Task { [weak self] in
            try await self?.backUpAllAttachments(waitOnThumbnails: true)
        }
    }

    // MARK: - List Media

    public func queryListMediaIfNeeded() async throws {
        try await listMediaManager.queryListMediaIfNeeded()
    }

    public func forceQueryListMedia() async throws {
        try await listMediaManager.forceQueryListMedia()
    }

    // MARK: - Orphaning

    public func deleteOrphansIfNeeded() async throws {
        try await orphanRunner.runIfNeeded()
    }

    // MARK: - Offloading

    public func offloadAttachmentsIfNeeded() async throws {
        try await offloadingManager.offloadAttachmentsIfNeeded()
    }
}
