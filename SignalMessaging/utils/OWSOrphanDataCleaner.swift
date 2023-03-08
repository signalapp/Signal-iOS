//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

extension OWSOrphanDataCleaner {
    @objc
    static func auditOnLaunchIfNecessary() {
        AssertIsOnMainThread()

        guard shouldAuditWithSneakyTransaction() else { return }

        // If we want to be cautious, we can disable orphan deletion using
        // flag - the cleanup will just be a dry run with logging.
        let shouldCleanUp = true
        auditAndCleanup(shouldCleanUp)
    }

    private static func shouldAuditWithSneakyTransaction() -> Bool {
        guard CurrentAppContext().isMainApp else {
            Logger.info("Orphan data audit skipped because we're not the main app")
            return false
        }

        guard !CurrentAppContext().isRunningTests else {
            Logger.info("Orphan data audit skipped because we're running tests")
            return false
        }

        let kvs = keyValueStore()
        let currentAppVersion = appVersion.currentAppReleaseVersion

        return databaseStorage.read { transaction -> Bool in
            guard TSAccountManager.shared.isRegistered(transaction: transaction) else {
                Logger.info("Orphan data audit skipped because we're not registered")
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
                Logger.info("Performing orphan data cleanup because we're on a different app version (\(currentAppVersion)")
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
            if hasEnoughTimePassed(lastCleaningDate) {
                Logger.info("Performing orphan data cleanup because enough time has passed")
                return true
            }

            Logger.info("Orphan data audit skipped because no other checks succeeded")
            return false
        }
    }

    @objc
    static func findJobRecordAttachmentIds(transaction: SDSAnyReadTransaction) -> [String]? {
        var attachmentIds = [String]()
        var shouldAbort = false

        func findAttachmentIds<JobRecordType: SSKJobRecord>(
            label: String,
            transaction: SDSAnyReadTransaction,
            jobRecordAttachmentIds: (JobRecordType) -> some Sequence<String>
        ) {
            do {
                try AnyJobRecordFinder<JobRecordType>().enumerateJobRecords(
                    label: label,
                    transaction: transaction,
                    block: { jobRecord, stop in
                        guard isMainAppAndActive() else {
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
            label: MessageSenderJobQueue.jobRecordLabel,
            transaction: transaction,
            jobRecordAttachmentIds: { (jobRecord: SSKMessageSenderJobRecord) in
                fetchMessage(for: jobRecord, transaction: transaction)?.allAttachmentIds() ?? []
            }
        )

        if shouldAbort {
            return nil
        }

        findAttachmentIds(
            label: OWSBroadcastMediaMessageJobRecord.defaultLabel,
            transaction: transaction,
            jobRecordAttachmentIds: { (jobRecord: OWSBroadcastMediaMessageJobRecord) in jobRecord.attachmentIdMap.keys }
        )

        if shouldAbort {
            return nil
        }

        findAttachmentIds(
            label: OWSIncomingGroupSyncJobRecord.defaultLabel,
            transaction: transaction,
            jobRecordAttachmentIds: { (jobRecord: OWSIncomingGroupSyncJobRecord) in [jobRecord.attachmentId] }
        )

        if shouldAbort {
            return nil
        }

        findAttachmentIds(
            label: OWSIncomingContactSyncJobRecord.defaultLabel,
            transaction: transaction,
            jobRecordAttachmentIds: { (jobRecord: OWSIncomingContactSyncJobRecord) in [jobRecord.attachmentId] }
        )

        if shouldAbort {
            return nil
        }

        return attachmentIds
    }

    private static func fetchMessage(
        for jobRecord: SSKMessageSenderJobRecord,
        transaction: SDSAnyReadTransaction
    ) -> TSMessage? {
        if let invisibleMessage = jobRecord.invisibleMessage {
            return invisibleMessage
        }

        let fetchMessageForMessageId: () -> TSMessage? = {
            guard let messageId = jobRecord.messageId else {
                return nil
            }
            guard let interaction = TSInteraction.anyFetch(uniqueId: messageId, transaction: transaction) else {
                // Interaction may have been deleted.
                Logger.warn("Missing interaction")
                return nil
            }
            return interaction as? TSMessage
        }
        if let fetchedMessage = fetchMessageForMessageId() {
            return fetchedMessage
        }

        return nil
    }

    // MARK: - Find

    /// Finds paths in `baseUrl` not present in `fetchExpectedRelativePaths()`.
    private static func findOrphanedPaths(
        baseUrl: URL,
        fetchExpectedRelativePaths: (SDSAnyReadTransaction) -> Set<String>
    ) -> Set<String> {
        let basePath = VoiceMessageInterruptedDraftStore.draftVoiceMessageDirectory.path

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
        } catch {
            Logger.warn("Couldn't find any voice message drafts \(error.shortDescription)")
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

    // MARK: - Remove

    @objc
    static func removeOrphanedFileAndDirectoryPaths(_ fileAndDirectoryPaths: Set<String>) -> Bool {
        var successCount = 0
        var errorCount = 0
        // Sort by longest path to shortest path so that we remove files before we
        // try to remove the directories that contain them.
        for fileOrDirectoryPath in fileAndDirectoryPaths.sorted(by: { $0.count < $1.count }).reversed() {
            if !self.isMainAppAndActive() {
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
}
