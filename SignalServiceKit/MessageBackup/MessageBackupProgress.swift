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

        let progressSource = await sink.addSource(
            withLabel: "Backup Export",
            unitCount: UInt64(estimatedFrameCount)
        )
        return MessageBackupExportProgress(progressSource: progressSource)
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
public struct MessageBackupImportFrameRestoreProgress {
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

        let progressSource = await sink.addSource(
            withLabel: "Backup Import: Frame Restore",
            unitCount: totalByteCount
        )
        return MessageBackupImportFrameRestoreProgress(
            progressSource: progressSource
        )
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

// MARK: -

public class MessageBackupImportRecreateIndexesProgress {
    private enum Constants {
        static let progressSourceUnitCount: UInt64 = .max
    }

    @Atomic
    private var progressSource: OWSProgressSource
    private var updateProcessPeriodicallyTask: Task<Void, Error>?

    private init(progressSource: OWSProgressSource) {
        self.progressSource = progressSource
    }

    public static func prepare(
        sink: OWSProgressSink
    ) async -> MessageBackupImportRecreateIndexesProgress {
        let progressSource = await sink.addSource(
            withLabel: "Backup Import: Recreate Indexes",
            unitCount: Constants.progressSourceUnitCount
        )
        return MessageBackupImportRecreateIndexesProgress(
            progressSource: progressSource
        )
    }

    /// Start approximating progress towards recreating indexes during a Backup
    /// import.
    ///
    /// SQLite doesn't report progress as it creates a database index, so we
    /// can't report progress precisely. Instead, we'll increment progress
    /// automatically over time, with a rough heuristic for how much progress we
    /// made during that time based on the number of restored frames.
    ///
    /// - Important
    /// Callers must pair a call to this method with a call to
    /// ``didFinishIndexRecreation()``.
    public func willStartIndexRecreation(totalFramesRestored: UInt64) {
        owsPrecondition(updateProcessPeriodicallyTask == nil)

        // Ballpark that we can recreate indexes for 5k frames-worth of database
        // rows per second. This number will depend on external factors like
        // device CPU as well as internal factors like how many indexes we're
        // creating.
        let framesEstimatePerSecond = 5_000
        let _unitCountPerSecond = Double(framesEstimatePerSecond) / Double(totalFramesRestored) * Double(Constants.progressSourceUnitCount)
        let unitCountPerSecond = UInt64(clamping: _unitCountPerSecond)

        updateProcessPeriodicallyTask = Task {
            while true {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: NSEC_PER_SEC)

                progressSource.incrementCompletedUnitCount(by: unitCountPerSecond)
            }
        }
    }

    /// Finish approximating progress towards recreating indexes during a Backup
    /// import.
    public func didFinishIndexRecreation() {
        updateProcessPeriodicallyTask?.cancel()
        updateProcessPeriodicallyTask = nil

        progressSource.complete()
    }
}
