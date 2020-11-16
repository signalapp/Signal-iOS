//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

        guard database.key.count == kSQLCipherKeySpecLength else {
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

    func restoreTransferredData(hotSwapDatabase: Bool) -> Bool {
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
            let newFilePath = URL(
                fileURLWithPath: file.relativePath,
                relativeTo: DeviceTransferService.appSharedDataDirectory
            ).path

            let fileIsAwaitingRestoration = OWSFileSystem.fileOrFolderExists(atPath: pendingFilePath)
            let fileWasAlreadyRestored = OWSFileSystem.fileOrFolderExists(atPath: newFilePath)

            if fileIsAwaitingRestoration {
                guard OWSFileSystem.deleteFileIfExists(newFilePath) else {
                    owsFailDebug("Failed to delete existing file \(file.identifier).")
                    return false
                }

                let pathComponents = file.relativePath.components(separatedBy: "/")
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
                    owsFailDebug("Failed to restore \(file.identifier)")
                    return false
                }
            } else if fileWasAlreadyRestored {
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

        pendingWasTransferredClear = true
        hasBeenRestored = true

        resetTransferDirectory()

        if hotSwapDatabase {
            DispatchMainThreadSafe {
                self.databaseStorage.reload()
                self.tsAccountManager.wasTransferred = false
                self.pendingWasTransferredClear = false
                self.tsAccountManager.isTransferInProgress = false
                SignalApp.shared().showConversationSplitView()

                // After transfer our push token has changed, update it.
                SyncPushTokensJob.run(
                    accountManager: AppEnvironment.shared.accountManager,
                    preferences: Environment.shared.preferences
                )
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

    @objc
    func launchCleanup() -> Bool {
        Logger.info("hasBeenRestored: \(hasBeenRestored)")

        AppReadiness.runNowOrWhenAppDidBecomeReady {
            self.tsAccountManager.isTransferInProgress = false

            if self.pendingWasTransferredClear {
                self.tsAccountManager.wasTransferred = false
                self.pendingWasTransferredClear = false
            }
        }

        if hasPendingRestore {
            return restoreTransferredData(hotSwapDatabase: false)
        } else {
            resetTransferDirectory()
            return true
        }
    }
}
