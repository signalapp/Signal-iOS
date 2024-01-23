//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension MessageBackup {
    public enum OpenProtoOutputStreamResult {
        case success(MessageBackupProtoOutputStream)
        /// Unable to open a file stream due to file I/O errors.
        case unableToOpenFileStream
    }

    public enum OpenProtoInputStreamResult {
        case success(MessageBackupProtoInputStream)
        /// The provided target file was not found on disk.
        case fileNotFound
        /// Unable to open a file stream due to file I/O errors.
        case unableToOpenFileStream
    }
}

/**
 * Creates input and output streams for reading and writing to the backup file on disk.
 *
 * The backup file is just a sequence of serialized proto bytes, back to back, delimited by varint
 * byte sizes so we know how much to read into memory to deserialize the next proto.
 * The input and output streams abstract over this, and allow callers to just think in terms of "frames",
 * the individual proto objects that we read and write one at a time.
 */
public protocol MessageBackupProtoStreamProvider {

    /// Open an output stream to write a backup to a file on disk.
    /// The caller becomes the owner of the stream, and is responsible for closing it once finished.
    func openOutputFileStream() -> MessageBackup.OpenProtoOutputStreamResult

    /// Open an input stream to read a backup from a file on disk.
    /// The caller becomes the owner of the stream, and is responsible for closing it once finished.
    func openInputFileStream(fileURL: URL) -> MessageBackup.OpenProtoInputStreamResult
}

public class MessageBackupProtoStreamProviderImpl: MessageBackupProtoStreamProvider {

    public init() {}

    public func openOutputFileStream() -> MessageBackup.OpenProtoOutputStreamResult {
        let fileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
        guard let outputStream = OutputStream(url: fileUrl, append: false) else {
            return .unableToOpenFileStream
        }
        let outputStreamDelegate = StreamDelegate()
        outputStream.delegate = outputStreamDelegate
        let streamRunloop = RunLoop.current
        outputStream.schedule(in: streamRunloop, forMode: .default)
        outputStream.open()
        guard outputStream.streamStatus == .open else {
            return .unableToOpenFileStream
        }

        let messageBackupOutputStream = MessageBackupProtoOutputStreamImpl(
            outputStream: outputStream,
            streamRunloop: streamRunloop,
            outputStreamDelegate: outputStreamDelegate,
            fileURL: fileUrl
        )
        return .success(messageBackupOutputStream)
    }

    public func openInputFileStream(fileURL: URL) -> MessageBackup.OpenProtoInputStreamResult {
        guard OWSFileSystem.fileOrFolderExists(url: fileURL) else {
            return .fileNotFound
        }
        guard let inputStream = InputStream(url: fileURL) else {
            return .unableToOpenFileStream
        }
        let inputStreamDelegate = StreamDelegate()
        inputStream.delegate = inputStreamDelegate
        let streamRunloop = RunLoop.current
        inputStream.schedule(in: streamRunloop, forMode: .default)
        inputStream.open()
        guard inputStream.streamStatus == .open else {
            return .unableToOpenFileStream
        }

        let messageBackupInputStream = MessageBackupProtoInputStreamImpl(
            inputStream: inputStream,
            streamRunloop: streamRunloop,
            inputStreamDelegate: inputStreamDelegate
        )
        return .success(messageBackupInputStream)
    }

    fileprivate class StreamDelegate: NSObject, Foundation.StreamDelegate {
        private let _hadError = AtomicBool(false)
        public var hadError: Bool { _hadError.get() }

        @objc
        public func stream(_ stream: Stream, handle eventCode: Stream.Event) {
            if eventCode == .errorOccurred {
                _hadError.set(true)
            }
        }
    }
}
