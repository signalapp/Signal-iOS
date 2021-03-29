//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

extension StorageCoordinator {
    @objc
    public static var hasDatabaseCorruption: Bool {
        guard dataStoreForUI == .grdb else { return false }
        return SSKPreferences.hasGrdbDatabaseCorruption()
    }

    @objc
    public static func attemptDatabaseRecovery() throws {
        guard hasDatabaseCorruption else { return }

        let baseDir = SDSDatabaseStorage.baseDir

        let primaryDatabaseDirURL = SDSDatabaseStorage.grdbDatabaseDirUrl
        let primaryDatabaseFileURL = SDSDatabaseStorage.grdbDatabaseFileUrl

        let backupDatabaseDirURL = GRDBDatabaseStorageAdapter.databaseDirUrl(baseDir: baseDir, directoryMode: .backup)
        let backupDatabaseFileURL = GRDBDatabaseStorageAdapter.databaseFileUrl(baseDir: baseDir, directoryMode: .backup)
        owsAssert(primaryDatabaseDirURL != backupDatabaseDirURL)
        owsAssert(primaryDatabaseFileURL != backupDatabaseFileURL)

        let recoveryDatabaseDirURL = GRDBDatabaseStorageAdapter.databaseDirUrl(baseDir: baseDir, directoryMode: .recovery)
        let recoveryDatabaseFileURL = GRDBDatabaseStorageAdapter.databaseFileUrl(baseDir: baseDir, directoryMode: .recovery)
        owsAssert(primaryDatabaseDirURL != recoveryDatabaseDirURL)
        owsAssert(primaryDatabaseFileURL != recoveryDatabaseFileURL)

        if !OWSFileSystem.fileOrFolderExists(url: primaryDatabaseFileURL)
            && OWSFileSystem.fileOrFolderExists(url: backupDatabaseFileURL)
            && OWSFileSystem.fileOrFolderExists(url: recoveryDatabaseFileURL) {
            // If we have a backup *and* recovery file already, and the primary database no longer exists,
            // we probably were terminated during some sensitive file operations. Lets just try and finish
            // that work and not try and make a new recovery DB
            Logger.info("Missing primary database, but a recovery DB is present. Attempting recovery.")
        } else {
            Logger.info("Attempting database recovery.")

            // If there is already a "recovery" database lingering, delete it.
            try OWSFileSystem.deleteFileIfExists(url: recoveryDatabaseDirURL)
            OWSFileSystem.ensureDirectoryExists(recoveryDatabaseDirURL.path)

            // Before we open the database, create a backup copy. This is just
            // out of paranoia, we'll clean it up if later everything seems fine.
            try OWSFileSystem.deleteFileIfExists(url: backupDatabaseDirURL)
            try FileManager.default.copyItem(at: primaryDatabaseDirURL, to: backupDatabaseDirURL)

            // Initialize the GRDB storage for the primary DB. It is
            // critical that this is the first time we access GRDB storage,
            // but it is equally critical we close the connection and release
            // it before the app continues on.

            try autoreleasepool {
                let keyspec = GRDBDatabaseStorageAdapter.keyspec
                let grdbStorage = GRDBDatabaseStorageAdapter(baseDir: baseDir)
                defer { grdbStorage.pool.releaseMemory() }

                // Attempt to export a copy of the database. The theory is that,
                // in export, some corrupted aspects of the database can be
                // resolved in the newly exported database.
                // TODO: we could eventually try and use sqlite's ".recover"
                // command which supposedly does a more thorough job, but it
                // provides complications with sqlcipher so for now we avoid it.
                try grdbStorage.pool.writeWithoutTransaction { db in
                    // Attach a recovery database
                    try db.execute(
                        sql: "ATTACH DATABASE ? AS recovery_db",
                        arguments: [
                            recoveryDatabaseFileURL.absoluteString
                        ]
                    )

                    // Setup sqlcipher for the attached database exactly
                    // matching the primary database.
                    try GRDBDatabaseStorageAdapter.prepareDatabase(
                        db: db,
                        keyspec: keyspec,
                        name: "recovery_db"
                    )

                    // Export our database to the recovery database
                    try db.execute(
                        sql: "SELECT sqlcipher_export('recovery_db')"
                    )

                    // Detach the recovery database
                    try db.execute(
                        sql: "DETACH DATABASE recovery_db"
                    )
                }

                // Verify we can open the recovery database
                var configuration = Configuration()
                configuration.prepareDatabase = { db in
                    try GRDBDatabaseStorageAdapter.prepareDatabase(db: db, keyspec: keyspec)
                }
                let recoveryPool = try DatabasePool(path: recoveryDatabaseFileURL.path, configuration: configuration)
                recoveryPool.releaseMemory()
            }
        }

        // Finally, we attempt to replace the primary database with the
        // recovery database. This is dangerous, but the user is already
        // in a corrupted state so some risk is worthwhile. In theory,
        // there should be no permanent data loss that doesn't already
        // exist since we've established a backup database.
        try OWSFileSystem.deleteFileIfExists(url: primaryDatabaseDirURL)

        // Move the recovery database into place.
        try FileManager.default.moveItem(at: recoveryDatabaseDirURL, to: primaryDatabaseDirURL)

        databaseStorage.reopenGRDBStorage()

        Logger.info("Database recovery complete, attempting to continue with recovered database.")

        // Mark DB as no longer corrupted
        SSKPreferences.setHasGrdbDatabaseCorruption(false)
        SSKPreferences.setHasGrdbEverRecoveredCorruptedDatabase(true)

        // TODO: At some point, we must delete the backup database.
        // I'm not doing that while we can (hopefully) verify success
        // of this method with a user currently encountering corruption
        // since it leaves us a channel of recovery if things go horribly
        // wrong. Before this makes it into a non-beta build we must do
        // that cleanup.
    }
}
