//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension BackupArchive {
    public enum ProtoOutputStreamWriteResult {
        case success
        /// Unable to serialize the provided proto object.
        /// Should never happen, and catastrophic if it does.
        case protoSerializationError(Swift.Error)
        /// Failure writing at file I/O level.
        case fileIOError(Swift.Error)
    }
}

// MARK: -

/**
 * Output stream for reading and writing a backup file on disk.
 *
 * The backup file is just a sequence of serialized proto bytes, back to back, delimited by varint
 * byte sizes so we know how much to read into memory to deserialize the next proto.
 * The output stream abstracts over this, and allows callers to just think in terms of "frames",
 * the individual proto objects that we write one at a time.
 */
class BackupArchiveProtoOutputStream {
    private let outputStream: OutputStreamable
    private let exportProgress: BackupArchiveExportProgress?

    init(
        outputStream: OutputStreamable,
        exportProgress: BackupArchiveExportProgress?,
    ) {
        self.outputStream = outputStream
        self.exportProgress = exportProgress
    }

    /// Write a header (``BackupProto_BackupInfo``) to the backup file.
    ///
    /// - Important
    /// It is the caller's responsibility to ensure this is always written, and
    /// is the first thing written, in order to produce a valid backup file.
    func writeHeader(_ header: BackupProto_BackupInfo) -> BackupArchive.ProtoOutputStreamWriteResult {
        let bytes: Data
        do {
            bytes = try header.serializedData()
        } catch {
            return .protoSerializationError(error)
        }
        do {
            try outputStream.write(data: bytes)
        } catch {
            return .fileIOError(error)
        }
        exportProgress?.didExportFrame()
        return .success
    }

    /// Write a frame to the backup file.
    func writeFrame(_ frame: BackupProto_Frame) -> BackupArchive.ProtoOutputStreamWriteResult {
        let bytes: Data
        do {
            bytes = try frame.serializedData()
        } catch {
            return .protoSerializationError(error)
        }
        do {
            try outputStream.write(data: bytes)
        } catch {
            return .fileIOError(error)
        }
        exportProgress?.didExportFrame()
        return .success
    }

    /// Closes the output stream.
    func closeFileStream() throws {
        exportProgress?.didCloseStream()
        try outputStream.close()
    }
}
