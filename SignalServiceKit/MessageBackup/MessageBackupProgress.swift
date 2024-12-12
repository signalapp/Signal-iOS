//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Used to track progress of a backup export, which we measure as a fraction of the total
/// number of database rows we've exported so far.
/// Note that this even weighting by row does NOT reflect time spent; some rows require
/// more work and time to process. But this is just an estimate for UX display.
public struct MessageBackupExportProgress {

    public let progressSource: OWSProgressSource?

    private init(progressSource: OWSProgressSource?) {
        self.progressSource = progressSource
    }

    public static func prepare(
        sink: OWSProgressSink?,
        db: any DB
    ) async throws -> Self {
        guard let sink else {
            return .init(progressSource: nil)
        }
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
        progressSource?.incrementCompletedUnitCount(by: 1)
    }

    public func didFinishExport() {
        guard let progressSource else { return }
        progressSource.incrementCompletedUnitCount(by: progressSource.totalUnitCount)
    }
}

/// Used to track progress of a backup import, which we measure as a fraction of the total
/// number of bytes in the input file that we've processed so far.
/// Note that this even weighting by byte does NOT reflect time spent; some frames require
/// more work and time to process. But this is just an estimate for UX display.
public struct MessageBackupImportProgress {

    public let progressSource: OWSProgressSource?

    private init(progressSource: OWSProgressSource?) {
        self.progressSource = progressSource
    }

    public static func prepare(
        sink: OWSProgressSink?,
        fileUrl: URL
    ) async throws -> Self {
        guard let sink else {
            return .init(progressSource: nil)
        }
        guard let totalByteCount = OWSFileSystem.fileSize(of: fileUrl)?.uint64Value else {
            throw OWSAssertionError("Unable to read file size")
        }
        let progressSource = await sink.addSource(withLabel: "Backup Import", unitCount: totalByteCount)
        return .init(progressSource: progressSource)
    }

    public func didReadBytes(byteLength: Int64) {
        guard let progressSource else { return }
        guard let byteLength = UInt64(exactly: byteLength) else {
            owsFailDebug("How did we get such a huge byte length?")
            return
        }
        if byteLength > 0 {
            progressSource.incrementCompletedUnitCount(by: byteLength)
        }
    }

    public func didFinishImport() {
        guard let progressSource else { return }
        progressSource.incrementCompletedUnitCount(by: progressSource.totalUnitCount)
    }
}
