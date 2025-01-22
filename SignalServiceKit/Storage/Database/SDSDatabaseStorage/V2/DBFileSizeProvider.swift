//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Provides the size of various database files on disk.
public protocol DBFileSizeProvider {
    /// Get the size of the database file.
    func getDatabaseFileSize() -> UInt64

    /// Get the size of the database WAL file.
    func getDatabaseWALFileSize() -> UInt64
}

struct SDSDBFileSizeProvider: DBFileSizeProvider {
    private let databaseStorage: SDSDatabaseStorage

    init(databaseStorage: SDSDatabaseStorage) {
        self.databaseStorage = databaseStorage
    }

    func getDatabaseFileSize() -> UInt64 {
        databaseStorage.databaseFileSize
    }

    func getDatabaseWALFileSize() -> UInt64 {
        databaseStorage.databaseWALFileSize
    }
}
