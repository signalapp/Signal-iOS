//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum YDBStorage {
    private static var legacyDatabaseDirPath: String {
        OWSFileSystem.appDocumentDirectoryPath()
    }
    private static var sharedDataDatabaseDirPath: String {
        OWSFileSystem.appSharedDataDirectoryPath().appendingPathComponent("database")
    }
    private static let databaseFilename: String = "Signal.sqlite"
    private static let databaseFilename_SHM: String = "\(databaseFilename)-shm"
    private static let databaseFilename_WAL: String = "\(databaseFilename)-wal"
    private static var legacyDatabaseFilePath: String {
        legacyDatabaseDirPath.appendingPathComponent(databaseFilename)
    }
    private static var legacyDatabaseFilePath_SHM: String {
        legacyDatabaseDirPath.appendingPathComponent(databaseFilename_SHM)
    }
    private static var legacyDatabaseFilePath_WAL: String {
        legacyDatabaseDirPath.appendingPathComponent(databaseFilename_WAL)
    }
    private static var sharedDataDatabaseFilePath: String {
        sharedDataDatabaseDirPath.appendingPathComponent(databaseFilename)
    }
    private static var sharedDataDatabaseFilePath_SHM: String {
        sharedDataDatabaseDirPath.appendingPathComponent(databaseFilename_SHM)
    }
    private static var sharedDataDatabaseFilePath_WAL: String {
        sharedDataDatabaseDirPath.appendingPathComponent(databaseFilename_WAL)
    }

    public static func deleteYDBStorage() {
        OWSFileSystem.deleteFileIfExists(legacyDatabaseFilePath)
        OWSFileSystem.deleteFileIfExists(legacyDatabaseFilePath_SHM)
        OWSFileSystem.deleteFileIfExists(legacyDatabaseFilePath_WAL)
        OWSFileSystem.deleteFileIfExists(sharedDataDatabaseFilePath)
        OWSFileSystem.deleteFileIfExists(sharedDataDatabaseFilePath_SHM)
        OWSFileSystem.deleteFileIfExists(sharedDataDatabaseFilePath_WAL)
        // NOTE: It's NOT safe to delete OWSPrimaryStorage.legacyDatabaseDirPath
        //       which is the app document dir.
        OWSFileSystem.deleteContents(ofDirectory: sharedDataDatabaseDirPath)
    }
}
