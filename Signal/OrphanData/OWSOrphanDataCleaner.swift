//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

private enum Constants {
    static let lastCleaningVersionKey = "OWSOrphanDataCleaner_LastCleaningVersionKey"
    static let lastCleaningDateKey = "OWSOrphanDataCleaner_LastCleaningDateKey"
}

private struct OWSOrphanData {
    let interactionIds: Set<String>
    let filePaths: Set<String>
    let reactionIds: Set<String>
    let mentionIds: Set<String>
    let fileAndDirectoryPaths: Set<String>
    let hasOrphanedPacksOrStickers: Bool
}
private typealias OrphanDataBlock = (_ orphanData: OWSOrphanData) -> Void

// Notes:
//
// * On disk, we only bother cleaning up files, not directories.
enum OWSOrphanDataCleaner {

    /// Unlike CurrentAppContext().isMainAppAndActive, this method can be safely
    /// invoked off the main thread.
    private static var isMainAppAndActive: Bool {
        CurrentAppContext().reportedApplicationState == .active
    }
    private static let databaseStorage = SSKEnvironment.shared.databaseStorageRef
    private static let keyValueStore = KeyValueStore(collection: "OWSOrphanDataCleaner_Collection")

    /// We use the lowest priority possible.
    private static let workQueue = DispatchQueue.global(qos: .background)

    static func auditOnLaunchIfNecessary() {
        AssertIsOnMainThread()

        guard shouldAuditWithSneakyTransaction() else { return }

        // If we want to be cautious, we can disable orphan deletion using
        // flag - the cleanup will just be a dry run with logging.
        let shouldCleanUp = true
        auditAndCleanup(shouldCleanUp)
    }

    /// This is exposed for the debug UI and tests.
    static func auditAndCleanup(_ shouldRemoveOrphans: Bool, completion: (() -> Void)? = nil) {
        AssertIsOnMainThread()

        guard CurrentAppContext().isMainApp else {
            owsFailDebug("can't audit orphan data in app extensions.")
            return
        }

        Logger.info("Starting orphan data \(shouldRemoveOrphans ? "cleanup" : "audit")")

        // Orphan cleanup has two risks:
        //
        // * As a long-running process that involves access to the
        //   shared data container, it could cause 0xdead10cc.
        // * It could accidentally delete data still in use,
        //   e.g. a profile avatar which has been saved to disk
        //   but whose OWSUserProfile hasn't been saved yet.
        //
        // To prevent 0xdead10cc, the cleaner continually checks
        // whether the app has resigned active.  If so, it aborts.
        // Each phase (search, re-search, processing) retries N times,
        // then gives up until the next app launch.
        //
        // To prevent accidental data deletion, we take the following
        // measures:
        //
        // * Only cleanup data of the following types (which should
        //   include all relevant app data): profile avatar,
        //   attachment, temporary files (including temporary
        //   attachments).
        // * We don't delete any data created more recently than N seconds
        //   _before_ when the app launched.  This prevents any stray data
        //   currently in use by the app from being accidentally cleaned
        //   up.
        let maxRetries = 3
        findOrphanData(withRetries: maxRetries) { orphanData in
            processOrphans(orphanData,
                           remainingRetries: maxRetries,
                           shouldRemoveOrphans: shouldRemoveOrphans) {
                Logger.info("Completed orphan data cleanup.")

                databaseStorage.write { transaction in
                    keyValueStore.setString(AppVersionImpl.shared.currentAppVersion,
                                            key: Constants.lastCleaningVersionKey,
                                            transaction: transaction.asV2Write)
                    keyValueStore.setDate(Date(),
                                          key: Constants.lastCleaningDateKey,
                                          transaction: transaction.asV2Write)
                }

                completion?()
            } failure: {
                Logger.info("Aborting orphan data cleanup.")
                completion?()
            }
        } failure: {
            Logger.info("Aborting orphan data cleanup.")
            completion?()
        }
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
                Constants.lastCleaningVersionKey,
                transaction: transaction.asV2Read
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
                Constants.lastCleaningDateKey,
                transaction: transaction.asV2Read
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

    /// This method finds but does not delete orphan data.
    ///
    /// The follow items are considered orphan data:
    /// * Orphan `TSInteraction`s (with no thread).
    /// * Orphan profile avatars.
    /// * Temporary files (all).
    private static func findOrphanData(withRetries remainingRetries: Int,
                                       success: @escaping OrphanDataBlock,
                                       failure: @escaping () -> Void) {
        guard remainingRetries > 0 else {
            Logger.info("Aborting orphan data search. No more retries.")
            workQueue.async(failure)
            return
        }

        Logger.info("Enqueuing an orphan data search. Remaining retries: \(remainingRetries)")

        // Wait until the app is active...
        CurrentAppContext().runNowOrWhenMainAppIsActive {
            // ...but perform the work off the main thread.
            let backgroundTask = OWSBackgroundTask(label: #function)
            workQueue.async {
                if let orphanData = findOrphanDataSync() {
                    success(orphanData)
                } else {
                    findOrphanData(withRetries: remainingRetries - 1, success: success, failure: failure)
                }
                backgroundTask.end()
            }
        }
    }

    /// Returns `nil` on failure, usually indicating that the search
    /// aborted due to the app resigning active. This method is extremely careful to
    /// abort if the app resigns active, in order to avoid `0xdead10cc` crashes.
    private static func findOrphanDataSync() -> OWSOrphanData? {
        var shouldAbort = false

        let legacyProfileAvatarsDirPath = OWSUserProfile.legacyProfileAvatarsDirPath
        let sharedDataProfileAvatarsDirPath = OWSUserProfile.sharedDataProfileAvatarsDirPath
        guard let legacyProfileAvatarsFilePaths = filePaths(inDirectorySafe: legacyProfileAvatarsDirPath), isMainAppAndActive else {
            return nil
        }
        guard let sharedDataProfileAvatarFilePaths = filePaths(inDirectorySafe: sharedDataProfileAvatarsDirPath), isMainAppAndActive else {
            return nil
        }

        guard let allGroupAvatarFilePaths = filePaths(inDirectorySafe: TSGroupModel.avatarsDirectory.path), isMainAppAndActive else {
            return nil
        }

        let stickersDirPath = StickerManager.cacheDirUrl().path
        guard let allStickerFilePaths = filePaths(inDirectorySafe: stickersDirPath), isMainAppAndActive else {
            return nil
        }

        let allOnDiskFilePaths: Set<String> = {
            var result: Set<String> = []
            result.formUnion(legacyProfileAvatarsFilePaths)
            result.formUnion(sharedDataProfileAvatarFilePaths)
            result.formUnion(allGroupAvatarFilePaths)
            result.formUnion(allStickerFilePaths)
            // TODO: Badges?

            // This should be redundant, but this will future-proof us against
            // ever accidentally removing the GRDB databases during
            // orphan clean up.
            let grdbPrimaryDirectoryPath = GRDBDatabaseStorageAdapter.databaseDirUrl(directoryMode: .primary).path
            let grdbHotswapDirectoryPath = GRDBDatabaseStorageAdapter.databaseDirUrl(directoryMode: .hotswapLegacy).path
            let grdbTransferDirectoryPath: String?
            if GRDBDatabaseStorageAdapter.hasAssignedTransferDirectory && TSAccountManagerObjcBridge.isTransferInProgressWithMaybeTransaction {
                grdbTransferDirectoryPath = GRDBDatabaseStorageAdapter.databaseDirUrl(directoryMode: .transfer).path
            } else {
                grdbTransferDirectoryPath = nil
            }

            let databaseFilePaths: Set<String> = {
                var filePathsToSubtract: Set<String> = []
                for filePath in result {
                    if filePath.hasPrefix(grdbPrimaryDirectoryPath) {
                        Logger.info("Protecting database file: \(filePath)")
                        filePathsToSubtract.insert(filePath)
                    } else if filePath.hasPrefix(grdbHotswapDirectoryPath) {
                        Logger.info("Protecting database hotswap file: \(filePath)")
                        filePathsToSubtract.insert(filePath)
                    } else if let grdbTransferDirectoryPath, filePath.hasPrefix(grdbTransferDirectoryPath) {
                        Logger.info("Protecting database hotswap file: \(filePath)")
                        filePathsToSubtract.insert(filePath)
                    }
                }
                return filePathsToSubtract
            }()
            result.subtract(databaseFilePaths)

            return result
        }()

        let profileAvatarFilePaths: Set<String> = {
            var result: Set<String> = []
            databaseStorage.read { transaction in
                result = OWSProfileManager.allProfileAvatarFilePaths(transaction: transaction)
            }
            return result
        }()

        guard let groupAvatarFilePaths = {
            do {
                var result: Set<String> = []
                try databaseStorage.read { transaction in
                    result = try TSGroupModel.allGroupAvatarFilePaths(transaction: transaction)
                }
                return result
            } catch {
                owsFailDebug("Failed to query group avatar file paths \(error)")
                return nil
            }
        }() else {
            return nil
        }

        guard isMainAppAndActive else {
            return nil
        }

        let voiceMessageDraftOrphanedPaths = findOrphanedVoiceMessageDraftPaths()

        guard isMainAppAndActive else {
            return nil
        }

        guard isMainAppAndActive else {
            return nil
        }

        var allReactionIds: Set<String> = []
        var allMentionIds: Set<String> = []
        var orphanInteractionIds: Set<String> = []
        var allMessageReactionIds: Set<String> = []
        var allMessageMentionIds: Set<String> = []
        var activeStickerFilePaths: Set<String> = []
        var hasOrphanedPacksOrStickers = false
        databaseStorage.read { transaction in
            let threadIds: Set<String> = Set(TSThread.anyAllUniqueIds(transaction: transaction))

            var allInteractionIds: Set<String> = []
            TSInteraction.anyEnumerate(transaction: transaction, batched: true) { interaction, stop in
                guard isMainAppAndActive else {
                    shouldAbort = true
                    stop.pointee = true
                    return
                }
                if interaction.uniqueThreadId.isEmpty || !threadIds.contains(interaction.uniqueThreadId) {
                    orphanInteractionIds.insert(interaction.uniqueId)
                }

                allInteractionIds.insert(interaction.uniqueId)
            }

            if shouldAbort {
                return
            }

            OWSReaction.anyEnumerate(transaction: transaction, batchingPreference: .batched()) { reaction, stop in
                guard isMainAppAndActive else {
                    shouldAbort = true
                    stop.pointee = true
                    return
                }
                allReactionIds.insert(reaction.uniqueId)
                if allInteractionIds.contains(reaction.uniqueMessageId) {
                    allMessageReactionIds.insert(reaction.uniqueId)
                }
            }

            if shouldAbort {
                return
            }

            TSMention.anyEnumerate(transaction: transaction, batchingPreference: .batched()) { mention, stop in
                guard isMainAppAndActive else {
                    shouldAbort = true
                    stop.pointee = true
                    return
                }
                allMentionIds.insert(mention.uniqueId)
                if allInteractionIds.contains(mention.uniqueMessageId) {
                    allMessageMentionIds.insert(mention.uniqueId)
                }
            }

            if shouldAbort {
                return
            }

            activeStickerFilePaths.formUnion(StickerManager.filePathsForAllInstalledStickers(transaction: transaction))

            hasOrphanedPacksOrStickers = StickerManager.hasOrphanedData(tx: transaction)
        }
        if shouldAbort {
            return nil
        }

        var orphanFilePaths = allOnDiskFilePaths
        orphanFilePaths.subtract(profileAvatarFilePaths)
        orphanFilePaths.subtract(groupAvatarFilePaths)
        orphanFilePaths.subtract(activeStickerFilePaths)

        var orphanReactionIds = allReactionIds
        orphanReactionIds.subtract(allMessageReactionIds)
        var missingReactionIds = allMessageReactionIds
        missingReactionIds.subtract(allReactionIds)

        var orphanMentionIds = allMentionIds
        orphanMentionIds.subtract(allMessageMentionIds)
        var missingMentionIds = allMessageMentionIds
        missingMentionIds.subtract(allMentionIds)

        var orphanFileAndDirectoryPaths: Set<String> = []
        orphanFileAndDirectoryPaths.formUnion(voiceMessageDraftOrphanedPaths)

        return OWSOrphanData(interactionIds: orphanInteractionIds,
                             filePaths: orphanFilePaths,
                             reactionIds: orphanReactionIds,
                             mentionIds: orphanMentionIds,
                             fileAndDirectoryPaths: orphanFileAndDirectoryPaths,
                             hasOrphanedPacksOrStickers: hasOrphanedPacksOrStickers)
    }

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

    private static func findOrphanedVoiceMessageDraftPaths() -> Set<String> {
        findOrphanedPaths(
            baseUrl: VoiceMessageInterruptedDraftStore.draftVoiceMessageDirectory,
            fetchExpectedRelativePaths: {
                VoiceMessageInterruptedDraftStore.allDraftFilePaths(transaction: $0)
            }
        )
    }

    // MARK: - Remove

    /// Calls `failure` on exhausting all remaining retries, usually indicating that
    /// orphan processing aborted due to the app resigning active. This method is
    /// extremely careful to abort if the app resigns active, in order to avoid
    /// `0xdead10cc` crashes.
    private static func processOrphans(_ orphanData: OWSOrphanData,
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
        CurrentAppContext().runNowOrWhenMainAppIsActive {
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
        }
    }

    /// Returns `false` on failure, usually indicating that orphan processing
    /// aborted due to the app resigning active.  This method is extremely careful to
    /// abort if the app resigns active, in order to avoid `0xdead10cc` crashes.
    private static func processOrphansSync(_ orphanData: OWSOrphanData, shouldRemoveOrphans: Bool) -> Bool {
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
                let creationDate = Date(millisecondsSince1970: interaction.timestamp)
                guard creationDate <= thresholdDate else {
                    Logger.info("Skipping orphan interaction due to age: \(creationDate.timeIntervalSinceNow)")
                    continue
                }
                Logger.info("Removing orphan message: \(interaction.uniqueId)")
                interactionsRemoved += 1
                guard shouldRemoveOrphans else {
                    continue
                }
                DependenciesBridge.shared.interactionDeleteManager
                    .delete(interaction, sideEffects: .default(), tx: transaction.asV2Write)
            }
            Logger.info("Deleted orphan interactions: \(interactionsRemoved)")

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

    private static func filePaths(inDirectorySafe dirPath: String) -> Set<String>? {
        guard FileManager.default.fileExists(atPath: dirPath) else {
            return []
        }
        do {
            var result: Set<String> = []
            let fileNames = try FileManager.default.contentsOfDirectory(atPath: dirPath)
            for fileName in fileNames {
                guard isMainAppAndActive else {
                    return nil
                }
                let filePath = dirPath.appendingPathComponent(fileName)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        guard let dirPaths = filePaths(inDirectorySafe: filePath) else {
                            return nil
                        }
                        result.formUnion(dirPaths)
                    } else {
                        result.insert(filePath)
                    }
                }
            }
            return result
        } catch {
            switch error {
            case POSIXError.ENOENT, CocoaError.fileReadNoSuchFile:
                // Races may cause files to be removed while we crawl the directory contents.
                Logger.warn("Error: \(error)")
            default:
                owsFailDebug("Error: \(error)")
            }
            return []
        }
    }
}
