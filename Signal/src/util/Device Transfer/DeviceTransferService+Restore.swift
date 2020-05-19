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

    func verifyTransferCompletedSuccessfully(receivedFileIds: [String]) -> Bool {
        guard let manifest = readManifestFromTransferDirectory() else {
            owsFailDebug("Missing manifest file")
            return false
        }

        // Check that there aren't any files that we were
        // expecting that are missing.
        for file in manifest.files {
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

    func restoreTransferredData(hotSwapDatabase: Bool) {
        guard hasPendingRestore else {
            return owsFailDebug("Cannot restore data when there was no pending restore")
        }

        guard let manifest = readManifestFromTransferDirectory() else {
            return owsFailDebug("Unexpectedly tried to restore data when there is no valid manifest")
        }

        guard let database = manifest.database else {
            return owsFailDebug("manifest is missing database")
        }

        Logger.info("Attempting to restore transferred data.")

        do {
            try GRDBDatabaseStorageAdapter.keyspec.store(data: database.key)
        } catch {
            return owsFailDebug("failed to restore database key")
        }

        for userDefault in manifest.standardDefaults {
            UserDefaults.standard.set(
                NSKeyedUnarchiver.unarchiveObject(with: userDefault.encodedValue),
                forKey: userDefault.key
            )
        }

        for userDefault in manifest.appDefaults {
            guard ![
                DeviceTransferService.pendingRestoreKey,
                DeviceTransferService.beenRestoredKey,
                DeviceTransferService.pendingWasTransferedClearKey
            ].contains(userDefault.key) else { continue }

            CurrentAppContext().appUserDefaults().set(
                NSKeyedUnarchiver.unarchiveObject(with: userDefault.encodedValue),
                forKey: userDefault.key
            )
        }

        for file in manifest.files + [database.database, database.wal] {
            let fileIsAwaitingRestoration = OWSFileSystem.fileOrFolderExists(
                atPath: URL(
                    fileURLWithPath: file.identifier,
                    relativeTo: DeviceTransferService.pendingTransferFilesDirectory
                ).path
            )
            let fileWasAlreadyRestored = OWSFileSystem.fileOrFolderExists(
                atPath: URL(
                    fileURLWithPath: file.relativePath,
                    relativeTo: DeviceTransferService.appSharedDataDirectory
                ).path
            )

            if fileIsAwaitingRestoration {
                OWSFileSystem.deleteFileIfExists(
                    URL(
                        fileURLWithPath: file.relativePath,
                        relativeTo: DeviceTransferService.appSharedDataDirectory
                    ).path
                )

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

                OWSFileSystem.moveFilePath(
                    URL(
                        fileURLWithPath: file.identifier,
                        relativeTo: DeviceTransferService.pendingTransferFilesDirectory
                    ).path,
                    toFilePath: URL(
                        fileURLWithPath: file.relativePath,
                        relativeTo: DeviceTransferService.appSharedDataDirectory
                    ).path
                )
            } else if fileWasAlreadyRestored {
                Logger.info("Skipping restoration of file that was already restored: \(file.identifier)")
            } else {
                owsFailDebug("unable to restore file that is missing")
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
            }
        }
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
    func launchCleanup() {
        Logger.info("hasBeenRestored: \(hasBeenRestored)")

        AppReadiness.runNowOrWhenAppDidBecomeReady {
            self.tsAccountManager.isTransferInProgress = false

            if self.pendingWasTransferredClear {
                self.tsAccountManager.wasTransferred = false
                self.pendingWasTransferredClear = false
            }
        }

        if hasPendingRestore {
            restoreTransferredData(hotSwapDatabase: false)
        } else {
            resetTransferDirectory()
        }
    }
}
