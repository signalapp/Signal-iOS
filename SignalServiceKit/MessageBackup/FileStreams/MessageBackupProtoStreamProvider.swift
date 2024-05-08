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

        /// Unable to open a file stream due to HMAC validation failing on the encrypted file
        case unableToDecryptFile
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
            let inputTrackingTransform = MetadataStreamTransform()
            let outputTrackingTransform = MetadataStreamTransform(calculateDigest: true)
            let transformingOutputStream = TransformingOutputStream(
                transforms: [
                    inputTrackingTransform,
                    ChunkedOutputStreamTransform(),
                    try GzipStreamTransform(.compress),
                    try backupKeyMaterial.createEncryptingStreamTransform(localAci: localAci, tx: tx),
                    try backupKeyMaterial.createHmacGeneratingStreamTransform(localAci: localAci, tx: tx),
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

        guard validateBackupHMAC(localAci: localAci, fileURL: fileURL, tx: tx) else {
            return .unableToDecryptFile
        }

        do {
            let inputStreamDelegate = StreamDelegate()
            guard let transformableInputStream = openTransformingInputFileStream(
                localAci: localAci,
                fileURL: fileURL,
                inputStreamDelegate: inputStreamDelegate,
                transforms: [
                    try backupKeyMaterial.createHmacValidatingStreamTransform(localAci: localAci, tx: tx),
                    try backupKeyMaterial.createDecryptingStreamTransform(localAci: localAci, tx: tx),
                    try GzipStreamTransform(.decompress),
                    ChunkedInputStreamTransform(),
                ],
                tx: tx
            ) else {
                return .unableToOpenFileStream
            }
            let messageBackupInputStream = MessageBackupProtoInputStreamImpl(
                inputStream: transformableInputStream,
                inputStreamDelegate: inputStreamDelegate
            )
            return .success(messageBackupInputStream)
        } catch {
            return .unableToOpenFileStream
        }
    }

    private func openTransformingInputFileStream(
        localAci: Aci,
        fileURL: URL,
        inputStreamDelegate: StreamDelegate?,
        transforms: [any StreamTransform],
        tx: DBReadTransaction
    ) -> TransformingInputStream? {
        guard let inputStream = InputStream(url: fileURL) else {
            return nil
        }
        inputStream.delegate = inputStreamDelegate
        let streamRunloop = RunLoop.current
        inputStream.schedule(in: streamRunloop, forMode: .default)
        inputStream.open()
        guard inputStream.streamStatus == .open else {
            return nil
        }

        return TransformingInputStream(
            transforms: transforms,
            inputStream: inputStream,
            runLoop: streamRunloop
        )
    }

    private func validateBackupHMAC(localAci: Aci, fileURL: URL, tx: DBReadTransaction) -> Bool {
        do {
            guard let inputStream = openTransformingInputFileStream(
                localAci: localAci,
                fileURL: fileURL,
                inputStreamDelegate: nil,
                transforms: [
                    try backupKeyMaterial.createHmacValidatingStreamTransform(localAci: localAci, tx: tx)
                ],
                tx: tx
            ) else {
                owsFailDebug("Failed to open output stream to validate backup.")
                return false
            }

            // Read through the input stream. The HmacStreamTransform will both build
            // an HMAC of the input data and read the HMAC from the end of the input file.
            // Once the end of the stream is reached, the transform will compare the
            // HMACs and throw an exception if they differ.
            while try inputStream.read(maxLength: 32 * 1024).count > 0 { }
            try inputStream.close()
            return true
        } catch {
            return false
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
