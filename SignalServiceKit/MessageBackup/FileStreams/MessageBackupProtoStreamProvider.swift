//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension MessageBackup {
    public typealias MetadataProvider = () throws -> Upload.BackupUploadMetadata
    public enum OpenProtoOutputStreamResult {
        case success(MessageBackupProtoOutputStream, MetadataProvider)
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
    func openOutputFileStream(localAci: Aci, tx: DBReadTransaction) -> MessageBackup.OpenProtoOutputStreamResult

    /// Open an input stream to read a backup from a file on disk.
    /// The caller becomes the owner of the stream, and is responsible for closing it once finished.
    func openInputFileStream(localAci: Aci, fileURL: URL, tx: DBReadTransaction) -> MessageBackup.OpenProtoInputStreamResult
}

public class MessageBackupProtoStreamProviderImpl: MessageBackupProtoStreamProvider {

    let backupKeyMaterial: MessageBackupKeyMaterial
    public init(backupKeyMaterial: MessageBackupKeyMaterial) {
        self.backupKeyMaterial = backupKeyMaterial
    }

    public func openOutputFileStream(localAci: Aci, tx: DBReadTransaction) -> MessageBackup.OpenProtoOutputStreamResult {
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

        do {
            let inputTrackingTransform = TrackingStreamTransform()
            let outputTrackingTransform = TrackingStreamTransform(calculateDigest: true)
            let transformingOutputStream = TransformingOutputStream(
                transforms: [
                    inputTrackingTransform,
                    ChunkedOutputStreamTransform(),
                    try GzipStreamTransform(.compress),
                    try backupKeyMaterial.createEncryptingStreamTransform(localAci: localAci, tx: tx),
                    outputTrackingTransform
                ],
                outputStream: outputStream,
                runLoop: streamRunloop
            )

            let messageBackupOutputStream = MessageBackupProtoOutputStreamImpl(
                outputStream: transformingOutputStream,
                outputStreamDelegate: outputStreamDelegate,
                fileURL: fileUrl
            )

            return .success(messageBackupOutputStream, {
                return Upload.BackupUploadMetadata(
                    fileUrl: fileUrl,
                    digest: try outputTrackingTransform.digest(),
                    encryptedDataLength: UInt32(clamping: outputTrackingTransform.count),
                    plaintextDataLength: UInt32(clamping: inputTrackingTransform.count)
                )
            })
        } catch {
            return .unableToOpenFileStream
        }
    }

    public func openInputFileStream(localAci: Aci, fileURL: URL, tx: DBReadTransaction) -> MessageBackup.OpenProtoInputStreamResult {
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

        do {
            let transformableInputStream = TransformingInputStream(
                transforms: [
                    try backupKeyMaterial.createDecryptingStreamTransform(localAci: localAci, tx: tx),
                    try GzipStreamTransform(.decompress),
                    ChunkedInputStreamTransform(),
                ],
                inputStream: inputStream,
                runLoop: streamRunloop
            )

            let messageBackupInputStream = MessageBackupProtoInputStreamImpl(
                inputStream: transformableInputStream,
                inputStreamDelegate: inputStreamDelegate
            )
            return .success(messageBackupInputStream)
        } catch {
            return .unableToOpenFileStream
        }
    }

    fileprivate class StreamDelegate: NSObject, Foundation.StreamDelegate {
        private let _hadError = AtomicBool(false, lock: .sharedGlobal)
        public var hadError: Bool { _hadError.get() }

        @objc
        public func stream(_ stream: Stream, handle eventCode: Stream.Event) {
            if eventCode == .errorOccurred {
                _hadError.set(true)
            }
        }
    }
}

private class TrackingStreamTransform: StreamTransform, FinalizableStreamTransform {
    public var hasFinalized: Bool = false
    public let hasPendingBytes = false

    private var digestContext: SHA256DigestContext?
    private var _digest: Data?
    public func digest() throws -> Data {
        guard calculateDigest else {
            throw OWSAssertionError("Not configured to calculate digest")
        }
        guard hasFinalized, let digest = _digest else {
            throw OWSAssertionError("Reading digest before finalized")
        }
        return digest
    }

    private let calculateDigest: Bool
    init(calculateDigest: Bool = false) {
        self.calculateDigest = calculateDigest
        if calculateDigest {
            self.digestContext = SHA256DigestContext()
        }
    }

    public private(set) var count: Int = 0

    public func transform(data: Data) throws -> Data {
        try digestContext?.update(data)
        count += data.count
        return data
    }

    public func readBufferedData() throws -> Data { .init() }

    public func finalize() throws -> Data {
        self.hasFinalized = true
        self._digest = try self.digestContext?.finalize()
        return Data()
    }
}
