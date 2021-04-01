//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension DeviceTransferService {
    private static let pendingRestoreKey = "DeviceTransferHasPendingRestore"
    var hasPendingRestore: Bool {
        get { CurrentAppContext().appUserDefaults().bool(forKey: DeviceTransferService.pendingRestoreKey) }
        set { CurrentAppContext().appUserDefaults().set(newValue, forKey: DeviceTransferService.pendingRestoreKey) }
    }
    private static let beenRestoredKey = "DeviceTransferHasBeenRestored"
    var hasBeenRestored: Bool {
        get { CurrentAppContext().appUserDefaults().bool(forKey: DeviceTransferService.beenRestoredKey) }
        set { CurrentAppContext().appUserDefaults().set(newValue, forKey: DeviceTransferService.beenRestoredKey) }
    }
    private static let pendingWasTransferedClearKey = "DeviceTransferPendingWasTransferredClear"
    var pendingWasTransferredClear: Bool {
        get { CurrentAppContext().appUserDefaults().bool(forKey: DeviceTransferService.pendingWasTransferedClearKey) }
        set { CurrentAppContext().appUserDefaults().set(newValue, forKey: DeviceTransferService.pendingWasTransferedClearKey) }
    }
    private static let pendingPromotionFromHotSwapToPrimaryDatabaseKey = "DeviceTransferPendingPromotionFromHotSwapToPrimaryDatabase"
    var pendingPromotionFromHotSwapToPrimaryDatabase: Bool {
        get { CurrentAppContext().appUserDefaults().bool(forKey: DeviceTransferService.pendingPromotionFromHotSwapToPrimaryDatabaseKey) }
        set { CurrentAppContext().appUserDefaults().set(newValue, forKey: DeviceTransferService.pendingPromotionFromHotSwapToPrimaryDatabaseKey) }
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

        guard database.key.count == GRDBDatabaseStorageAdapter.kSQLCipherKeySpecLength else {
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

    func restoreTransferredData(hotswapDatabase: Bool) -> Bool {
        Logger.info("Attempting to restore transferred data.")

        guard hasPendingRestore else {
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
            try GRDBDatabaseStorageAdapter.keyspec.store(data: database.key)
        } catch {
            owsFailDebug("failed to restore database key")
            return false
        }

        for userDefault in manifest.standardDefaults {
            guard let unarchivedValue = NSKeyedUnarchiver.unarchiveObject(with: userDefault.encodedValue) else {
                owsFailDebug("Failed to unarchive value for key \(userDefault.key)")
                continue
            }

            UserDefaults.standard.set(unarchivedValue, forKey: userDefault.key)
        }

        for userDefault in manifest.appDefaults {
            guard ![
                DeviceTransferService.pendingRestoreKey,
                DeviceTransferService.beenRestoredKey,
                DeviceTransferService.pendingWasTransferedClearKey
            ].contains(userDefault.key) else { continue }

            guard let unarchivedValue = NSKeyedUnarchiver.unarchiveObject(with: userDefault.encodedValue) else {
                owsFailDebug("Failed to unarchive value for key \(userDefault.key)")
                continue
            }

            CurrentAppContext().appUserDefaults().set(unarchivedValue, forKey: userDefault.key)
        }

        for file in manifest.files + [database.database, database.wal] {
            let pendingFilePath = URL(
                fileURLWithPath: file.identifier,
                relativeTo: DeviceTransferService.pendingTransferFilesDirectory
            ).path

            // We could be receiving a database in any of the directory modes,
            // so we force the restore path to be the "primary" database since
            // that is generally what we desire. If we're hotswapping, this
            // path will be later overriden with the hotswap path.
            let newFilePath: String
            if DeviceTransferService.databaseIdentifier == file.identifier {
                newFilePath = GRDBDatabaseStorageAdapter.databaseFileUrl(
                    baseDir: SDSDatabaseStorage.baseDir,
                    directoryMode: .primary
                ).path
            } else if DeviceTransferService.databaseWALIdentifier == file.identifier {
                newFilePath = GRDBDatabaseStorageAdapter.databaseWalUrl(
                    baseDir: SDSDatabaseStorage.baseDir,
                    directoryMode: .primary
                ).path
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
                hotswapFilePath = GRDBDatabaseStorageAdapter.databaseFileUrl(
                    baseDir: SDSDatabaseStorage.baseDir,
                    directoryMode: .hotswap
                ).path
            } else if DeviceTransferService.databaseWALIdentifier == file.identifier {
                hotswapFilePath = GRDBDatabaseStorageAdapter.databaseWalUrl(
                    baseDir: SDSDatabaseStorage.baseDir,
                    directoryMode: .hotswap
                ).path
            }

            let fileIsAwaitingRestoration = OWSFileSystem.fileOrFolderExists(atPath: pendingFilePath)
            let fileWasAlreadyRestoredToHotSwapPath: Bool = {
                guard let hotswapFilePath = hotswapFilePath else { return false }
                return OWSFileSystem.fileOrFolderExists(atPath: hotswapFilePath)
            }()
            let fileWasAlreadyRestored = fileWasAlreadyRestoredToHotSwapPath || OWSFileSystem.fileOrFolderExists(atPath: newFilePath)

            if fileIsAwaitingRestoration {
                let restorationPath: String = {
                    if hotswapDatabase, let hotswapFilePath = hotswapFilePath { return hotswapFilePath }
                    return newFilePath
                }()

                guard move(pendingFilePath: pendingFilePath, to: restorationPath) else {
                    owsFailDebug("Failed to move file \(file.identifier)")
                    return false
                }
            } else if fileWasAlreadyRestored {
                if !hotswapDatabase, fileWasAlreadyRestoredToHotSwapPath, let hotswapFilePath = hotswapFilePath {
                    Logger.info("No longer hot swapping, promoting hotswap database to primary database: \(file.identifier)")
                    guard move(pendingFilePath: hotswapFilePath, to: newFilePath) else {
                        owsFailDebug("Failed to promote hotswap database \(file.identifier)")
                        return false
                    }
                } else {
                    Logger.info("Skipping restoration of file that was already restored: \(file.identifier)")
                }
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

        pendingWasTransferredClear = true
        pendingPromotionFromHotSwapToPrimaryDatabase = hotswapDatabase
        hasBeenRestored = true

        resetTransferDirectory()

        if hotswapDatabase {
            DispatchMainThreadSafe {
                self.databaseStorage.reload(directoryMode: .hotswap)
                self.tsAccountManager.wasTransferred = false
                self.pendingWasTransferredClear = false
                self.tsAccountManager.isTransferInProgress = false
                SignalApp.shared().showConversationSplitView()

                // After transfer our push token has changed, update it.
                SyncPushTokensJob.run()
            }
        }

        return true
    }

    func resetTransferDirectory() {
        do {
            if OWSFileSystem.fileOrFolderExists(atPath: DeviceTransferService.pendingTransferDirectory.path) {
                try FileManager.default.removeItem(atPath: DeviceTransferService.pendingTransferDirectory.path)
            }
        } catch {
            owsFailDebug("Failed to delete existing transfer directory \(error)")
        }
        OWSFileSystem.ensureDirectoryExists(DeviceTransferService.pendingTransferDirectory.path)

        // If we had a pending restore, we no longer do.
        hasPendingRestore = false
    }

    private func move(pendingFilePath: String, to newFilePath: String) -> Bool {
        guard OWSFileSystem.deleteFileIfExists(newFilePath) else {
            owsFailDebug("Failed to delete existing file.")
            return false
        }

        let relativeNewPath = newFilePath.replacingOccurrences(
            of: DeviceTransferService.appSharedDataDirectory.path,
            with: ""
        )

        let pathComponents = relativeNewPath.components(separatedBy: "/")
        var path = ""
        for component in pathComponents where !component.isEmpty {
            guard component != pathComponents.last else { break }
            path += component + "/"
            OWSFileSystem.ensureDirectoryExists(
                URL(
                    fileURLWithPath: path,
                    relativeTo: DeviceTransferService.appSharedDataDirectory
                ).path
            )
        }

        guard OWSFileSystem.moveFilePath(pendingFilePath, toFilePath: newFilePath) else {
            owsFailDebug("Failed to restore file.")
            return false
        }

        return true
    }

    private func promoteTransferDatabaseToPrimaryDatabase() -> Bool {
        Logger.info("Promoting the hotswap database to the primary database")

        let primaryDatabaseDirectoryPath = GRDBDatabaseStorageAdapter.databaseDirUrl(
            baseDir: SDSDatabaseStorage.baseDir,
            directoryMode: .primary
        ).path
        let hotswapDatabaseDirectoryPath = GRDBDatabaseStorageAdapter.databaseDirUrl(
            baseDir: SDSDatabaseStorage.baseDir,
            directoryMode: .hotswap
        ).path

        if OWSFileSystem.fileOrFolderExists(atPath: hotswapDatabaseDirectoryPath) {
            guard move(pendingFilePath: hotswapDatabaseDirectoryPath, to: primaryDatabaseDirectoryPath) else {
                owsFailDebug("Failed to promote hotswap database to primary database.")
                return false
            }
        } else {
            guard OWSFileSystem.fileOrFolderExists(atPath: primaryDatabaseDirectoryPath) else {
                owsFailDebug("Missing primary and hotswap database directories.")
                return false
            }
            Logger.info("Missing hotswap database, we may have previously restored. Assuming primary database is correct.")
        }

        pendingPromotionFromHotSwapToPrimaryDatabase = false

        return true
    }

    @objc
    func launchCleanup() -> Bool {
        Logger.info("hasBeenRestored: \(hasBeenRestored)")

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.tsAccountManager.isTransferInProgress = false

            if self.pendingWasTransferredClear {
                self.tsAccountManager.wasTransferred = false
                self.pendingWasTransferredClear = false
            }
        }

        if hasPendingRestore {
            return restoreTransferredData(hotswapDatabase: false)
        } else if pendingPromotionFromHotSwapToPrimaryDatabase {
            return promoteTransferDatabaseToPrimaryDatabase()
        } else {
            resetTransferDirectory()
            return true
        }
    }
}
