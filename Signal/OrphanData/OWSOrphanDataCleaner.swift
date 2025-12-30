//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalServiceKit
import SignalUI

private struct OWSOrphanData {
    let interactionIds: Set<String>
    let filePaths: Set<String>
    let reactionIds: Set<String>
    let mentionIds: Set<String>
    let fileAndDirectoryPaths: Set<String>
    let hasOrphanedPacksOrStickers: Bool
}

// Notes:
//
// * On disk, we only bother cleaning up files, not directories.
enum OWSOrphanDataCleaner {

    private static let databaseStorage = SSKEnvironment.shared.databaseStorageRef

    static func cleanUp(shouldRemoveOrphanedData: Bool) async throws {
        Logger.info("starting orphan data \(shouldRemoveOrphanedData ? "cleanup" : "audit")")

        // Orphaned cleanup has one risk: It could accidentally delete data still
        // in use (e.g., a profile avatar that's been saved to disk but whose
        // OWSUserProfile hasn't yet been saved).
        //
        // To prevent accidental data deletion, we take the following measure:
        //
        // * We don't delete any data created more recently than N seconds before
        // we started cleaning orphaned data. This prevents any stray data
        // currently in use by the app from being accidentally cleaned up.
        let startTime = Date()
        let orphanedData = try await findOrphanedData()
        try await processOrphanedData(
            orphanedData,
            startTime: startTime,
            shouldRemoveOrphanedData: shouldRemoveOrphanedData,
        )
        Logger.info("completed orphaned data cleanup")
    }

    // MARK: - Find

    /// This method finds (but does not delete) orphaned data.
    private static func findOrphanedData() async throws -> OWSOrphanData {
        Logger.info("searching for orphaned data")

        let legacyProfileAvatarsFilePaths = try filePaths(inDirectorySafe: OWSUserProfile.legacyProfileAvatarsDirPath)
        let sharedDataProfileAvatarFilePaths = try filePaths(inDirectorySafe: OWSUserProfile.sharedDataProfileAvatarsDirPath)
        let allGroupAvatarFilePaths = try filePaths(inDirectorySafe: TSGroupModel.avatarsDirectory.path)
        let allStickerFilePaths = try filePaths(inDirectorySafe: StickerManager.cacheDirUrl().path)

        let allOnDiskFilePaths: Set<String> = {
            var result: Set<String> = []
            result.formUnion(legacyProfileAvatarsFilePaths)
            result.formUnion(sharedDataProfileAvatarFilePaths)
            result.formUnion(allGroupAvatarFilePaths)
            result.formUnion(allStickerFilePaths)
            // TODO: Badges?

            // This should be redundant, but this will future-proof us against ever
            // accidentally removing the GRDB databases during orphan clean up.
            let grdbPrimaryDirectoryPath = GRDBDatabaseStorageAdapter.databaseDirUrl(directoryMode: .primary).path
            let grdbHotswapDirectoryPath = GRDBDatabaseStorageAdapter.databaseDirUrl(directoryMode: .hotswapLegacy).path
            let grdbTransferDirectoryPath: String?
            if GRDBDatabaseStorageAdapter.hasAssignedTransferDirectory, TSAccountManagerObjcBridge.isTransferInProgressWithMaybeTransaction {
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

        let profileAvatarFilePaths = databaseStorage.read { tx in
            return OWSProfileManager.allProfileAvatarFilePaths(transaction: tx)
        }

        try Task.checkCancellation()

        let groupAvatarFilePaths: Set<String>
        do {
            groupAvatarFilePaths = try databaseStorage.read { tx in
                return try TSGroupModel.allGroupAvatarFilePaths(transaction: tx)
            }
        } catch {
            owsFailDebug("failed to query group avatar file paths: \(error)")
            throw error
        }

        try Task.checkCancellation()

        let voiceMessageDraftOrphanedPaths = await findOrphanedVoiceMessageDraftPaths()

        try Task.checkCancellation()

        var orphanInteractionIds: Set<String> = []
        var orphanReactionIds: Set<String> = []
        var orphanMentionIds: Set<String> = []
        var activeStickerFilePaths: Set<String> = []
        var hasOrphanedPacksOrStickers = false
        try databaseStorage.read { transaction in
            let threadIds: Set<String> = Set(ThreadFinder().fetchUniqueIds(tx: transaction))

            var allInteractionIds: Set<String> = []
            do {
                let fetchCursor = try Row.fetchCursor(
                    transaction.database,
                    sql: "SELECT \(interactionColumn: .threadUniqueId), \(interactionColumn: .uniqueId) FROM \(InteractionRecord.databaseTableName)",
                )
                while let row = try fetchCursor.next() {
                    let threadUniqueId = row[0] as String
                    let uniqueId = row[1] as String
                    try Task.checkCancellation()
                    if threadUniqueId.isEmpty || !threadIds.contains(threadUniqueId) {
                        orphanInteractionIds.insert(uniqueId)
                    }
                    allInteractionIds.insert(uniqueId)
                }
            } catch let error as CancellationError {
                throw error
            } catch {
                owsFailDebug("Couldn't enumerate TSInteractions: \(error.grdbErrorForLogging)")
                throw error.grdbErrorForLogging
            }

            OWSReaction.anyEnumerate(transaction: transaction, batchingPreference: .batched()) { reaction, stop in
                if Task.isCancelled {
                    stop.pointee = true
                    return
                }
                if !allInteractionIds.contains(reaction.uniqueMessageId) {
                    orphanReactionIds.insert(reaction.uniqueId)
                }
            }
            try Task.checkCancellation()

            TSMention.anyEnumerate(transaction: transaction, batchingPreference: .batched()) { mention, stop in
                if Task.isCancelled {
                    stop.pointee = true
                    return
                }
                if !allInteractionIds.contains(mention.uniqueMessageId) {
                    orphanMentionIds.insert(mention.uniqueId)
                }
            }
            try Task.checkCancellation()

            activeStickerFilePaths.formUnion(StickerManager.filePathsForAllInstalledStickers(transaction: transaction))
            try Task.checkCancellation()

            hasOrphanedPacksOrStickers = StickerManager.hasOrphanedData(tx: transaction)
        }

        var orphanFilePaths = allOnDiskFilePaths
        orphanFilePaths.subtract(profileAvatarFilePaths)
        orphanFilePaths.subtract(groupAvatarFilePaths)
        orphanFilePaths.subtract(activeStickerFilePaths)

        var orphanFileAndDirectoryPaths: Set<String> = []
        orphanFileAndDirectoryPaths.formUnion(voiceMessageDraftOrphanedPaths)

        return OWSOrphanData(
            interactionIds: orphanInteractionIds,
            filePaths: orphanFilePaths,
            reactionIds: orphanReactionIds,
            mentionIds: orphanMentionIds,
            fileAndDirectoryPaths: orphanFileAndDirectoryPaths,
            hasOrphanedPacksOrStickers: hasOrphanedPacksOrStickers,
        )
    }

    /// Finds paths in `baseUrl` not present in `fetchExpectedRelativePaths()`.
    private static func findOrphanedPaths(
        baseUrl: URL,
        fetchExpectedRelativePaths: (DBReadTransaction) -> Set<String>,
    ) async -> Set<String> {
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

        await databaseStorage.awaitableWrite { _ in }
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

    private static func findOrphanedVoiceMessageDraftPaths() async -> Set<String> {
        await findOrphanedPaths(
            baseUrl: VoiceMessageInterruptedDraftStore.draftVoiceMessageDirectory,
            fetchExpectedRelativePaths: {
                VoiceMessageInterruptedDraftStore.allDraftFilePaths(transaction: $0)
            },
        )
    }

    // MARK: - Remove

    /// Deletes orphaned data.
    private static func processOrphanedData(
        _ orphanedData: OWSOrphanData,
        startTime: Date,
        shouldRemoveOrphanedData: Bool,
    ) async throws {
        // We need to avoid cleaning up new files that are still in the process of
        // being created/written, so we don't clean up anything recent.
        let minimumOrphanAgeSeconds: TimeInterval = 15 * .minute
        let thresholdDate = startTime.addingTimeInterval(-minimumOrphanAgeSeconds)

        var interactionsRemoved = 0
        for interactionId in orphanedData.interactionIds {
            try Task.checkCancellation()
            await databaseStorage.awaitableWrite { transaction in
                guard let interaction = TSInteraction.anyFetch(uniqueId: interactionId, transaction: transaction) else {
                    // This could just be a race condition, but it should be very unlikely.
                    Logger.warn("Could not load interaction: \(interactionId)")
                    return
                }
                // Don't delete interactions which were created in the last N minutes.
                let creationDate = Date(millisecondsSince1970: interaction.timestamp)
                guard creationDate <= thresholdDate else {
                    Logger.info("Skipping orphan interaction due to age: \(-creationDate.timeIntervalSinceNow)")
                    return
                }
                Logger.info("Removing orphan message: \(interaction.uniqueId)")
                interactionsRemoved += 1
                guard shouldRemoveOrphanedData else {
                    return
                }
                DependenciesBridge.shared.interactionDeleteManager
                    .delete(interaction, sideEffects: .default(), tx: transaction)
            }
        }
        Logger.info("Deleted orphan interactions: \(interactionsRemoved)")

        var reactionsRemoved = 0
        for reactionId in orphanedData.reactionIds {
            try Task.checkCancellation()
            await databaseStorage.awaitableWrite { tx in
                let performedCleanup = ReactionManager.tryToCleanupOrphanedReaction(
                    uniqueId: reactionId,
                    thresholdDate: thresholdDate,
                    shouldPerformRemove: shouldRemoveOrphanedData,
                    transaction: tx,
                )
                if performedCleanup {
                    reactionsRemoved += 1
                }
            }
        }
        Logger.info("Deleted orphan reactions: \(reactionsRemoved)")

        var mentionsRemoved = 0
        for mentionId in orphanedData.mentionIds {
            try Task.checkCancellation()
            await databaseStorage.awaitableWrite { tx in
                let performedCleanup = MentionFinder.tryToCleanupOrphanedMention(
                    uniqueId: mentionId,
                    thresholdDate: thresholdDate,
                    shouldPerformRemove: shouldRemoveOrphanedData,
                    transaction: tx,
                )
                if performedCleanup {
                    mentionsRemoved += 1
                }
            }
        }
        Logger.info("Deleted orphan mentions: \(mentionsRemoved)")

        if orphanedData.hasOrphanedPacksOrStickers {
            await databaseStorage.awaitableWrite { transaction in
                StickerManager.cleanUpOrphanedData(tx: transaction)
            }
        }
        try Task.checkCancellation()

        var filesRemoved = 0
        let filePaths = orphanedData.filePaths.sorted()
        for filePath in filePaths {
            try Task.checkCancellation()

            guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath) else {
                // This is fine; the file may have been deleted since we found it.
                Logger.warn("Could not get attributes of file at: \(filePath)")
                continue
            }
            // Don't delete files which were modified in the last N minutes.
            if let modificationDate = (attributes as NSDictionary).fileModificationDate(), modificationDate > thresholdDate {
                Logger.info("Skipping file due to age: \(-modificationDate.timeIntervalSinceNow)")
                continue
            }
            Logger.info("Deleting file: \(filePath)")
            filesRemoved += 1
            guard shouldRemoveOrphanedData else {
                continue
            }
            if !OWSFileSystem.deleteFile(filePath, ignoreIfMissing: true) {
                owsFailDebug("Could not remove orphan file")
            }
        }
        Logger.info("Deleted orphaned files: \(filesRemoved)")

        if shouldRemoveOrphanedData {
            try removeOrphanedFileAndDirectoryPaths(orphanedData.fileAndDirectoryPaths)
        }
    }

    private static func removeOrphanedFileAndDirectoryPaths(_ fileAndDirectoryPaths: Set<String>) throws {
        var successCount = 0
        var errorCount = 0
        // Sort by longest path to shortest path so that we remove files before we
        // try to remove the directories that contain them.
        for fileOrDirectoryPath in fileAndDirectoryPaths.sorted(by: { $0.count < $1.count }).reversed() {
            try Task.checkCancellation()
            do {
                try removeFileOrEmptyDirectory(at: fileOrDirectoryPath)
                successCount += 1
            } catch {
                owsFailDebug("Couldn't remove file or directory: \(error.shortDescription)")
                errorCount += 1
            }
        }
        Logger.info("Deleted orphaned files/directories [successes: \(successCount), failures: \(errorCount)]")
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

    private static func filePaths(inDirectorySafe dirPath: String) throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: dirPath) else {
            return []
        }
        var result: Set<String> = []
        let fileNames: [String]
        do {
            fileNames = try FileManager.default.contentsOfDirectory(atPath: dirPath)
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
        for fileName in fileNames {
            try Task.checkCancellation()
            let filePath = dirPath.appendingPathComponent(fileName)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    result.formUnion(try filePaths(inDirectorySafe: filePath))
                } else {
                    result.insert(filePath)
                }
            }
        }
        return result
    }
}
