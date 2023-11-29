//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension CloudBackup {
    public enum ProtoOutputStreamWriteResult {
        case success
        /// Unable to serialize the provided proto object.
        /// Should never happen, and catastrophic if it does.
        case protoSerializationError(Error)
        /// Failure writing at file I/O level.
        case fileIOError(Error)
    }
}

/**
 * Output stream for reading and writing a backup file on disk.
 *
 * The backup file is just a sequence of serialized proto bytes, back to back, delimited by varint
 * byte sizes so we know how much to read into memory to deserialize the next proto.
 * The output stream abstracts over this, and allows callers to just think in terms of "frames",
 * the individual proto objects that we write one at a time.
 */
public protocol CloudBackupProtoOutputStream {

    /// Write a header (BakckupInfo) to the backup file.
    /// It is the caller's responsibility to ensure this is always written, and is the first thing written,
    /// in order to produce a valid backup file.
    func writeHeader(_ header: BackupProtoBackupInfo) -> CloudBackup.ProtoOutputStreamWriteResult

    /// Write a frame to the backup file.
    func writeFrame(_ frame: BackupProtoFrame) -> CloudBackup.ProtoOutputStreamWriteResult

    /// Closes the output stream.
    /// - Returns: URL of the file written to.
    func closeFileStream() -> URL
}

internal class CloudBackupProtoOutputStreamImpl: OWSChunkedOutputStream, CloudBackupProtoOutputStream {

    private var outputStream: OutputStream
    private var streamRunloop: RunLoop
    private var outputStreamDelegate: StreamDelegate
    private var fileUrl: URL

    internal init(
        outputStream: OutputStream,
        streamRunloop: RunLoop,
        outputStreamDelegate: StreamDelegate,
        fileURL: URL
    ) {
        self.outputStream = outputStream
        self.streamRunloop = streamRunloop
        self.outputStreamDelegate = outputStreamDelegate
        self.fileUrl = fileURL
        super.init(outputStream: outputStream)
    }

    internal func writeHeader(_ header: BackupProtoBackupInfo) -> CloudBackup.ProtoOutputStreamWriteResult {
        let bytes: Data
        do {
            bytes = try header.serializedData()
        } catch {
            return .protoSerializationError(error)
        }
        let byteLength = UInt32(bytes.count)
        do {
            try writeVariableLengthUInt32(byteLength)
            try writeData(bytes)
        } catch {
            return .fileIOError(error)
        }
        return .success
    }

    internal func writeFrame(_ frame: BackupProtoFrame) -> CloudBackup.ProtoOutputStreamWriteResult {
        let bytes: Data
        do {
            bytes = try frame.serializedData()
        } catch {
            return .protoSerializationError(error)
        }
        let byteLength = UInt32(bytes.count)
        do {
            try writeVariableLengthUInt32(byteLength)
            try writeData(bytes)
        } catch {
            return .fileIOError(error)
        }
        return .success
    }

    public func closeFileStream() -> URL {
        outputStream.remove(from: streamRunloop, forMode: .default)
        outputStream.close()
        return fileUrl
    }
}
