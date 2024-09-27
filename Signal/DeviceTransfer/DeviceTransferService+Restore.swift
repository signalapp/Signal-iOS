//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension DeviceTransferService {
    private static let hasBeenRestoredKey = "DeviceTransferHasBeenRestored"
    var hasBeenRestored: Bool {
        get { CurrentAppContext().appUserDefaults().bool(forKey: DeviceTransferService.hasBeenRestoredKey) }
        set { CurrentAppContext().appUserDefaults().set(newValue, forKey: DeviceTransferService.hasBeenRestoredKey) }
    }

    private static let restorePhaseKey = "DeviceTransferRestorationPhase"
    var rawRestorationPhase: Int {
        get { CurrentAppContext().appUserDefaults().integer(forKey: DeviceTransferService.restorePhaseKey) }
        set { CurrentAppContext().appUserDefaults().set(newValue, forKey: DeviceTransferService.restorePhaseKey) }
    }

    var restorationPhase: RestorationPhase {
        get throws {
            try RestorationPhase(rawValue: rawRestorationPhase) ?? {
                throw OWSAssertionError("Invalid raw value: \(rawRestorationPhase)")
            }()
        }
    }

    private enum LegacyRestorationFlags {
        static let pendingRestoreKey = "DeviceTransferHasPendingRestore"
        static var hasPendingRestore: Bool {
            get { CurrentAppContext().appUserDefaults().bool(forKey: Self.pendingRestoreKey) }
            set {
                owsAssertDebug(newValue == false) // Future transfers should use the `restorationPhase` key
                CurrentAppContext().appUserDefaults().set(newValue, forKey: Self.pendingRestoreKey)
            }
        }
        static let pendingWasTransferredClearKey = "DeviceTransferPendingWasTransferredClear"
        static var pendingWasTransferredClear: Bool {
            get { CurrentAppContext().appUserDefaults().bool(forKey: Self.pendingWasTransferredClearKey) }
            set { CurrentAppContext().appUserDefaults().set(newValue, forKey: Self.pendingWasTransferredClearKey) }
        }

        static let pendingPromotionFromHotSwapToPrimaryDatabaseKey = "DeviceTransferPendingPromotionFromHotSwapToPrimaryDatabase"
        static var pendingPromotionFromHotSwapToPrimaryDatabase: Bool {
            get { CurrentAppContext().appUserDefaults().bool(forKey: Self.pendingPromotionFromHotSwapToPrimaryDatabaseKey) }
            set {
                owsAssertDebug(newValue == false) // Hotswapping databases is deprecated
                CurrentAppContext().appUserDefaults().set(newValue, forKey: Self.pendingPromotionFromHotSwapToPrimaryDatabaseKey)
            }
        }
    }

    func verifyTransferCompletedSuccessfully(receivedFileIds: [String], skippedFileIds: [String]) -> Bool {
        guard let manifest = readManifestFromTransferDirectory() else {
            owsFailDebug("Missing manifest file")
            return false
        }

        // Check that there aren't any files that we were
        // expecting that are missing.
        for file in manifest.files {
            guard !skippedFileIds.contains(file.identifier) else { continue }

            guard receivedFileIds.contains(file.identifier) else {
                owsFailDebug("did not receive file \(file.identifier)")
                return false
            }
            guard OWSFileSystem.fileOrFolderExists(
                atPath: URL(
                    fileURLWithPath: file.identifier,
                    relativeTo: DeviceTransferService.pendingTransferFilesDirectory
                ).path
            ) else {
                owsFailDebug("Missing file \(file.identifier)")
                return false
            }
        }

        // Check that the appropriate database files were received
        guard let database = manifest.database else {
            owsFailDebug("missing database proto")
            return false
        }

        guard database.key.count == GRDBKeyFetcher.Constants.kSQLCipherKeySpecLength else {
            owsFailDebug("incorrect database key length")
            return false
        }

        guard receivedFileIds.contains(DeviceTransferService.databaseIdentifier) else {
            owsFailDebug("did not receive database file")
            return false
        }

        guard OWSFileSystem.fileOrFolderExists(
            atPath: URL(
                fileURLWithPath: DeviceTransferService.databaseIdentifier,
                relativeTo: DeviceTransferService.pendingTransferFilesDirectory
            ).path
        ) else {
            owsFailDebug("missing database file")
            return false
        }

        guard receivedFileIds.contains(DeviceTransferService.databaseWALIdentifier) else {
            owsFailDebug("did not receive database wal file")
            return false
        }

        guard OWSFileSystem.fileOrFolderExists(
            atPath: URL(
                fileURLWithPath: DeviceTransferService.databaseWALIdentifier,
                relativeTo: DeviceTransferService.pendingTransferFilesDirectory
            ).path
        ) else {
            owsFailDebug("missing database wal file")
            return false
        }

        return true
    }

    func restoreTransferredDataLegacy() -> Bool {
        Logger.info("Attempting to restore transferred data.")

        guard LegacyRestorationFlags.hasPendingRestore else {
            owsFailDebug("Cannot restore data when there was no pending restore")
            return false
        }

        guard let manifest = readManifestFromTransferDirectory() else {
            owsFailDebug("Unexpectedly tried to restore data when there is no valid manifest")
            return false
        }

        guard let database = manifest.database else {
            owsFailDebug("manifest is missing database")
            return false
        }

        do {
            try GRDBKeyFetcher(keychainStorage: keychainStorage).store(data: database.key)
        } catch {
            owsFailDebug("failed to restore database key")
            return false
        }

        do {
            try updateUserDefaults(manifest: manifest)
        } catch {
            owsFailDebug("Failed to update user defaults: \(error)")
            return false
        }

        for file in manifest.files + [database.database, database.wal] {
            let pendingFilePath = URL(
                fileURLWithPath: file.identifier,
                relativeTo: DeviceTransferService.pendingTransferFilesDirectory
            ).path

            // We could be receiving a database in any of the directory modes,
            // so we force the restore path to be the "primary" database since
            // that is generally what we desire. If we're hotswapping, this
            // path will be later overridden with the hotswap path.
            let newFilePath: String
            if DeviceTransferService.databaseIdentifier == file.identifier {
                newFilePath = GRDBDatabaseStorageAdapter.databaseFileUrl(directoryMode: .primary).path
            } else if DeviceTransferService.databaseWALIdentifier == file.identifier {
                newFilePath = GRDBDatabaseStorageAdapter.databaseWalUrl(directoryMode: .primary).path
            } else {
                newFilePath = URL(
                    fileURLWithPath: file.relativePath,
                    relativeTo: DeviceTransferService.appSharedDataDirectory
                ).path
            }

            // If we're hot swapping the database, we move the database
            // files to a special hotswap directory, since the primary
            // database is already open. Trying to overwrite the file
            // in situ can result in database corruption if something
            // tries to perform a write.
            var hotswapFilePath: String?
            if DeviceTransferService.databaseIdentifier == file.identifier {
                hotswapFilePath = GRDBDatabaseStorageAdapter.databaseFileUrl(directoryMode: .hotswapLegacy).path
            } else if DeviceTransferService.databaseWALIdentifier == file.identifier {
                hotswapFilePath = GRDBDatabaseStorageAdapter.databaseWalUrl(directoryMode: .hotswapLegacy).path
            }

            if OWSFileSystem.fileOrFolderExists(atPath: pendingFilePath) {
                guard OWSFileSystem.deleteFileIfExists(newFilePath) else {
                    owsFailDebug("Failed to delete existing file.")
                    return false
                }
                do {
                    try move(pendingFilePath: pendingFilePath, to: newFilePath)
                } catch {
                    owsFailDebug("Failed to move file \(file.identifier); \(error.shortDescription)")
                    return false
                }
            } else if let hotswapFilePath, OWSFileSystem.fileOrFolderExists(atPath: hotswapFilePath) {
                Logger.info("No longer hot swapping, promoting hotswap database to primary database: \(file.identifier)")
                guard OWSFileSystem.deleteFileIfExists(newFilePath) else {
                    owsFailDebug("Failed to delete existing file.")
                    return false
                }
                do {
                    try move(pendingFilePath: hotswapFilePath, to: newFilePath)
                } catch {
                    owsFailDebug("Failed to promote hotswap database \(file.identifier); \(error.shortDescription)")
                    return false
                }
            } else if OWSFileSystem.fileOrFolderExists(atPath: newFilePath) {
                Logger.info("Skipping restoration of file that was already restored: \(file.identifier)")
            } else if [
                DeviceTransferService.databaseIdentifier,
                DeviceTransferService.databaseWALIdentifier
            ].contains(file.identifier) {
                owsFailDebug("unable to restore file that is missing")
                return false
            } else {
                // We sometimes don't receive a file because it goes missing on the old
                // device between when we generate the manifest and when we perform the
                // restoration. Our verification process ensures that the only files that
                // could be missing in this way are non-essential files. It's better to
                // let the user continue than to lock them out of the app in this state.
                Logger.info("Skipping restoration of missing file: \(file.identifier)")
                continue
            }
        }

        LegacyRestorationFlags.pendingWasTransferredClear = true
        LegacyRestorationFlags.pendingPromotionFromHotSwapToPrimaryDatabase = false
        hasBeenRestored = true

        resetTransferDirectory(createNewTransferDirectory: true)

        return true
    }

    func resetTransferDirectory(createNewTransferDirectory: Bool) {
        do {
            try FileManager.default.removeItem(atPath: DeviceTransferService.pendingTransferDirectory.path)
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile, POSIXError.ENOENT {
            // it doesn't exist -- this is fine
        } catch {
            owsFailDebug("Failed to delete existing transfer directory \(error)")
        }
        if createNewTransferDirectory {
            OWSFileSystem.ensureDirectoryExists(DeviceTransferService.pendingTransferDirectory.path)
        }

        // If we had a pending restore, we no longer do.
        switch try? restorationPhase {
        case .noCurrentRestoration, .cleanup: break
        default: rawRestorationPhase = RestorationPhase.noCurrentRestoration.rawValue
        }
        LegacyRestorationFlags.hasPendingRestore = false
    }

    private func move(pendingFilePath: String, to newFilePath: String) throws {
        OWSFileSystem.ensureDirectoryExists((newFilePath as NSString).deletingLastPathComponent)
        try OWSFileSystem.moveFilePath(pendingFilePath, toFilePath: newFilePath)
    }

    private func promoteTransferDatabaseToPrimaryDatabase() -> Bool {
        Logger.info("Promoting the hotswap database to the primary database")

        let primaryDatabaseDirectoryPath = GRDBDatabaseStorageAdapter.databaseDirUrl(directoryMode: .primary).path
        let hotswapDatabaseDirectoryPath = GRDBDatabaseStorageAdapter.databaseDirUrl(directoryMode: .hotswapLegacy).path

        if OWSFileSystem.fileOrFolderExists(atPath: hotswapDatabaseDirectoryPath) {
            guard OWSFileSystem.deleteFileIfExists(primaryDatabaseDirectoryPath) else {
                owsFailDebug("Failed to delete existing file.")
                return false
            }
            do {
                try move(pendingFilePath: hotswapDatabaseDirectoryPath, to: primaryDatabaseDirectoryPath)
            } catch {
                owsFailDebug("Failed to promote hotswap database to primary database: \(error.shortDescription)")
                return false
            }
        } else {
            guard OWSFileSystem.fileOrFolderExists(atPath: primaryDatabaseDirectoryPath) else {
                owsFailDebug("Missing primary and hotswap database directories.")
                return false
            }
            Logger.info("Missing hotswap database, we may have previously restored. Assuming primary database is correct.")
        }

        LegacyRestorationFlags.pendingPromotionFromHotSwapToPrimaryDatabase = false

        return true
    }

    func launchCleanup() -> Bool {
        Logger.info("hasBeenRestored: \(hasBeenRestored)")

        let success: Bool
        if hasIncompleteRestoration {
            do {
                try restoreTransferredData()
                success = true
            } catch {
                owsFailDebug("Failed to finish restoration: \(error)")
                success = false
            }
        } else if LegacyRestorationFlags.hasPendingRestore {
            success = restoreTransferredDataLegacy()
        } else if LegacyRestorationFlags.pendingPromotionFromHotSwapToPrimaryDatabase {
            success = promoteTransferDatabaseToPrimaryDatabase()
        } else {
            success = true
        }
        if success {
            finalizeRestorationIfNecessary()
        }
        return success
    }
}

extension DeviceTransferService {

    enum RestorationPhase: Int {
        // Start/Complete: Nothing to do.
        case noCurrentRestoration = 0

        // Performed by `restoreTransferredData()`
        case start
        case updateUserDefaults
        case moveManifestFiles
        case allocateNewDatabaseDirectory
        case moveDatabaseFiles
        case updateDatabase

        // This state represents that there's some one-time cleanup that's left to be done
        // Restoration is complete, but every time the app launches `finalizeRestorationIfNecessary`
        // will run and transition to `noCurrentRestoration` once successful
        case cleanup

        var next: RestorationPhase {
            RestorationPhase(rawValue: rawValue + 1) ?? .noCurrentRestoration
        }
    }

    var hasIncompleteRestoration: Bool { rawRestorationPhase > 0 }
    func restoreTransferredData() throws {
        do {
            let manifest: DeviceTransferProtoManifest? = readManifestFromTransferDirectory()

            // Run through the restoration steps. The deal here is:
            // - The phase we're currently on has not been completed yet
            // - Each phase must be idempotent and capable of handling arbitrary interruption (i.e. crashes)
            // - If a phase completes without error, it should be durable
            // - We return once we've hit `noCurrentRestoration` or `cleanup`
            var currentPhase = try restorationPhase
            while currentPhase != .noCurrentRestoration, currentPhase != .cleanup {
                Logger.info("Performing restoration phase: \(currentPhase)")
                try performRestorationPhase(currentPhase, manifest: manifest)
                Logger.info("Completed restoration phase: \(currentPhase)")

                currentPhase = currentPhase.next
                rawRestorationPhase = currentPhase.rawValue
            }
        } catch {
            owsFailDebug("Hit error during restoration phase \(rawRestorationPhase): \(error)")
            throw error
        }
    }

    private func performRestorationPhase(_ phase: RestorationPhase, manifest: DeviceTransferProtoManifest?) throws {
        switch phase {
        case .noCurrentRestoration, .cleanup:
            owsFailDebug("Unexpected state")
        case .start:
            // No-op, having a start case jut makes the logs look nice
            break
        case .updateUserDefaults:
            try updateUserDefaults(manifest: manifest)
        case .moveManifestFiles:
            try moveManifestFiles(manifest: manifest)
        case .allocateNewDatabaseDirectory:
            allocateNewDatabaseDirectory()
        case .moveDatabaseFiles:
            try moveDatabaseFiles(manifest: manifest)
        case .updateDatabase:
            try updateCurrentDatabase(manifest: manifest)
            // At this point, we've restored all of the data we need. Just some bits of cleanup left.
            hasBeenRestored = true
        }
    }

    private func updateUserDefaults(manifest: DeviceTransferProtoManifest?) throws {
        guard let manifest = manifest else {
            throw OWSAssertionError("No manifest available")
        }

        let possibleUserDefaultClasses = [
            NSData.self,
            NSString.self,
            NSNumber.self,
            NSDate.self,
            NSArray.self,
            NSDictionary.self,
        ]
        // TODO: We should codify how we want to use standardDefaults. Either we should
        // get rid of them, or expand them to support all of our extensions
        for userDefault in manifest.standardDefaults {
            guard let unarchivedValue = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: possibleUserDefaultClasses, from: userDefault.encodedValue) else {
                owsFailDebug("Failed to unarchive value for key \(userDefault.key)")
                continue
            }

            UserDefaults.standard.set(unarchivedValue, forKey: userDefault.key)
        }

        // TODO: Do we want to transfer all of our app defaults?
        for userDefault in manifest.appDefaults {
            guard ![
                GRDBDatabaseStorageAdapter.DirectoryMode.primaryFolderNameKey,
                GRDBDatabaseStorageAdapter.DirectoryMode.transferFolderNameKey,
                DeviceTransferService.hasBeenRestoredKey,
                LegacyRestorationFlags.pendingRestoreKey,
                LegacyRestorationFlags.pendingPromotionFromHotSwapToPrimaryDatabaseKey,
                LegacyRestorationFlags.pendingWasTransferredClearKey
            ].contains(userDefault.key) else { continue }

            guard let unarchivedValue = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: possibleUserDefaultClasses, from: userDefault.encodedValue) else {
                owsFailDebug("Failed to unarchive value for key \(userDefault.key)")
                continue
            }
            CurrentAppContext().appUserDefaults().set(unarchivedValue, forKey: userDefault.key)
        }
    }

    private func moveManifestFiles(manifest: DeviceTransferProtoManifest?) throws {
        guard let manifest = manifest else {
            throw OWSAssertionError("No manifest available")
        }
        let sourceDir = DeviceTransferService.pendingTransferFilesDirectory
        let destDir = DeviceTransferService.appSharedDataDirectory

        try manifest.files.forEach { file in
            let sourceUrl = URL(fileURLWithPath: file.identifier, relativeTo: sourceDir)
            let destUrl = URL(fileURLWithPath: file.relativePath, relativeTo: destDir)

            do {
                try move(pendingFilePath: sourceUrl.path, to: destUrl.path)
            } catch CocoaError.fileWriteFileExists {
                Logger.info("Skipping restoration of file that was already restored: \(file.identifier)")
            } catch CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile, POSIXError.ENOENT {
                // We sometimes don't receive a file because it goes missing on the old
                // device between when we generate the manifest and when we perform the
                // restoration. Our verification process ensures that the only files that
                // could be missing in this way are non-essential files. It's better to
                // let the user continue than to lock them out of the app in this state.
                Logger.info("Skipping restoration of missing file: \(file.identifier)")
            } catch {
                throw OWSAssertionError("Failed to move file \(file.identifier)")
            }
        }
    }

    // We create the directory but do not touch anything about it until this phase has committed
    private func allocateNewDatabaseDirectory() {
        GRDBDatabaseStorageAdapter.createNewTransferDirectory()
    }

    private func moveDatabaseFiles(manifest: DeviceTransferProtoManifest?) throws {
        guard let database = manifest?.database else {
            throw OWSAssertionError("No manifest database available")
        }
        let sourceDir = DeviceTransferService.pendingTransferFilesDirectory
        let databaseSourceFiles = [database.database, database.wal]

        try databaseSourceFiles.forEach { file in
            let sourceUrl = URL(fileURLWithPath: file.identifier, relativeTo: sourceDir)
            let destUrl: URL
            switch file.identifier {
            case DeviceTransferService.databaseIdentifier:
                destUrl = GRDBDatabaseStorageAdapter.databaseFileUrl(directoryMode: .transfer)
            case DeviceTransferService.databaseWALIdentifier:
                destUrl = GRDBDatabaseStorageAdapter.databaseWalUrl(directoryMode: .transfer)
            default:
                throw OWSAssertionError("Unknown file identifier")
            }

            do {
                try move(pendingFilePath: sourceUrl.path, to: destUrl.path)
            } catch CocoaError.fileWriteFileExists {
                Logger.info("Skipping restoration of database file that was already restored: \(file.identifier)")
            } catch {
                throw OWSAssertionError("Failed to move file \(file.identifier); \(error.shortDescription)")
            }
        }
    }

    private func updateCurrentDatabase(manifest: DeviceTransferProtoManifest?) throws {
        guard let database = manifest?.database else {
            throw OWSAssertionError("No manifest database available")
        }

        try GRDBKeyFetcher(keychainStorage: keychainStorage).store(data: database.key)
        GRDBDatabaseStorageAdapter.promoteTransferDirectoryToPrimary()
    }

    @discardableResult
    func finalizeRestorationIfNecessary() -> Guarantee<Void> {
        resetTransferDirectory(createNewTransferDirectory: false)

        let (promise, future) = Guarantee<Void>.pending()
        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            DependenciesBridge.shared.db.write { tx in
                DependenciesBridge.shared.registrationStateChangeManager.setIsTransferComplete(
                    sendStateUpdateNotification: true,
                    tx: tx
                )
            }

            // Consult both the modern and legacy restoration flag
            let currentPhase = (try? self.restorationPhase) ?? .noCurrentRestoration
            if currentPhase == .cleanup || LegacyRestorationFlags.pendingWasTransferredClear {
                Logger.info("Performing one-time post-restore cleanup...")
                GRDBDatabaseStorageAdapter.removeOrphanedGRDBDirectories()
                LegacyRestorationFlags.pendingWasTransferredClear = false
                self.rawRestorationPhase = RestorationPhase.noCurrentRestoration.rawValue
                Logger.info("Done!")
            }

            future.resolve()
        }
        return promise
    }
}
