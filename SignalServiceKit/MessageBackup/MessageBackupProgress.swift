//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Tracks progress of a Backup export, as a fraction of the number of database
/// rows we've exported so far over the approximate number we expect to.
/// - Note
/// Number of exported database rows is not a perfect metric for time spent, as
/// some rows require more time and work than others.
public struct MessageBackupExportProgress {
    private let progressSource: OWSProgressSource

    private init(progressSource: OWSProgressSource) {
        self.progressSource = progressSource
    }

    public static func prepare(
        sink: OWSProgressSink,
        db: any DB
    ) async throws -> Self {
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

        let progressSource = await sink.addSource(withLabel: "Backup Export", unitCount: UInt64(estimatedFrameCount))
        return .init(progressSource: progressSource)
    }

    public func didExportFrame() {
        progressSource.incrementCompletedUnitCount(by: 1)
    }
}

// MARK: -

/// Tracks the progress of importing frames from a Backup, as a fraction of the
/// total number of bytes read from the Backup file so far.
/// - Note
/// Number of bytes read is not a perfect metric for time spent, as some frames
/// require more time and work than others.
public struct MessageBackupImportFrameProgress {
    private let progressSource: OWSProgressSource

    private init(progressSource: OWSProgressSource) {
        self.progressSource = progressSource
    }

    public static func prepare(
        sink: OWSProgressSink,
        fileUrl: URL
    ) async throws -> Self {
        guard let totalByteCount = OWSFileSystem.fileSize(of: fileUrl)?.uint64Value else {
            throw OWSAssertionError("Unable to read file size")
        }
        let progressSource = await sink.addSource(withLabel: "Backup Import", unitCount: totalByteCount)
        return .init(progressSource: progressSource)
    }

    public func didReadBytes(count byteLength: Int) {
        guard let byteLength = UInt64(exactly: byteLength) else {
            owsFailDebug("How did we get such a huge byte length?")
            return
        }
        if byteLength > 0 {
            progressSource.incrementCompletedUnitCount(by: byteLength)
        }
    }
}
