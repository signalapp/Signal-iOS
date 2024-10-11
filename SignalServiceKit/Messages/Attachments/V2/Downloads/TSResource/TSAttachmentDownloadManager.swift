//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

@objc
public class TSAttachmentDownloadManager: NSObject {

    public typealias AttachmentId = String

    private static let unfairLock = UnfairLock()
    // This property should only be accessed with unfairLock.
    private var activeJobMap = [AttachmentId: Job]()
    // This property should only be accessed with unfairLock.
    private var jobQueue = [Job]()
    // Not used to determine whether a job should be run; the source of truth
    // for that is the database Attachment's state.
    // Just used to drive progress indicators.
    private var completeAttachmentMap = LRUCache<AttachmentId, Bool>(maxSize: 256)

    private let appReadiness: AppReadiness
    private static let schedulers: Schedulers = DispatchQueueSchedulers()
    private var schedulers: Schedulers { Self.schedulers }

    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        super.init()

        SwiftSingletons.register(self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(profileWhitelistDidChange(notification:)),
            name: UserProfileNotifications.profileWhitelistDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { self.startPendingMessageDownloads() }
    }

    @objc
    func profileWhitelistDidChange(notification: Notification) {
        AssertIsOnMainThread()

        // If a thread was newly whitelisted, try and start any
        // downloads that were pending on a message request.
        let requestsToEnqueue = SSKEnvironment.shared.databaseStorageRef.read { transaction -> [(messageId: String, jobRequest: MessageJobRequest)] in
            guard let whitelistedThread = ({ () -> TSThread? in
                if let address = notification.userInfo?[UserProfileNotifications.profileAddressKey] as? SignalServiceAddress,
                   address.isValid,
                   SSKEnvironment.shared.profileManagerRef.isUser(inProfileWhitelist: address, transaction: transaction) {
                    return TSContactThread.getWithContactAddress(address, transaction: transaction)
                }
                if let groupId = notification.userInfo?[UserProfileNotifications.profileGroupIdKey] as? Data,
                   SSKEnvironment.shared.profileManagerRef.isGroupId(inProfileWhitelist: groupId, transaction: transaction) {
                    return TSGroupThread.fetch(groupId: groupId, transaction: transaction)
                }
                return nil
            }()) else {
                return []
            }
            return jobRequestsForAllAttachments(for: whitelistedThread, tx: transaction)
        }
        for (messageId, jobRequest) in requestsToEnqueue {
            enqueueMessageJobRequest(jobRequest, messageId: messageId)
        }
    }

    @objc
    func applicationDidBecomeActive() {
        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { self.startPendingMessageDownloads() }
    }

    // MARK: -

    private static let pendingMessageDownloads = SDSKeyValueStore(collection: "PendingNewMessageDownloads")
    private static let pendingStoryMessageDownloads = SDSKeyValueStore(collection: "PendingNewStoryMessageDownloads")

    private func startPendingMessageDownloads() {
        owsAssertDebug(CurrentAppContext().isMainApp)

        let (pendingMessageDownloads, pendingStoryMessageDownloads) = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            (
                Self.pendingMessageDownloads.allUIntValuesMap(transaction: transaction),
                Self.pendingStoryMessageDownloads.allUIntValuesMap(transaction: transaction)
            )
        }

        guard !pendingMessageDownloads.isEmpty || !pendingStoryMessageDownloads.isEmpty else { return }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            self.processPendingMessages(
                pendingMessageDownloads,
                store: Self.pendingMessageDownloads,
                transaction: transaction
            ) { pendingMessageId, downloadBehavior in
                self.enqueueDownloadOfAttachmentsForMessageId(
                    pendingMessageId,
                    downloadBehavior: downloadBehavior,
                    transaction: transaction
                )
            }

            self.processPendingMessages(
                pendingStoryMessageDownloads,
                store: Self.pendingStoryMessageDownloads,
                transaction: transaction
            ) { pendingStoryMessageId, downloadBehavior in
                self.enqueueDownloadOfAttachmentsForStoryMessageId(
                    pendingStoryMessageId,
                    downloadBehavior: downloadBehavior,
                    transaction: transaction
                )
            }
        }
    }

    private func processPendingMessages(
        _ pendingMessages: [String: UInt],
        store: SDSKeyValueStore,
        transaction: SDSAnyWriteTransaction,
        enqueue: (String, TSAttachmentDownloadBehavior) -> Void
    ) {
        for (uniqueId, rawDownloadBehavior) in pendingMessages {
            guard let downloadBehavior = TSAttachmentDownloadBehavior(rawValue: rawDownloadBehavior) else {
                owsFailDebug("Unexpected download behavior \(rawDownloadBehavior)")
                store.removeValue(forKey: uniqueId, transaction: transaction)
                continue
            }

            enqueue(uniqueId, downloadBehavior)
        }
    }

    // MARK: -

    public func downloadProgress(forAttachmentId attachmentId: AttachmentId) -> CGFloat? {
        Self.unfairLock.withLock {
            if let job = activeJobMap[attachmentId] {
                return job.progress
            }
            if nil != completeAttachmentMap[attachmentId] {
                return 1.0
            }
            return nil
        }
    }

    // MARK: -

    private func enqueueJobs(jobs: [Job]) {
        Self.unfairLock.withLock {
            jobQueue.append(contentsOf: jobs)
        }

        tryToStartNextDownload()
    }

    private func dequeueNextJobs() -> [(Job, TSAttachmentPointer)] {
        /// Within the lock we:
        /// 1. Check if we have a job thats eligible to run
        ///     a. Not too many parallel downloads
        ///     b. A job for the same attachment is not already in progress or complete.
        ///     c. The job has not been cancelled.
        /// 2. Re-fetch the attachment for the job
        ///     a. Ensure its not already downloaded, or was not deleted
        /// 3. Mark the job as running
        ///
        /// Because we check whether we are already running a job and then mark the job
        /// as running within the lock, we avoid races.
        return Self.unfairLock.withLock {
            let kMaxSimultaneousDownloads: Int = CurrentAppContext().isNSE ? 1 : 4
            let maxNumJobsToRun = kMaxSimultaneousDownloads - activeJobMap.count
            guard maxNumJobsToRun > 0 else {
                return []
            }
            var indexesToRemove = [Int]()
            var jobsToRun = [(Job, TSAttachmentPointer)]()

            // Go through each job in the queue, until we find jobs we can run,
            // up to the count we can run at a time.
            // Either:
            // 1. The job can be run: assign it to jobToRun and break
            // 2. The job can't be run yet, but might be later: leave it in the queue
            // 3. The job is running already: join its promise to the running instance & remove
            // 4. The already finished: remove it (we don't assign the promise as we assume
            //    downstream actions already happened)
            // 5. The job has been cancelled or attachment deleted: reject it and remove it
            jobLoop: for (index, job) in jobQueue.enumerated() {
                if _shouldCancelJobWithinLock(job, asOfDate: Date()) {
                    // Job is cancelled! Fail it and drop it.
                    job.future.reject(AttachmentDownloadError.cancelled)
                    indexesToRemove.append(index)

                    continue
                }

                if let existingJob = activeJobMap[job.attachmentId] {
                    // Ensure we only have one download in flight at a time for a given attachment.
                    Logger.warn("Ignoring duplicate download.")

                    // Link up this job's promise to the other job, then remove it.
                    job.future.resolve(on: schedulers.sync, with: existingJob.promise)
                    indexesToRemove.append(index)

                    continue
                }
                switch self.prepareDownload(job: job) {
                case .alreadyDownloaded:
                    self._markJobCompleteWithinLock(job, isAttachmentDownloaded: true)
                    indexesToRemove.append(index)
                    continue
                case .attachmentDeleted:
                    self._markJobCompleteWithinLock(job, isAttachmentDownloaded: true)
                    indexesToRemove.append(index)
                    continue
                case .cannotDownload:
                    // Just leave it in the queue. Maybe we can download it later.
                    continue
                case .downloadable(let tSAttachmentPointer):
                    indexesToRemove.append(index)
                    jobsToRun.append((job, tSAttachmentPointer))
                    if jobsToRun.count == maxNumJobsToRun {
                        break jobLoop
                    }
                }
            }
            for indexToRemove in indexesToRemove.reversed() {
                jobQueue.remove(at: indexToRemove)
            }

            jobsToRun.forEach { job, _  in
                activeJobMap[job.attachmentId] = job
            }

            return jobsToRun
        }
    }

    private func markJobComplete(_ job: Job, isAttachmentDownloaded: Bool) {
        Self.unfairLock.withLock {
            _markJobCompleteWithinLock(job, isAttachmentDownloaded: isAttachmentDownloaded)
        }
        tryToStartNextDownload()
    }

    private func _markJobCompleteWithinLock(_ job: Job, isAttachmentDownloaded: Bool) {
        let attachmentId = job.attachmentId

        activeJobMap[attachmentId] = nil

        cancellationRequestMap[attachmentId] = nil

        if isAttachmentDownloaded {
            owsAssertDebug(completeAttachmentMap[attachmentId] != false)
            completeAttachmentMap[attachmentId] = true
        }
    }

    private func tryToStartNextDownload() {
        let jobs = dequeueNextJobs()
        guard !jobs.isEmpty else {
            return
        }

        jobs.forEach { job, attachmentPointer in
            firstly(on: schedulers.sync) { () -> Promise<TSAttachmentStream> in
                self.retrieveAttachment(job: job, attachmentPointer: attachmentPointer)
            }.done(on: schedulers.sync) { (attachmentStream: TSAttachmentStream) in
                self.downloadDidSucceed(attachmentStream: attachmentStream, job: job)
            }.catch(on: schedulers.sync) { (error: Error) in
                self.downloadDidFail(error: error, job: job)
            }
        }
    }

    enum PrepareDownloadResult {
        case alreadyDownloaded
        case attachmentDeleted
        case cannotDownload
        case downloadable(TSAttachmentPointer)
    }

    private func prepareDownload(job: Job) -> PrepareDownloadResult {
        return SSKEnvironment.shared.databaseStorageRef.write { (transaction) -> PrepareDownloadResult in
            // Fetch latest to ensure we don't overwrite an attachment stream, resurrect an attachment, etc.
            guard let attachment = job.loadLatestAttachment(transaction: transaction) else {
                // This isn't necessarily a bug.  For example:
                //
                // * Receive an incoming message with an attachment.
                // * Kick off download of that attachment.
                // * Receive read receipt for that message, causing it to be disappeared immediately.
                // * Try to download that attachment - but it's missing.
                Logger.warn("Missing attachment: \(job.category).")
                return .attachmentDeleted
            }
            guard let attachmentPointer = attachment as? TSAttachmentPointer else {
                // This isn't necessarily a bug.
                //
                // * An attachment may have been re-enqueued for download while it was already being downloaded.
                Logger.info("Attachment already downloaded: \(job.category).")

                return .alreadyDownloaded
            }

            switch job.jobType {
            case .messageAttachment(_, let messageUniqueId):
                if DebugFlags.forceAttachmentDownloadFailures.get() {
                    Logger.info("Skipping media download for thread due to debug settings: \(job.category).")
                    attachmentPointer.updateAttachmentPointerState(from: .enqueued,
                                                                   to: .failed,
                                                                   transaction: transaction)
                    return .cannotDownload
                }

                if self.isDownloadBlockedByActiveCall(job: job) {
                    Logger.info("Skipping media download due to active call: \(job.category).")
                    attachmentPointer.updateAttachmentPointerState(from: .enqueued,
                                                                   to: .pendingManualDownload,
                                                                   transaction: transaction)
                    return .cannotDownload
                }
                guard let message = TSMessage.anyFetchMessage(uniqueId: messageUniqueId, transaction: transaction) else {
                    Logger.info("Skipping media download due to missing message: \(job.category).")
                    return .attachmentDeleted
                }
                let blockedByPendingMessageRequest = self.isDownloadBlockedByPendingMessageRequest(
                    job: job,
                    attachmentPointer: attachmentPointer,
                    message: message,
                    tx: transaction
                )
                if blockedByPendingMessageRequest {
                    Logger.info("Skipping media download for thread with pending message request: \(job.category).")
                    attachmentPointer.updateAttachmentPointerState(from: .enqueued,
                                                                   to: .pendingMessageRequest,
                                                                   transaction: transaction)
                    return .cannotDownload
                }
                let blockedByAutoDownloadSettings = self.isDownloadBlockedByAutoDownloadSettings(
                    job: job,
                    attachmentPointer: attachmentPointer,
                    transaction: transaction
                )
                if blockedByAutoDownloadSettings {
                    Logger.info("Skipping media download for thread due to auto-download settings: \(job.category).")
                    attachmentPointer.updateAttachmentPointerState(from: .enqueued,
                                                                   to: .pendingManualDownload,
                                                                   transaction: transaction)
                    return .cannotDownload
                }
            case .storyMessageAttachment:
                if DebugFlags.forceAttachmentDownloadFailures.get() {
                    Logger.info("Skipping media download for thread due to debug settings: \(job.category).")
                    attachmentPointer.updateAttachmentPointerState(from: .enqueued,
                                                                   to: .failed,
                                                                   transaction: transaction)
                    return .cannotDownload
                }

                if self.isDownloadBlockedByActiveCall(job: job) {
                    Logger.info("Skipping media download due to active call: \(job.category).")
                    attachmentPointer.updateAttachmentPointerState(from: .enqueued,
                                                                   to: .pendingManualDownload,
                                                                   transaction: transaction)
                    return .cannotDownload
                }
                let blockedByAutoDownloadSettings = self.isDownloadBlockedByAutoDownloadSettings(
                    job: job,
                    attachmentPointer: attachmentPointer,
                    transaction: transaction
                )
                if blockedByAutoDownloadSettings {
                    Logger.info("Skipping media download for thread due to auto-download settings: \(job.category).")
                    attachmentPointer.updateAttachmentPointerState(from: .enqueued,
                                                                   to: .pendingManualDownload,
                                                                   transaction: transaction)
                    return .cannotDownload
                }
            case .contactSync:
                // We don't need to apply attachment download settings
                // to contact sync attachments.
                break
            }

            Logger.info("Downloading: \(job.category).")

            attachmentPointer.updateAttachmentPointerState(.downloading, transaction: transaction)

            Self.touchAssociatedElement(for: job.jobType, tx: transaction)

            return .downloadable(attachmentPointer)
        }
    }

    private func isDownloadBlockedByActiveCall(job: Job) -> Bool {

        guard !job.downloadBehavior.bypassPendingManualDownload else {
            return false
        }

        switch job.category {
        case .bodyMediaImage, .bodyMediaVideo:
            break
        case .bodyAudioVoiceMemo, .bodyOversizeText:
            return false
        case .bodyAudioOther, .bodyFile:
            break
        case .stickerSmall:
            return false
        case .stickerLarge:
            break
        case .quotedReplyThumbnail, .linkedPreviewThumbnail, .contactShareAvatar:
            return false
        case .contactSync:
            return false
        }

        return DependenciesBridge.shared.currentCallProvider.hasCurrentCall
    }

    private func isDownloadBlockedByPendingMessageRequest(
        job: Job,
        attachmentPointer: TSAttachmentPointer,
        message: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> Bool {

        guard !job.downloadBehavior.bypassPendingMessageRequest else {
            return false
        }

        if DebugFlags.forceAttachmentDownloadPendingMessageRequest.get() {
            return true
        }

        guard attachmentPointer.isVisualMediaMimeType, message.messageSticker == nil, !message.isViewOnceMessage else {
            return false
        }

        guard message.isIncoming else {
            return false
        }

        // If there's not a thread, err on the safe side and don't download it.
        guard let thread = message.thread(tx: tx) else {
            return true
        }

        // If the message that created this attachment was the first message in the
        // thread, the thread may not yet be marked visible. In that case, just
        // check if the thread is whitelisted. We know we just received a message.
        // TODO: Mark the thread visible before this point to share more logic.
        guard thread.shouldThreadBeVisible else {
            return !SSKEnvironment.shared.profileManagerRef.isThread(inProfileWhitelist: thread, transaction: tx)
        }

        return ThreadFinder().hasPendingMessageRequest(thread: thread, transaction: tx)
    }

    private func isDownloadBlockedByAutoDownloadSettings(
        job: Job,
        attachmentPointer: TSAttachmentPointer,
        transaction: SDSAnyReadTransaction
    ) -> Bool {

        guard !job.downloadBehavior.bypassPendingManualDownload else {
            return false
        }

        if DebugFlags.forceAttachmentDownloadPendingManualDownload.get() {
            return true
        }

        let autoDownloadableMediaTypes = DependenciesBridge.shared.mediaBandwidthPreferenceStore
            .autoDownloadableMediaTypes(tx: transaction.asV2Read)

        switch job.category {
        case .bodyMediaImage:
            return !autoDownloadableMediaTypes.contains(.photo)
        case .bodyMediaVideo:
            return !autoDownloadableMediaTypes.contains(.video)
        case .bodyAudioVoiceMemo, .bodyOversizeText:
            return false
        case .bodyAudioOther:
            return !autoDownloadableMediaTypes.contains(.audio)
        case .bodyFile:
            return !autoDownloadableMediaTypes.contains(.document)
        case .stickerSmall:
            return false
        case .stickerLarge:
            return !autoDownloadableMediaTypes.contains(.photo)
        case .quotedReplyThumbnail, .linkedPreviewThumbnail, .contactShareAvatar:
            return false
        case .contactSync:
            return false
        }
    }

    private func downloadDidSucceed(attachmentStream: TSAttachmentStream,
                                    job: Job) {
        if job.category.isSticker,
           let filePath = attachmentStream.originalFilePath {
            let imageMetadata = Data.imageMetadata(withPath: filePath, mimeType: nil)
            if imageMetadata.imageFormat != .unknown,
               let mimeTypeFromMetadata = imageMetadata.mimeType {
                attachmentStream.replaceUnsavedContentType(mimeTypeFromMetadata)
            }
        }

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            guard let attachmentPointer = job.loadLatestAttachment(transaction: transaction) as? TSAttachmentPointer else {
                Logger.warn("Attachment pointer no longer exists.")
                return
            }
            attachmentPointer.anyRemove(transaction: transaction)
            attachmentStream.anyInsert(transaction: transaction)

            Self.touchAssociatedElement(for: job.jobType, tx: transaction)
        }

        // TODO: Should we fulfill() if the attachmentPointer no longer existed?
        job.future.resolve(attachmentStream)

        markJobComplete(job, isAttachmentDownloaded: true)
    }

    private func downloadDidFail(error: Error, job: Job) {
        Logger.error("Attachment download failed with error: \(error)")

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            // Fetch latest to ensure we don't overwrite an attachment stream, resurrect an attachment, etc.
            guard let attachmentPointer = job.loadLatestAttachment(transaction: transaction) as? TSAttachmentPointer else {
                Logger.warn("Attachment pointer no longer exists.")
                return
            }
            switch attachmentPointer.state {
            case .failed, .pendingMessageRequest, .pendingManualDownload:
                owsFailDebug("Unexpected state: \(NSStringForTSAttachmentPointerState(attachmentPointer.state))")
            case .enqueued, .downloading:
                // If the download was cancelled, mark as paused.                
                if case AttachmentDownloadError.cancelled = error {
                    attachmentPointer.updateAttachmentPointerState(.pendingManualDownload, transaction: transaction)
                } else {
                    attachmentPointer.updateAttachmentPointerState(.failed, transaction: transaction)
                }
            }

            Self.touchAssociatedElement(for: job.jobType, tx: transaction)
        }

        job.future.reject(error)

        markJobComplete(job, isAttachmentDownloaded: false)
    }

    private static func touchAssociatedElement(for jobType: JobType, tx: SDSAnyWriteTransaction) {
        switch jobType {
        case .messageAttachment(attachmentId: _, messageUniqueId: let messageUniqueId):
            touchLatestVersionOfMessage(uniqueId: messageUniqueId, tx: tx)
        case .storyMessageAttachment(attachmentId: _, storyMessage: let storyMessage):
            SSKEnvironment.shared.databaseStorageRef.touch(storyMessage: storyMessage, transaction: tx)
        case .contactSync:
            break
        }
    }

    private static func touchLatestVersionOfMessage(uniqueId: String, tx: SDSAnyWriteTransaction) {
        guard let latestMessage = TSMessage.anyFetchMessage(uniqueId: uniqueId, transaction: tx) else {
            // This path could happen in practice but should be very rare.
            owsFailDebug("Message has been deleted.")
            return
        }
        // We need to re-index as we may have just downloaded an attachment
        // that affects index content (e.g. oversize text attachment).
        SSKEnvironment.shared.databaseStorageRef.touch(interaction: latestMessage, shouldReindex: true, transaction: tx)
    }

    // MARK: - Cancellation

    // This property should only be accessed with unfairLock.
    private var cancellationRequestMap = [String: Date]()

    public func cancelDownload(attachmentId: AttachmentId) {
        Self.unfairLock.withLock {
            cancellationRequestMap[attachmentId] = Date()
        }
    }

    private func shouldCancelJob(downloadState: DownloadState) -> Bool {
        Self.unfairLock.withLock {
            _shouldCancelJobWithinLock(downloadState.job, asOfDate: downloadState.startDate)
        }
    }

    private func _shouldCancelJobWithinLock(_ job: Job, asOfDate date: Date) -> Bool {
        guard let cancellationDate = cancellationRequestMap[job.attachmentId] else {
            return false
        }
        return cancellationDate > date
    }
}

// MARK: - Settings

@objc
public enum TSAttachmentDownloadBehavior: UInt, Equatable {
    case `default`
    case bypassPendingMessageRequest
    case bypassPendingManualDownload
    case bypassAll

    public static var defaultValue: MediaBandwidthPreferences.Preference { .wifiAndCellular }

    public var bypassPendingMessageRequest: Bool {
        switch self {
        case .bypassPendingMessageRequest, .bypassAll:
            return true
        default:
            return false
        }
    }

    public var bypassPendingManualDownload: Bool {
        switch self {
        case .bypassPendingManualDownload, .bypassAll:
            return true
        default:
            return false
        }
    }
}

// MARK: - Enqueue

public extension TSAttachmentDownloadManager {

    func enqueueContactSyncDownload(attachmentPointer: TSAttachmentPointer) async throws -> TSAttachmentStream {
        // Dispatch to a background queue because the legacy code uses non-awaitable
        // db writes, and therefore cannot be on a Task queue.
        let (downloadPromise, downloadFuture) = Promise<TSAttachmentStream>.pending()
        DispatchQueue.sharedBackground.async { [self] in
            let jobRequest = ContactSyncJobRequest(attachmentPointer: attachmentPointer)
            self.enqueueDownload(jobRequest: jobRequest)
            let jobPromise = jobRequest.job.promise
            downloadFuture.resolve(
                on: SyncScheduler(),
                with: jobPromise
            )
        }
        return try await downloadPromise.awaitable()

    }

    private func enqueueDownload(jobRequest: JobRequest) {
        guard !CurrentAppContext().isRunningTests else {
            jobRequest.jobs.forEach {
                $0.future.reject(TSAttachmentDownloadManager.buildError())
            }
            return
        }

        self.enqueueJobs(jobRequest: jobRequest)
    }

    private func jobRequestsForAllAttachments(
        for thread: TSThread,
        tx: SDSAnyReadTransaction
    ) -> [(messageId: String, jobRequest: MessageJobRequest)] {
        do {
            var requestsToEnqueue = [(messageId: String, jobRequest: MessageJobRequest)]()
            try Self.enumerateMessagesWithLegacyAttachments(
                inThreadUniqueId: thread.uniqueId,
                transaction: tx
            ) { (message, _) in
                let messageId = message.uniqueId
                let jobRequest = buildMessageJobRequest(
                    for: messageId,
                    attachmentGroup: .allAttachments,
                    downloadBehavior: .default,
                    tx: tx
                )
                guard let jobRequest else {
                    return
                }
                requestsToEnqueue.append((messageId, jobRequest))
            }
            return requestsToEnqueue
        } catch {
            owsFailDebug("Error: \(error.grdbErrorForLogging)")
            return []
        }
    }

    func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        downloadBehavior: TSAttachmentDownloadBehavior,
        transaction: SDSAnyWriteTransaction
    ) {
        // No attachments, nothing to do.
        guard !TSAttachmentStore().allAttachmentIds(for: message).isEmpty else { return }

        enqueueDownloadOfAttachmentsForMessageId(
            message.uniqueId,
            downloadBehavior: message is TSOutgoingMessage ? .bypassAll : downloadBehavior,
            transaction: transaction
        )
    }

    private func enqueueDownloadOfAttachmentsForMessageId(
        _ messageId: String,
        downloadBehavior: TSAttachmentDownloadBehavior,
        transaction: SDSAnyWriteTransaction
    ) {
        // If we're not the main app, queue up the download for the next time
        // the main app launches.
        guard CurrentAppContext().isMainApp else {
            Self.pendingMessageDownloads.setUInt(
                downloadBehavior.rawValue,
                key: messageId,
                transaction: transaction
            )
            // Warning: kind of dangerous to return a fulfilled promise here,
            // but without a mayor overhaul its unavoidable.
            // We are moving to v2 attachments, so an overhaul of this legacy
            // class is overkill.
            return
        }

        Self.pendingMessageDownloads.removeValue(forKey: messageId, transaction: transaction)

        // Don't enqueue the attachment downloads until the write
        // transaction is committed or attachmentDownloads might race
        // and not be able to find the attachment(s)/message/thread.
        transaction.addAsyncCompletionOffMain {
            self.enqueueDownloadOfAttachments(
                forMessageId: messageId,
                attachmentGroup: .allAttachments,
                downloadBehavior: downloadBehavior
            )
        }
    }

    func enqueueDownloadOfAttachments(
        forMessageId messageId: String,
        attachmentGroup: AttachmentGroup,
        downloadBehavior: TSAttachmentDownloadBehavior
    ) {
        guard !CurrentAppContext().isRunningTests else {
            return
        }

        let jobRequest = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return buildMessageJobRequest(
                for: messageId,
                attachmentGroup: attachmentGroup,
                downloadBehavior: downloadBehavior,
                tx: tx
            )
        }

        guard let jobRequest else {
            return
        }

        enqueueMessageJobRequest(jobRequest, messageId: messageId)

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { tx in
            guard let message = TSMessage.anyFetchMessage(uniqueId: messageId, transaction: tx) else {
                return
            }
            SSKEnvironment.shared.databaseStorageRef.touch(
                interaction: message,
                shouldReindex: false,
                transaction: tx
            )
        }
    }

    private func buildMessageJobRequest(
        for messageId: String,
        attachmentGroup: AttachmentGroup,
        downloadBehavior: TSAttachmentDownloadBehavior,
        tx: SDSAnyReadTransaction
    ) -> MessageJobRequest? {
        guard let message = TSMessage.anyFetchMessage(uniqueId: messageId, transaction: tx) else {
            return nil
        }
        let jobRequest = MessageJobRequest(
            message: message,
            attachmentGroup: attachmentGroup,
            downloadBehavior: downloadBehavior,
            tx: tx
        )
        guard !jobRequest.isEmpty else {
            return nil
        }

        return jobRequest
    }

    private func enqueueMessageJobRequest(_ jobRequest: MessageJobRequest, messageId: String) {
        self.enqueueJobs(jobRequest: jobRequest)

        jobRequest.quotedReplyThumbnailPromise?.done(on: schedulers.global()) { attachmentStream in
            Self.updateQuotedMessageThumbnail(
                messageId: messageId,
                attachmentStream: attachmentStream
            )
        }.cauterize()

        Promise.when(
            on: schedulers.sync,
            fulfilled: jobRequest.jobs.map(\.promise)
        ).catch(on: schedulers.sync) { error in
            Logger.warn("Failed to fetch attachments for message: \(messageId) with error: \(error)")
        }.cauterize()
    }

    func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        downloadBehavior: TSAttachmentDownloadBehavior,
        transaction: SDSAnyWriteTransaction
    ) {
        switch message.attachment {
        case .file:
            break
        case .text(let textAttachemnt):
            // No attachment, nothing to do.
            guard textAttachemnt.preview?.legacyImageAttachmentId != nil else {
                return
            }
        case .foreignReferenceAttachment:
            owsFailDebug("Downloading v2 attachment with legacy download manager!")
            return
        }

        enqueueDownloadOfAttachmentsForStoryMessageId(
            message.uniqueId,
            downloadBehavior: message.direction == .outgoing ? .bypassAll : downloadBehavior,
            transaction: transaction
        )
    }

    private func enqueueDownloadOfAttachmentsForStoryMessageId(
        _ storyMessageId: String,
        downloadBehavior: TSAttachmentDownloadBehavior,
        transaction: SDSAnyWriteTransaction
    ) {
        // If we're not the main app, queue up the download for the next time
        // the main app launches.
        guard CurrentAppContext().isMainApp else {
            Self.pendingStoryMessageDownloads.setUInt(
                downloadBehavior.rawValue,
                key: storyMessageId,
                transaction: transaction
            )
            // Warning: kind of dangerous to return a fulfilled promise here,
            // but without a mayor overhaul its unavoidable.
            // We are moving to v2 attachments, so an overhaul of this legacy
            // class is overkill.
            return
        }

        Self.pendingStoryMessageDownloads.removeValue(forKey: storyMessageId, transaction: transaction)

        // Don't enqueue the attachment downloads until the write
        // transaction is committed or attachmentDownloads might race
        // and not be able to find the attachment(s)/message/thread.
        transaction.addAsyncCompletionOffMain {
            self.enqueueDownloadOfAttachments(
                forStoryMessageId: storyMessageId,
                downloadBehavior: downloadBehavior
            )
        }
    }

    func enqueueDownloadOfAttachments(
        forStoryMessageId storyMessageId: String,
        downloadBehavior: TSAttachmentDownloadBehavior
    ) {
        guard !CurrentAppContext().isRunningTests else {
            return
        }
        let bundle: (StoryMessage, StoryMessageJobRequest)? = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            guard let message = StoryMessage.anyFetch(uniqueId: storyMessageId, transaction: transaction) else {
                Logger.warn("Failed to fetch StoryMessage to download attachments")
                return nil
            }
            guard
                let jobRequest = StoryMessageJobRequest(
                    storyMessage: message,
                    downloadBehavior: downloadBehavior,
                    tx: transaction
                ),
                !jobRequest.isEmpty
            else {
                return nil
            }
            return (message, jobRequest)
        }
        guard let (storyMessage, jobRequest) = bundle else {
            return
        }

        self.enqueueJobs(jobRequest: jobRequest)

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            SSKEnvironment.shared.databaseStorageRef.touch(storyMessage: storyMessage, transaction: transaction)
        }

        Promise.when(
            on: schedulers.sync,
            fulfilled: jobRequest.jobs.map(\.promise)
        ).catch(on: schedulers.sync) { error in
            Logger.warn("Failed to fetch attachments for StoryMessage: \(storyMessageId) with error: \(error)")
        }.cauterize()
    }

    @objc
    enum AttachmentGroup: UInt, Equatable {
        case allAttachments
        case bodyAttachments

        var justBodyAttachments: Bool {
            switch self {
            case .allAttachments:
                return false
            case .bodyAttachments:
                return true
            }
        }
    }

    enum AttachmentCategory: UInt, Equatable, CustomStringConvertible {
        case bodyMediaImage
        case bodyMediaVideo
        case bodyAudioVoiceMemo
        case bodyAudioOther
        case bodyFile
        case bodyOversizeText
        case stickerSmall
        case stickerLarge
        case quotedReplyThumbnail
        case linkedPreviewThumbnail
        case contactShareAvatar
        case contactSync

        var isSticker: Bool {
            (self == .stickerSmall || self == .stickerLarge)
        }

        // MARK: - CustomStringConvertible

        public var description: String {
            switch self {
            case .bodyMediaImage:
                return ".bodyMediaImage"
            case .bodyMediaVideo:
                return ".bodyMediaVideo"
            case .bodyAudioVoiceMemo:
                return ".bodyAudioVoiceMemo"
            case .bodyAudioOther:
                return ".bodyAudioOther"
            case .bodyFile:
                return ".bodyFile"
            case .bodyOversizeText:
                return ".bodyOversizeText"
            case .stickerSmall:
                return ".stickerSmall"
            case .stickerLarge:
                return ".stickerLarge"
            case .quotedReplyThumbnail:
                return ".quotedReplyThumbnail"
            case .linkedPreviewThumbnail:
                return ".linkedPreviewThumbnail"
            case .contactShareAvatar:
                return ".contactShareAvatar"
            case .contactSync:
                return ".contactSync"
            }
        }
    }

    private class func updateQuotedMessageThumbnail(
        messageId: String,
        attachmentStream: TSAttachmentStream
    ) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            guard let message = TSMessage.anyFetchMessage(uniqueId: messageId, transaction: transaction) else {
                Logger.warn("Missing message.")
                return
            }
            message.anyUpdateMessage(transaction: transaction) { refetchedMessage in
                guard let quotedMessage = refetchedMessage.quotedMessage else {
                    return
                }
                // We update the same reference the message has, so when this closure exits and the
                // message is rewritten to disk it will be rewritten with the updated quotedMessage.
                quotedMessage.setLegacyThumbnailAttachmentStream(attachmentStream)
            }
        }
    }

    private func enqueueJobs(
        jobRequest: JobRequest
    ) {
        self.enqueueJobs(jobs: jobRequest.jobs)
    }

    @objc
    static func buildError() -> Error {
        OWSError(error: .attachmentDownloadFailed,
                 description: OWSLocalizedString("ERROR_MESSAGE_ATTACHMENT_DOWNLOAD_FAILED",
                                                comment: "Error message indicating that attachment download(s) failed."),
                 isRetryable: true)
    }

    // MARK: -

    @objc
    static let serialDecryptionQueue: DispatchQueue = {
        return DispatchQueue(label: "org.signal.attachment.download",
                             qos: .utility,
                             autoreleaseFrequency: .workItem)
    }()

    private func retrieveAttachment(job: Job,
                                    attachmentPointer: TSAttachmentPointer) -> Promise<TSAttachmentStream> {

        // We want to avoid large downloads from a compromised or buggy service.
        let maxDownloadSize = RemoteConfig.current.maxAttachmentDownloadSizeBytes

        return firstly(on: schedulers.sync) { () -> Promise<URL> in
            self.download(
                job: job,
                attachmentPointer: attachmentPointer,
                maxDownloadSizeBytes: maxDownloadSize
            )
        }.then(on: schedulers.sync) { (encryptedFileUrl: URL) -> Promise<TSAttachmentStream> in
            // This dispatches to its own queue
            Self.decrypt(encryptedFileUrl: encryptedFileUrl,
                         attachmentPointer: attachmentPointer)
        }
    }

    private class DownloadState {
        let job: Job
        let attachmentPointer: TSAttachmentPointer
        let startDate = Date()

        init(job: Job, attachmentPointer: TSAttachmentPointer) {
            self.job = job
            self.attachmentPointer = attachmentPointer
        }
    }

    private func download(
        job: Job,
        attachmentPointer: TSAttachmentPointer,
        maxDownloadSizeBytes: UInt
    ) -> Promise<URL> {

        let downloadState = DownloadState(job: job, attachmentPointer: attachmentPointer)

        return firstly(on: schedulers.sync) { () -> Promise<URL> in
            self.downloadAttempt(
                downloadState: downloadState,
                maxDownloadSizeBytes: maxDownloadSizeBytes
            )
        }
    }

    private func downloadAttempt(
        downloadState: DownloadState,
        maxDownloadSizeBytes: UInt,
        resumeData: Data? = nil,
        attemptIndex: UInt = 0
    ) -> Promise<URL> {

        let (promise, future) = Promise<URL>.pending()

        firstly(on: schedulers.global()) { () -> Promise<OWSUrlDownloadResponse> in
            let attachmentPointer = downloadState.attachmentPointer
            let urlSession = SSKEnvironment.shared.signalServiceRef.urlSessionForCdn(
                cdnNumber: attachmentPointer.cdnNumber,
                maxResponseSize: maxDownloadSizeBytes
            )
            let urlPath = try Self.urlPath(for: downloadState)
            let headers: [String: String] = [
                "Content-Type": MimeType.applicationOctetStream.rawValue
            ]

            let progress = { (task: URLSessionTask, progress: Progress) in
                self.handleDownloadProgress(
                    downloadState: downloadState,
                    task: task,
                    progress: progress,
                    future: future
                )
            }

            if let resumeData = resumeData {
                let request = try urlSession.endpoint.buildRequest(urlPath, method: .get, headers: headers)
                guard let requestUrl = request.url else {
                    return Promise(error: OWSAssertionError("Request missing url."))
                }
                return urlSession.downloadTaskPromise(requestUrl: requestUrl,
                                                      resumeData: resumeData,
                                                      progress: progress)
            } else {
                return urlSession.downloadTaskPromise(urlPath,
                                                      method: .get,
                                                      headers: headers,
                                                      progress: progress)
            }
        }.map(on: schedulers.global()) { (response: OWSUrlDownloadResponse) in
            let downloadUrl = response.downloadUrl
            guard let fileSize = OWSFileSystem.fileSize(of: downloadUrl) else {
                throw OWSAssertionError("Could not determine attachment file size.")
            }
            guard fileSize.int64Value <= maxDownloadSizeBytes else {
                throw OWSGenericError("Attachment download length exceeds max size.")
            }
            return downloadUrl
        }.recover(on: schedulers.sync) { (error: Error) -> Promise<URL> in
            Logger.warn("Error: \(error)")

            let maxAttemptCount = 16
            if error.isNetworkFailureOrTimeout,
               attemptIndex < maxAttemptCount {

                return firstly(on: Self.schedulers.sync) {
                    // Wait briefly before retrying.
                    Guarantee.after(on: Self.schedulers.global(), seconds: 0.25)
                }.then(on: Self.schedulers.sync) { () -> Promise<URL> in
                    if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
                       !resumeData.isEmpty {
                        return self.downloadAttempt(
                            downloadState: downloadState,
                            maxDownloadSizeBytes: maxDownloadSizeBytes,
                            resumeData: resumeData,
                            attemptIndex: attemptIndex + 1
                        )
                    } else {
                        return self.downloadAttempt(
                            downloadState: downloadState,
                            maxDownloadSizeBytes: maxDownloadSizeBytes,
                            attemptIndex: attemptIndex + 1
                        )
                    }
                }
            } else {
                throw error
            }
        }.done(on: schedulers.sync) { url in
            future.resolve(url)
        }.catch(on: schedulers.sync) { error in
            future.reject(error)
        }

        return promise
    }

    private class func urlPath(for downloadState: DownloadState) throws -> String {

        let attachmentPointer = downloadState.attachmentPointer
        let urlPath: String
        if attachmentPointer.cdnKey.isEmpty {
            urlPath = String(format: "attachments/%llu", attachmentPointer.serverId)
        } else {
            guard let encodedKey = attachmentPointer.cdnKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                throw OWSAssertionError("Invalid cdnKey.")
            }
            urlPath = "attachments/\(encodedKey)"
        }
        return urlPath
    }

    private enum AttachmentDownloadError: Error {
        case cancelled
    }

    private func handleDownloadProgress(
        downloadState: DownloadState,
        task: URLSessionTask,
        progress: Progress,
        future: Future<URL>
    ) {

        guard !self.shouldCancelJob(downloadState: downloadState) else {
            Logger.info("Cancelling job.")
            task.cancel()
            future.reject(AttachmentDownloadError.cancelled)
            return
        }

        // Don't do anything until we've received at least one byte of data.
        guard progress.completedUnitCount > 0 else {
            return
        }

        downloadState.job.progress = CGFloat(progress.fractionCompleted)

        // Use a slightly non-zero value to ensure that the progress
        // indicator shows up as quickly as possible.
        let progressTheta: Double = 0.001
        Self.fireProgressNotification(progress: max(progressTheta, progress.fractionCompleted),
                                      attachmentId: downloadState.attachmentPointer.uniqueId)
    }

    // MARK: -

    private class func decrypt(
        encryptedFileUrl: URL,
        attachmentPointer: TSAttachmentPointer
    ) -> Promise<TSAttachmentStream> {
        let (promise, future) = Promise<TSAttachmentStream>.pending()

        // Use serialQueue to ensure that we only load into memory
        // & decrypt a single attachment at a time.
        Self.serialDecryptionQueue.async {
            autoreleasepool {
                do {
                    let attachmentStream = SSKEnvironment.shared.databaseStorageRef.read { transaction in
                        TSAttachmentStream(pointer: attachmentPointer, transaction: transaction)
                    }

                    guard let originalMediaURL = attachmentStream.originalMediaURL else {
                        throw OWSAssertionError("Missing originalMediaURL.")
                    }

                    guard let encryptionKey = attachmentPointer.encryptionKey else {
                        throw OWSAssertionError("Missing encryptionKey.")
                    }

                    try Cryptography.decryptAttachment(
                        at: encryptedFileUrl,
                        metadata: EncryptionMetadata(
                            key: encryptionKey,
                            digest: attachmentPointer.digest,
                            plaintextLength: Int(attachmentPointer.byteCount)
                        ),
                        output: originalMediaURL
                    )

                    future.resolve(attachmentStream)
                } catch let error {
                    do {
                        try OWSFileSystem.deleteFileIfExists(url: encryptedFileUrl)
                    } catch let deleteFileError {
                        owsFailDebug("Error: \(deleteFileError).")
                    }
                    future.reject(error)
                }
            }
        }
        return promise
    }

    // MARK: -

    private class func fireProgressNotification(progress: Double, attachmentId: AttachmentId) {
        NotificationCenter.default.postNotificationNameAsync(
            TSResourceDownloads.attachmentDownloadProgressNotification,
            object: nil,
            userInfo: [
                TSResourceDownloads.attachmentDownloadProgressKey: NSNumber(value: progress),
                TSResourceDownloads.attachmentDownloadAttachmentIDKey: TSResourceId.legacy(uniqueId: attachmentId)
            ])
    }

    // MARK: - Fetching

    static func enumerateMessagesWithLegacyAttachments(
        inThreadUniqueId threadUniqueId: String,
        transaction: SDSAnyReadTransaction,
        block: (TSMessage, inout Bool) -> Void
    ) throws {
        let emptyArraySerializedData = try! NSKeyedArchiver.archivedData(withRootObject: [String](), requiringSecureCoding: true)

        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .attachmentIds) IS NOT NULL
            AND \(interactionColumn: .attachmentIds) != ?
        """
        let arguments: StatementArguments = [threadUniqueId, emptyArraySerializedData]
        let cursor = TSInteraction.grdbFetchCursor(
            sql: sql,
            arguments: arguments,
            transaction: transaction.unwrapGrdbRead
        )

        while let interaction = try cursor.next() {
            var stop: Bool = false

            guard let message = interaction as? TSMessage else {
                owsFailDebug("Interaction has unexpected type: \(type(of: interaction))")
                continue
            }

            // NOTE: this doesn't actually do a db lookup on TSAttachment.
            // Attachment (once it exists) will not use this method; this is used
            // for orphan data cleanup which will take just a completely different
            // form with Attachment, this message enumeration will be obsolete.
            guard message.hasBodyAttachments(transaction: transaction) else {
                owsFailDebug("message unexpectedly has no attachments")
                continue
            }

            block(message, &stop)

            if stop {
                return
            }
        }
    }
}
