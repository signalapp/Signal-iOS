//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension BackupArchive {
    enum ProtoStream {
        enum OpenOutputStreamResult<StreamMetadata> {
            /// The contained stream was opened successfully.
            /// - Note
            /// Calling the contained `metadataProvider` provides point-in-time
            /// metadata for the stream; consequently, callers likely want to
            /// invoke it after finishing writing to the stream.
            case success(BackupArchiveProtoOutputStream, metadataProvider: () throws -> StreamMetadata)
            /// Unable to open a file stream due to I/O errors.
            case unableToOpenFileStream
        }

        enum OpenInputStreamResult {
            /// A stream was opened successfully.
            case success(BackupArchiveProtoInputStream, rawStream: TransformingInputStream)
            /// The provided target file was not found on disk.
            case fileNotFound
            /// Unable to open a file stream due to file I/O errors.
            case unableToOpenFileStream
            /// Unable to open an encrypted file stream due to HMAC validation
            /// failing.
            case hmacValidationFailedOnEncryptedFile
        }
    }
}

// MARK: -

/// Creates streams for reading and writing to a plaintext Backup file on-disk.
///
/// A Backup file is a sequence of concatenated serialized proto bytes delimited
/// by varint byte sizes, which tell us how much to read into memory to
/// deserialize the next proto. The streams provided by this type abstract over
/// this serialized format, allowing callers instead to think in terms of
/// "frames", or individual proto objects that we read or write individually.
///
/// - SeeAlso: ``BackupArchiveEncryptedProtoStreamProvider``
public class BackupArchivePlaintextProtoStreamProvider {
    typealias ProtoStream = BackupArchive.ProtoStream

    private let genericStreamProvider: GenericStreamProvider

    init() {
        self.genericStreamProvider = GenericStreamProvider()
    }

    /// Open an input stream to read a plaintext backup from a file on disk. The
    /// caller becomes the owner of the stream, and is responsible for closing
    /// it once finished.
    func openPlaintextOutputFileStream(
        exportProgress: BackupArchiveExportProgress?,
    ) -> ProtoStream.OpenOutputStreamResult<URL> {
        let transforms: [any StreamTransform] = [
            ChunkedOutputStreamTransform(),
        ]

        return genericStreamProvider.openOutputFileStream(
            transforms: transforms,
            exportProgress: exportProgress,
        )
    }

    /// Open an output stream to write a plaintext backup to a file on disk. The
    /// caller owns the returned stream, and is responsible for closing it once
    /// finished.
    func openPlaintextInputFileStream(
        fileUrl: URL,
        frameRestoreProgress: BackupArchiveImportFramesProgress?,
    ) -> ProtoStream.OpenInputStreamResult {
        let transforms: [any StreamTransform] = [
            frameRestoreProgress.map { InputProgressStreamTransform(frameRestoreProgress: $0) },
            ChunkedInputStreamTransform(),
        ].compacted()

        return genericStreamProvider.openInputFileStream(
            fileUrl: fileUrl,
            transforms: transforms,
        )
    }
}

/// Creates streams for reading and writing to an encrypted Backup file on-disk.
///
/// A Backup file is a sequence of concatenated serialized proto bytes delimited
/// by varint byte sizes, which tell us how much to read into memory to
/// deserialize the next proto. The streams provided by this type abstract over
/// this serialized format, allowing callers instead to think in terms of
/// "frames", or individual proto objects that we read or write individually.
///
/// - SeeAlso: ``BackupArchivePlaintextProtoStreamProvider``
public class BackupArchiveEncryptedProtoStreamProvider {
    typealias ProtoStream = BackupArchive.ProtoStream

    private let genericStreamProvider: GenericStreamProvider
    init() {
        self.genericStreamProvider = GenericStreamProvider()
    }

    /// Open an output stream to write an encrypted backup to a file on disk.
    /// The caller owns the returned stream, and is responsible for closing it
    /// once finished.
    func openEncryptedOutputFileStream(
        startTimestamp: Date,
        encryptionMetadata: BackupExportPurpose.EncryptionMetadata,
        exportProgress: BackupArchiveExportProgress?,
        attachmentByteCounter: BackupArchiveAttachmentByteCounter,
        tx: DBReadTransaction,
    ) -> ProtoStream.OpenOutputStreamResult<Upload.EncryptedBackupUploadMetadata> {
        let backupEncryptionKey = encryptionMetadata.encryptionKey
        do {
            let inputTrackingTransform = MetadataStreamTransform(calculateDigest: false)
            let outputTrackingTransform = MetadataStreamTransform(calculateDigest: true)

            let transforms: [any StreamTransform] = [
                inputTrackingTransform,
                ChunkedOutputStreamTransform(),
                try GzipStreamTransform(.compress),
                try EncryptingStreamTransform(
                    iv: Randomness.generateRandomBytes(UInt(Cryptography.Constants.aescbcIVLength)),
                    encryptionKey: backupEncryptionKey.aesKey,
                ),
                try HmacStreamTransform(hmacKey: backupEncryptionKey.hmacKey, operation: .generate),
                encryptionMetadata.metadataHeader.map(NonceHeaderOutputStreamTransform.init(metadataHeader:)),
                outputTrackingTransform,
            ].compacted()

            let outputStream: BackupArchiveProtoOutputStream
            let fileUrl: URL
            switch genericStreamProvider.openOutputFileStream(
                transforms: transforms,
                exportProgress: exportProgress,
            ) {
            case .success(let _outputStream, let _fileUrlProvider):
                outputStream = _outputStream
                fileUrl = try! _fileUrlProvider()
            case .unableToOpenFileStream:
                return .unableToOpenFileStream
            }

            return .success(
                outputStream,
                metadataProvider: {
                    return Upload.EncryptedBackupUploadMetadata(
                        exportStartTimestamp: startTimestamp,
                        fileUrl: fileUrl,
                        digest: try outputTrackingTransform.digest(),
                        encryptedDataLength: UInt32(clamping: outputTrackingTransform.count),
                        plaintextDataLength: UInt32(clamping: inputTrackingTransform.count),
                        attachmentByteSize: attachmentByteCounter.attachmentByteSize(),
                        nonceMetadata: encryptionMetadata.nonceMetadata,
                    )
                },
            )
        } catch {
            return .unableToOpenFileStream
        }
    }

    /// Open an input stream to read an encrypted backup from a file on disk.
    /// The caller becomes the owner of the stream, and is responsible for
    /// closing it once finished.
    func openEncryptedInputFileStream(
        fileUrl: URL,
        source: BackupImportSource,
        backupEncryptionKey: MessageBackupKey,
        frameRestoreProgress: BackupArchiveImportFramesProgress?,
        tx: DBReadTransaction,
    ) -> ProtoStream.OpenInputStreamResult {
        guard validateBackupHMAC(source: source, backupEncryptionKey: backupEncryptionKey, fileUrl: fileUrl, tx: tx) else {
            return .hmacValidationFailedOnEncryptedFile
        }

        do {
            let transforms: [any StreamTransform] = [
                NonceHeaderInputStreamTransform(source: source),
                frameRestoreProgress.map { InputProgressStreamTransform(frameRestoreProgress: $0) },
                try HmacStreamTransform(hmacKey: backupEncryptionKey.hmacKey, operation: .validate),
                try DecryptingStreamTransform(encryptionKey: backupEncryptionKey.aesKey),
                try GzipStreamTransform(.decompress),
                ChunkedInputStreamTransform(),
            ].compacted()

            return genericStreamProvider.openInputFileStream(
                fileUrl: fileUrl,
                transforms: transforms,
            )
        } catch {
            return .unableToOpenFileStream
        }
    }

    private func validateBackupHMAC(
        source: BackupImportSource,
        backupEncryptionKey: MessageBackupKey,
        fileUrl: URL,
        tx: DBReadTransaction,
    ) -> Bool {
        do {
            let inputStreamResult = genericStreamProvider.openInputFileStream(
                fileUrl: fileUrl,
                transforms: [
                    NonceHeaderInputStreamTransform(source: source),
                    try HmacStreamTransform(hmacKey: backupEncryptionKey.hmacKey, operation: .validate),
                ],
            )

            switch inputStreamResult {
            case .success(_, let rawInputStream):
                // Read through the input stream. The HmacStreamTransform will both build
                // an HMAC of the input data and read the HMAC from the end of the input file.
                // Once the end of the stream is reached, the transform will compare the
                // HMACs and throw an exception if they differ.
                while try rawInputStream.read(maxLength: 32 * 1024).count > 0 {}
                try rawInputStream.close()
                return true
            case .fileNotFound, .unableToOpenFileStream, .hmacValidationFailedOnEncryptedFile:
                return false
            }
        } catch {
            return false
        }
    }
}

// MARK: -

private class GenericStreamProvider {
    typealias ProtoStream = BackupArchive.ProtoStream

    init() {}

    func openOutputFileStream(
        transforms: [any StreamTransform],
        exportProgress: BackupArchiveExportProgress?,
    ) -> ProtoStream.OpenOutputStreamResult<URL> {
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

        let transformingOutputStream = TransformingOutputStream(
            transforms: transforms,
            outputStream: outputStream,
            runLoop: streamRunloop,
        )

        let backupOutputStream = BackupArchiveProtoOutputStream(
            outputStream: transformingOutputStream,
            exportProgress: exportProgress,
        )

        return .success(
            backupOutputStream,
            metadataProvider: { fileUrl },
        )
    }

    func openInputFileStream(
        fileUrl: URL,
        transforms: [any StreamTransform],
    ) -> ProtoStream.OpenInputStreamResult {
        guard OWSFileSystem.fileOrFolderExists(url: fileUrl) else {
            return .fileNotFound
        }
        guard let inputStream = InputStream(url: fileUrl) else {
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

        let transformableInputStream = TransformingInputStream(
            transforms: transforms,
            inputStream: inputStream,
            runLoop: streamRunloop,
        )

        let backupInputStream = BackupArchiveProtoInputStream(
            inputStream: transformableInputStream,
            inputStreamDelegate: inputStreamDelegate,
        )

        return .success(backupInputStream, rawStream: transformableInputStream)
    }

    private class StreamDelegate: NSObject, Foundation.StreamDelegate {
        private let _hadError = AtomicBool(false, lock: .sharedGlobal)
        var hadError: Bool { _hadError.get() }

        @objc
        func stream(_ stream: Stream, handle eventCode: Stream.Event) {
            if eventCode == .errorOccurred {
                _hadError.set(true)
            }
        }
    }
}

// MARK: -

/// Reports bytes read to a progress sink.
///
/// - Important
/// This transform tracks the size of data it receives; consequently, if it is
/// applied after transforms that affect the size of read data, such as
/// decompression or decryption, it may report an unexpected size.
private class InputProgressStreamTransform: StreamTransform {
    private let frameRestoreProgress: BackupArchiveImportFramesProgress

    init(frameRestoreProgress: BackupArchiveImportFramesProgress) {
        self.frameRestoreProgress = frameRestoreProgress
    }

    func transform(data: Data) throws -> Data {
        frameRestoreProgress.didReadBytes(count: data.count)
        return data
    }
}
