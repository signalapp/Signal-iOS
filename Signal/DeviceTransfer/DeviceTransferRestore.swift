//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

protocol DeviceTransferRestore {
    func launchCleanup() -> Bool
    func restoreTransferredData() throws
    func markPendingRestore()
}

class DeviceTransferRestoreImpl: DeviceTransferRestore {

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

    private enum Constants {
        static let hasBeenRestoredKey = "DeviceTransferHasBeenRestored"
        static let restorePhaseKey = "DeviceTransferRestorationPhase"
    }

    var hasBeenRestored: Bool {
        get { CurrentAppContext().appUserDefaults().bool(forKey: Constants.hasBeenRestoredKey) }
        set { CurrentAppContext().appUserDefaults().set(newValue, forKey: Constants.hasBeenRestoredKey) }
    }

    var rawRestorationPhase: Int {
        get { CurrentAppContext().appUserDefaults().integer(forKey: Constants.restorePhaseKey) }
        set { CurrentAppContext().appUserDefaults().set(newValue, forKey: Constants.restorePhaseKey) }
    }

    var restorationPhase: RestorationPhase {
        get throws {
            try RestorationPhase(rawValue: rawRestorationPhase) ?? {
                throw OWSAssertionError("Invalid raw value: \(rawRestorationPhase)")
            }()
        }
    }

    var hasIncompleteRestoration: Bool {
        rawRestorationPhase > 0
    }

    let appReadiness: AppReadiness
    let keychainStorage: any KeychainStorage

    init(
        appReadiness: AppReadiness,
        keychainStorage: any KeychainStorage,
    ) {
        self.appReadiness = appReadiness
        self.keychainStorage = keychainStorage
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
        } else {
            success = true
        }
        if success {
            finalizeRestorationIfNecessary()
        }
        return success
    }

    func restoreTransferredData() throws {
        do {
            let manifest: DeviceTransferProtoManifest? = DeviceTransfer.Utils.readManifestFromTransferDirectory()

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

    func markPendingRestore() {
        // Record that we have a pending restore, so even if the app exits
        // we can still know to restore the data that was transferred.
        let startPhase = RestorationPhase.start
        Logger.info("Setting restoration phase to: \(startPhase)")
        rawRestorationPhase = startPhase.rawValue
    }

    // MARK: - Utility

    private func move(pendingFilePath: String, to newFilePath: String) throws {
        OWSFileSystem.ensureDirectoryExists((newFilePath as NSString).deletingLastPathComponent)
        try OWSFileSystem.moveFilePath(pendingFilePath, toFilePath: newFilePath)
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
        guard let manifest else {
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
            guard
                ![
                    GRDBDatabaseStorageAdapter.DirectoryMode.primaryFolderNameKey,
                    GRDBDatabaseStorageAdapter.DirectoryMode.transferFolderNameKey,
                    Constants.hasBeenRestoredKey,
                ].contains(userDefault.key) else { continue }

            guard let unarchivedValue = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: possibleUserDefaultClasses, from: userDefault.encodedValue) else {
                owsFailDebug("Failed to unarchive value for key \(userDefault.key)")
                continue
            }
            CurrentAppContext().appUserDefaults().set(unarchivedValue, forKey: userDefault.key)
        }
    }

    private func moveManifestFiles(manifest: DeviceTransferProtoManifest?) throws {
        guard let manifest else {
            throw OWSAssertionError("No manifest available")
        }
        let sourceDir = DeviceTransfer.Constants.pendingTransferFilesDirectory
        let destDir = DeviceTransfer.Constants.appSharedDataDirectory

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
        let sourceDir = DeviceTransfer.Constants.pendingTransferFilesDirectory
        let databaseSourceFiles = [database.database, database.wal]

        try databaseSourceFiles.forEach { file in
            let sourceUrl = URL(fileURLWithPath: file.identifier, relativeTo: sourceDir)
            let destUrl: URL
            switch file.identifier {
            case DeviceTransfer.Constants.databaseIdentifier:
                destUrl = GRDBDatabaseStorageAdapter.databaseFileUrl(directoryMode: .transfer)
            case DeviceTransfer.Constants.databaseWALIdentifier:
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

    private func finalizeRestorationIfNecessary() {
        DeviceTransfer.Utils.resetTransferDirectory(createNewTransferDirectory: false)

        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            DependenciesBridge.shared.db.write { tx in
                DependenciesBridge.shared.registrationStateChangeManager.setIsTransferComplete(
                    sendStateUpdateNotification: true,
                    tx: tx,
                )
            }

            // Consult both the modern and legacy restoration flag
            let currentPhase = (try? self.restorationPhase) ?? .noCurrentRestoration
            if currentPhase == .cleanup {
                Logger.info("Performing one-time post-restore cleanup...")
                GRDBDatabaseStorageAdapter.removeOrphanedGRDBDirectories()
                self.rawRestorationPhase = RestorationPhase.noCurrentRestoration.rawValue
                Logger.info("Done!")
            }
        }
    }
}

#if TESTABLE_BUILD

class DeviceTransferRestoreMock: DeviceTransferRestore {
    func launchCleanup() -> Bool { return false }
    func restoreTransferredData() throws { }
    func markPendingRestore() { }
}

#endif
