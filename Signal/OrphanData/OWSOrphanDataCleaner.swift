//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalServiceKit
import SignalUI

// TODO: Convert to struct after all code is swift.
@objcMembers
class OWSOrphanData: NSObject {
    let interactionIds: Set<String>
    let attachmentIds: Set<String>
    let filePaths: Set<String>
    let reactionIds: Set<String>
    let mentionIds: Set<String>
    let fileAndDirectoryPaths: Set<String>
    let hasOrphanedPacksOrStickers: Bool

    init(interactionIds: Set<String>,
         attachmentIds: Set<String>,
         filePaths: Set<String>,
         reactionIds: Set<String>,
         mentionIds: Set<String>,
         fileAndDirectoryPaths: Set<String>,
         hasOrphanedPacksOrStickers: Bool) {
        self.interactionIds = interactionIds
        self.attachmentIds = attachmentIds
        self.filePaths = filePaths
        self.reactionIds = reactionIds
        self.mentionIds = mentionIds
        self.fileAndDirectoryPaths = fileAndDirectoryPaths
        self.hasOrphanedPacksOrStickers = hasOrphanedPacksOrStickers
    }
}
private typealias OrphanDataBlock = (_ orphanData: OWSOrphanData) -> ()

extension OWSOrphanDataCleaner {

    /// Unlike CurrentAppContext().isMainAppAndActive, this method can be safely
    /// invoked off the main thread.
    @objc static var isMainAppAndActive: Bool {
        CurrentAppContext().reportedApplicationState == .active
    }

    @objc static let keyValueStore = SDSKeyValueStore(collection: "OWSOrphanDataCleaner_Collection")

    /// We use the lowest priority possible.
    @objc static let workQueue = DispatchQueue.global(qos: .background)

    static func auditOnLaunchIfNecessary() {
        AssertIsOnMainThread()

        guard shouldAuditWithSneakyTransaction() else { return }

        // If we want to be cautious, we can disable orphan deletion using
        // flag - the cleanup will just be a dry run with logging.
        let shouldCleanUp = true
        auditAndCleanup(shouldCleanUp)
    }

    private static func shouldAuditWithSneakyTransaction() -> Bool {
        let kvs = keyValueStore
        let currentAppVersion = AppVersionImpl.shared.currentAppVersion

        return databaseStorage.read { transaction -> Bool in
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard tsAccountManager.registrationState(tx: transaction.asV2Read).isRegistered else {
                return false
            }

            let lastCleaningVersion = kvs.getString(
                OWSOrphanDataCleaner_LastCleaningVersionKey,
                transaction: transaction
            )
            guard let lastCleaningVersion else {
                Logger.info("Performing orphan data cleanup because we've never done it")
                return true
            }
            guard lastCleaningVersion == currentAppVersion else {
                Logger.info("Performing orphan data cleanup because we're on a different app version")
                return true
            }

            let lastCleaningDate = kvs.getDate(
                OWSOrphanDataCleaner_LastCleaningDateKey,
                transaction: transaction
            )
            guard let lastCleaningDate else {
                owsFailDebug("We have a \"last cleaned version\". Why don't we have a last cleaned date?")
                Logger.info("Performing orphan data cleanup because we've never done it")
                return true
            }

            #if DEBUG
            let hasEnoughTimePassed = DateUtil.dateIsOlderThanToday
            #else
            let hasEnoughTimePassed = DateUtil.dateIsOlderThanOneWeek
            #endif
            if hasEnoughTimePassed(lastCleaningDate, nil) {
                Logger.info("Performing orphan data cleanup because enough time has passed")
                return true
            }

            return false
        }
    }

    @objc
    static func findJobRecordAttachmentIds(transaction: SDSAnyReadTransaction) -> [String]? {
        var attachmentIds = [String]()
        var shouldAbort = false

        func findAttachmentIds<JobRecordType: JobRecord>(
            transaction: SDSAnyReadTransaction,
            jobRecordAttachmentIds: (JobRecordType) -> some Sequence<String>
        ) {
            do {
                try JobRecordFinderImpl<JobRecordType>(db: DependenciesBridge.shared.db).enumerateJobRecords(
                    transaction: transaction.asV2Read,
                    block: { jobRecord, stop in
                        guard isMainAppAndActive else {
                            shouldAbort = true
                            stop = true
                            return
                        }
                        attachmentIds.append(contentsOf: jobRecordAttachmentIds(jobRecord))
                    }
                )
            } catch {
                Logger.warn("Couldn't enumerate job records: \(error)")
            }
        }

        findAttachmentIds(
            transaction: transaction,
            jobRecordAttachmentIds: { (jobRecord: MessageSenderJobRecord) -> [String] in
                guard let message = fetchMessage(for: jobRecord, transaction: transaction) else {
                    return []
                }
                return Self.legacyAttachmentUniqueIds(message)
            }
        )

        if shouldAbort {
            return nil
        }

        findAttachmentIds(
            transaction: transaction,
            jobRecordAttachmentIds: { (jobRecord: TSAttachmentMultisendJobRecord) in jobRecord.attachmentIdMap.keys }
        )

        if shouldAbort {
            return nil
        }

        findAttachmentIds(
            transaction: transaction,
            jobRecordAttachmentIds: { (jobRecord: IncomingGroupSyncJobRecord) in [jobRecord.legacyAttachmentId].compacted() }
        )

        if shouldAbort {
            return nil
        }

        findAttachmentIds(
            transaction: transaction,
            jobRecordAttachmentIds: { (jobRecord: IncomingContactSyncJobRecord) -> [String] in
                switch jobRecord.downloadInfo {
                case .invalid, .transient:
                    return []
                case .legacy(let attachmentId):
                    return [attachmentId]
                }
            }
        )

        if shouldAbort {
            return nil
        }

        return attachmentIds
    }

    private static func fetchMessage(
        for jobRecord: MessageSenderJobRecord,
        transaction: SDSAnyReadTransaction
    ) -> TSMessage? {
        switch jobRecord.messageType {
        case .none:
            return nil
        case .transient(let message):
            return message
        case .persisted(let messageId, _), .editMessage(let messageId, _, _):
            guard let interaction = TSInteraction.anyFetch(uniqueId: messageId, transaction: transaction) else {
                // Interaction may have been deleted.
                Logger.warn("Missing interaction")
                return nil
            }
            return interaction as? TSMessage
        }
    }

    // MARK: - Find

    /// Finds paths in `baseUrl` not present in `fetchExpectedRelativePaths()`.
    private static func findOrphanedPaths(
        baseUrl: URL,
        fetchExpectedRelativePaths: (SDSAnyReadTransaction) -> Set<String>
    ) -> Set<String> {
        let basePath = baseUrl.path

        // The ordering within this method is important. First, we search the file
        // system for files that already exist. Next, we ensure that any pending
        // database write operations have finished. This ensures that any files
        // written as part of a database transaction are visible to our read
        // transaction. If we skip the write transaction, we may treat just-created
        // files as orphaned and remove them. If a new write transaction is opened
        // after the one in this method, we won't treat any files it creates as
        // orphaned since we've already finished searching the file system.
        // Finally, we consult the database to see which files should exist.

        let actualRelativePaths: [String]
        do {
            actualRelativePaths = try FileManager.default.subpathsOfDirectory(atPath: basePath)
        } catch CocoaError.fileReadNoSuchFile {
            actualRelativePaths = []
        } catch {
            Logger.warn("Orphan data cleaner couldn't find any paths \(error.shortDescription)")
            actualRelativePaths = []
        }

        if actualRelativePaths.isEmpty {
            return []
        }

        databaseStorage.write { _ in }
        var expectedRelativePaths = databaseStorage.read { fetchExpectedRelativePaths($0) }

        // Mark the directories that contain these files as expected as well. This
        // avoids redundant `rmdir` calls to check if the directories are empty.
        while true {
            let oldCount = expectedRelativePaths.count
            expectedRelativePaths.formUnion(expectedRelativePaths.lazy.map {
                ($0 as NSString).deletingLastPathComponent
            })
            let newCount = expectedRelativePaths.count
            if oldCount == newCount {
                break
            }
        }

        let orphanedRelativePaths = Set(actualRelativePaths).subtracting(expectedRelativePaths)
        return Set(orphanedRelativePaths.lazy.map { basePath.appendingPathComponent($0) })
    }

    @objc
    static func findOrphanedVoiceMessageDraftPaths() -> Set<String> {
        findOrphanedPaths(
            baseUrl: VoiceMessageInterruptedDraftStore.draftVoiceMessageDirectory,
            fetchExpectedRelativePaths: {
                VoiceMessageInterruptedDraftStore.allDraftFilePaths(transaction: $0)
            }
        )
    }

    @objc
    static func findOrphanedWallpaperPaths() -> Set<String> {
        findOrphanedPaths(
            baseUrl: DependenciesBridge.shared.wallpaperStore.customPhotoDirectory,
            fetchExpectedRelativePaths: { Wallpaper.allCustomPhotoRelativePaths(tx: $0.asV2Read) }
        )
    }

    // MARK: - Remove

    /// Calls `failure` on exhausting all remaining retries, usually indicating that
    /// orphan processing aborted due to the app resigning active. This method is
    /// extremely careful to abort if the app resigns active, in order to avoid
    /// `0xdead10cc` crashes.
    @objc
    static func processOrphans(_ orphanData: OWSOrphanData,
                               remainingRetries: Int,
                               shouldRemoveOrphans: Bool,
                               success: @escaping () -> Void,
                               failure: @escaping () -> Void) {
        guard remainingRetries > 0 else {
            Logger.info("Aborting orphan data audit.")
            workQueue.async(failure)
            return
        }

        // Wait until the app is active...
        CurrentAppContext().runNowOr(whenMainAppIsActive: {
            // ...but perform the work off the main thread.
            let backgroundTask = OWSBackgroundTask(label: #function)
            workQueue.async {
                let result = processOrphansSync(orphanData, shouldRemoveOrphans: shouldRemoveOrphans)
                if result {
                    success()
                } else {
                    processOrphans(orphanData,
                                   remainingRetries: remainingRetries - 1,
                                   shouldRemoveOrphans: shouldRemoveOrphans,
                                   success: success,
                                   failure: failure)
                }
                backgroundTask.end()
            }
        })
    }

    /// Returns `false` on failure, usually indicating that orphan processing
    /// aborted due to the app resigning active.  This method is extremely careful to
    /// abort if the app resigns active, in order to avoid `0xdead10cc` crashes.
    @objc
    static func processOrphansSync(_ orphanData: OWSOrphanData, shouldRemoveOrphans: Bool) -> Bool {
        guard isMainAppAndActive else {
            return false
        }

        var shouldAbort = false

        // We need to avoid cleaning up new files that are still in the process of
        // being created/written, so we don't clean up anything recent.
        let minimumOrphanAgeSeconds: TimeInterval = CurrentAppContext().isRunningTests ? 0 : 15 * kMinuteInterval
        let appLaunchTime = CurrentAppContext().appLaunchTime
        let thresholdTimestamp = appLaunchTime.timeIntervalSince1970 - minimumOrphanAgeSeconds
        let thresholdDate = Date(timeIntervalSince1970: thresholdTimestamp)
        databaseStorage.write { transaction in
            var interactionsRemoved: UInt = 0
            for interactionId in orphanData.interactionIds {
                guard isMainAppAndActive else {
                    shouldAbort = true
                    return
                }
                guard let interaction = TSInteraction.anyFetch(uniqueId: interactionId, transaction: transaction) else {
                    // This could just be a race condition, but it should be very unlikely.
                    Logger.warn("Could not load interaction: \(interactionId)")
                    continue
                }
                // Don't delete interactions which were created in the last N minutes.
                let creationDate = NSDate.ows_date(withMillisecondsSince1970: interaction.timestamp) as Date
                guard creationDate <= thresholdDate else {
                    Logger.info("Skipping orphan interaction due to age: \(creationDate.timeIntervalSinceNow)")
                    continue
                }
                Logger.info("Removing orphan message: \(interaction.uniqueId)")
                interactionsRemoved += 1
                guard shouldRemoveOrphans else {
                    continue
                }
                interaction.anyRemove(transaction: transaction)
            }
            Logger.info("Deleted orphan interactions: \(interactionsRemoved)")

            var attachmentsRemoved: UInt = 0
            for attachmentId in orphanData.attachmentIds {
                guard isMainAppAndActive else {
                    shouldAbort = true
                    return
                }
                guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) else {
                    // This can happen on launch since we sync contacts/groups, especially if you have a lot of attachments
                    // to churn through, it's likely it's been deleted since starting this job.
                    Logger.warn("Could not load attachment: \(attachmentId)")
                    continue
                }
                guard let attachmentStream = attachment as? TSAttachmentStream else {
                    continue
                }
                // Don't delete attachments which were created in the last N minutes.
                let creationDate = attachmentStream.creationTimestamp
                guard creationDate <= thresholdDate else {
                    Logger.info("Skipping orphan attachment due to age: \(creationDate.timeIntervalSinceNow)")
                    continue
                }
                Logger.info("Removing orphan attachmentStream: \(attachmentStream.uniqueId)")
                attachmentsRemoved += 1
                guard shouldRemoveOrphans else {
                    continue
                }
                attachmentStream.anyRemove(transaction: transaction)
            }
            Logger.info("Deleted orphan attachments: \(attachmentsRemoved)")

            var reactionsRemoved: UInt = 0
            for reactionId in orphanData.reactionIds {
                guard isMainAppAndActive else {
                    shouldAbort = true
                    return
                }

                let performedCleanup = ReactionManager.tryToCleanupOrphanedReaction(uniqueId: reactionId,
                                                                                    thresholdDate: thresholdDate,
                                                                                    shouldPerformRemove: shouldRemoveOrphans,
                                                                                    transaction: transaction)
                if performedCleanup {
                    reactionsRemoved += 1
                }
            }
            Logger.info("Deleted orphan reactions: \(reactionsRemoved)")

            var mentionsRemoved: UInt = 0
            for mentionId in orphanData.mentionIds {
                guard isMainAppAndActive else {
                    shouldAbort = true
                    return
                }

                let performedCleanup = MentionFinder.tryToCleanupOrphanedMention(uniqueId: mentionId,
                                                                                 thresholdDate: thresholdDate,
                                                                                 shouldPerformRemove: shouldRemoveOrphans,
                                                                                 transaction: transaction)
                if performedCleanup {
                    mentionsRemoved += 1
                }
            }
            Logger.info("Deleted orphan mentions: \(mentionsRemoved)")

            if orphanData.hasOrphanedPacksOrStickers {
                StickerManager.cleanUpOrphanedData(tx: transaction)
            }
        }

        guard !shouldAbort else {
            return false
        }

        var filesRemoved: UInt = 0
        let filePaths = orphanData.filePaths.sorted()
        for filePath in filePaths {
            guard isMainAppAndActive else {
                return false
            }

            guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath) else {
                // This is fine; the file may have been deleted since we found it.
                Logger.warn("Could not get attributes of file at: \(filePath)")
                continue
            }
            // Don't delete files which were created in the last N minutes.
            if let creationDate = (attributes as NSDictionary).fileModificationDate(), creationDate > thresholdDate {
                Logger.info("Skipping file due to age: \(creationDate.timeIntervalSinceNow)")
                continue
            }
            Logger.info("Deleting file: \(filePath)")
            filesRemoved += 1
            guard shouldRemoveOrphans else {
                continue
            }
            guard OWSFileSystem.fileOrFolderExists(atPath: filePath) else {
                // Already removed.
                continue
            }
            if !OWSFileSystem.deleteFile(filePath, ignoreIfMissing: true) {
                owsFailDebug("Could not remove orphan file")
            }
        }
        Logger.info("Deleted orphan files: \(filesRemoved)")

        if shouldRemoveOrphans {
            guard removeOrphanedFileAndDirectoryPaths(orphanData.fileAndDirectoryPaths) else {
                return false
            }
        }

        return true
    }

    private static func removeOrphanedFileAndDirectoryPaths(_ fileAndDirectoryPaths: Set<String>) -> Bool {
        var successCount = 0
        var errorCount = 0
        // Sort by longest path to shortest path so that we remove files before we
        // try to remove the directories that contain them.
        for fileOrDirectoryPath in fileAndDirectoryPaths.sorted(by: { $0.count < $1.count }).reversed() {
            if !self.isMainAppAndActive {
                return false
            }
            do {
                try removeFileOrEmptyDirectory(at: fileOrDirectoryPath)
                successCount += 1
            } catch {
                owsFailDebug("Couldn't remove file or directory: \(error.shortDescription)")
                errorCount += 1
            }
        }
        Logger.info("Deleted orphaned files/directories [successes: \(successCount), failures: \(errorCount)]")
        return true
    }

    private static func removeFileOrEmptyDirectory(at path: String) throws {
        do {
            // First, remove it if it's a directory.
            try runUnixOperation(rmdir, argument: path)
        } catch POSIXError.ENOENT {
            // It doesn't exist (or a parent directory doesn't exist).
            return
        } catch POSIXError.ENOTEMPTY {
            // It's not empty, so don't delete it.
            return
        } catch POSIXError.ENOTDIR {
            // It's a file.
        } catch {
            Logger.warn("Couldn't remove directory \(error.shortDescription)")
            // Fall through since it seems like this isn't a directory...
        }

        do {
            try runUnixOperation(unlink, argument: path)
        } catch POSIXError.ENOTDIR, POSIXError.ENOENT {
            // The file (or its containing directory) doesn't exist.
            return
        } catch {
            throw error
        }
    }

    private static func runUnixOperation(_ op: (UnsafePointer<CChar>?) -> Int32, argument path: String) throws {
        let result = path.withCString { op($0) }
        if result == 0 {
            return
        }
        if let errorCode = POSIXErrorCode(rawValue: errno) {
            throw POSIXError(errorCode)
        }
        throw OWSGenericError("Operation failed.")
    }

    // MARK: - Helpers

    @objc
    static func legacyAttachmentUniqueIds(_ message: TSMessage) -> [String] {
        let ids = TSAttachmentStore().allAttachmentIds(for: message)
        return Array(ids)
    }

    @objc
    static func legacyAttachmentUniqueId(_ storyMessage: StoryMessage) -> String? {
        switch storyMessage.attachment {
        case .file(let file):
            return file.attachmentId
        case .text(let textAttachment):
            return textAttachment.preview?.legacyImageAttachmentId
        case .foreignReferenceAttachment:
            return nil
        }
    }
}
