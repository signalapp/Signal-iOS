//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class NotImplementedError: Error {}

public class CloudBackupManagerImpl: CloudBackupManager {

    private let dateProvider: DateProvider
    private let db: DB
    private let signalRecipientFetcher: CloudBackup.Shims.SignalRecipientFetcher
    private let streamProvider: CloudBackupOutputStreamProvider
    private let tsInteractionFetcher: CloudBackup.Shims.TSInteractionFetcher
    private let tsThreadFetcher: CloudBackup.Shims.TSThreadFetcher

    public init(
        dateProvider: @escaping DateProvider,
        db: DB,
        signalRecipientFetcher: CloudBackup.Shims.SignalRecipientFetcher,
        streamProvider: CloudBackupOutputStreamProvider,
        tsInteractionFetcher: CloudBackup.Shims.TSInteractionFetcher,
        tsThreadFetcher: CloudBackup.Shims.TSThreadFetcher
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.signalRecipientFetcher = signalRecipientFetcher
        self.streamProvider = streamProvider
        self.tsInteractionFetcher = tsInteractionFetcher
        self.tsThreadFetcher = tsThreadFetcher
    }

    public func createBackup() async throws -> URL {
        guard FeatureFlags.cloudBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }
        return try await db.awaitableWrite { tx in
            // The mother of all write transactions. Eventually we want to use
            // a read tx, and use explicit locking to prevent other things from
            // happening in the meantime (e.g. message processing) but for now
            // hold the single write lock and call it a day.
            return try self._createBackup(tx: tx)
        }
    }

    public func importBackup(fileUrl: URL) async throws {
        guard FeatureFlags.cloudBackupFileAlpha else {
            owsFailDebug("Should not be able to use backups!")
            throw NotImplementedError()
        }
        try await db.awaitableWrite { tx in
            // This has to open one big write transaction; the alternative is
            // to chunk them into separate writes. Nothing else should be happening
            // in the app anyway.
            try self._importBackup(fileUrl, tx: tx)
        }
    }

    private func _createBackup(tx: DBWriteTransaction) throws -> URL {
        let stream: CloudBackupOutputStream
        switch streamProvider.openOutputFileStream() {
        case .success(let streamResult):
            stream = streamResult
        case .failure(let error):
            throw error
        }

        try writeHeader(stream: stream, tx: tx)

        // TODO: write frames

        return stream.closeFileStream()
    }

    private func writeHeader(stream: CloudBackupOutputStream, tx: DBWriteTransaction) throws {
        let backupInfo = try BackupProtoBackupInfo.builder(
            version: 1,
            backupTime: dateProvider().ows_millisecondsSince1970
        ).build()
        try stream.writeHeader(backupInfo)
    }

    private func _importBackup(_ fileUrl: URL, tx: DBWriteTransaction) throws {
        let stream: CloudBackupInputStream
        switch streamProvider.openInputFileStream(fileURL: fileUrl) {
        case .success(let streamResult):
            stream = streamResult
        case .failure(let error):
            throw error
        }

        _ = try stream.readHeader()

        // TODO: read frames

        return stream.closeFileStream()
    }
}
