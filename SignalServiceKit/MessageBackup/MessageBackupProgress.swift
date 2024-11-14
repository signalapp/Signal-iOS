//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Used to track progress of a backup export, which we measure as a fraction of the total
/// number of database rows we've exported so far.
/// Note that this even weighting by row does NOT reflect time spent; some rows require
/// more work and time to process. But this is just an estimate for UX display.
public struct MessageBackupExportProgress {

    public let progress: Progress

    private init(progress: Progress) {
        self.progress = progress
    }

    public static func prepare(db: any DB) throws -> Self {
        var estimatedFrameCount = try db.read { tx in
            // Get all the major things we iterate over. It doesn't have
            // to be perfect; we'll skip some of these and besides they're
            // all weighted evenly. Its just an estimate.
            return try
                SignalRecipient.fetchCount(tx.databaseConnection)
                + ThreadRecord.fetchCount(tx.databaseConnection)
                + InteractionRecord.fetchCount(tx.databaseConnection)
                + CallLinkRecord.fetchCount(tx.databaseConnection)
                + StickerPackRecord.fetchCount(tx.databaseConnection)
        }
        // Add a fixed extra amount for:
        // * header frame
        // * self recipient
        // * account data frame
        // * release notes channel
        estimatedFrameCount += 4
        return .init(progress: Progress(totalUnitCount: Int64(estimatedFrameCount)))
    }

    public func didExportFrame() {
        progress.completedUnitCount = min(progress.totalUnitCount, progress.completedUnitCount + 1)
    }

    public func didFinishExport() {
        progress.completedUnitCount = progress.totalUnitCount
    }
}

/// Used to track progress of a backup import, which we measure as a fraction of the total
/// number of bytes in the input file that we've processed so far.
/// Note that this even weighting by byte does NOT reflect time spent; some frames require
/// more work and time to process. But this is just an estimate for UX display.
public struct MessageBackupImportProgress {

    public let progress: Progress

    private init(progress: Progress) {
        self.progress = progress
    }

    public static func prepare(fileUrl: URL) throws -> Self {
        guard let totalByteCount = OWSFileSystem.fileSize(of: fileUrl)?.int64Value else {
            throw OWSAssertionError("Unable to read file size")
        }
        return .init(progress: Progress(totalUnitCount: totalByteCount))
    }

    public func didReadBytes(byteLength: Int64) {
        progress.completedUnitCount = min(
            progress.totalUnitCount,
            progress.completedUnitCount + byteLength
        )
    }

    public func didFinishImport() {
        progress.completedUnitCount = progress.totalUnitCount
    }
}
