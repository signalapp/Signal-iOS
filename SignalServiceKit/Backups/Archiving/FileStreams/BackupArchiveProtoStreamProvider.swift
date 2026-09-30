//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

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
    private let genericProtoStreamProvider: GenericProtoStreamProvider

    init() {
        self.genericProtoStreamProvider = GenericProtoStreamProvider()
    }

    /// Open an input stream to read a plaintext backup from a file on disk. The
    /// caller becomes the owner of the stream, and is responsible for closing
    /// it once finished.
    func openPlaintextOutputFileStream(
        exportProgress: BackupArchiveExportProgress?,
    ) throws -> (
        protoOutputStream: BackupArchiveProtoOutputStream,
        fileUrl: URL,
    ) {
        return try genericProtoStreamProvider.openOutputFileStream(
            additionalTransforms: [],
            exportProgress: exportProgress,
        )
    }

    /// Open an output stream to write a plaintext backup to a file on disk. The
    /// caller owns the returned stream, and is responsible for closing it once
    /// finished.
    func openPlaintextInputFileStream(
        fileUrl: URL,
        frameRestoreProgress: BackupArchiveImportFramesProgress?,
    ) throws -> BackupArchiveProtoInputStream {
        let transforms: [any StreamTransform] = [
            frameRestoreProgress.map { InputProgressStreamTransform(frameRestoreProgress: $0) },
            ChunkedInputStreamTransform(),
        ].compacted()

        let (protoInputStream, _) = try genericProtoStreamProvider.openInputFileStream(
            fileUrl: fileUrl,
            transforms: transforms,
        )

        return protoInputStream
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
    private let genericProtoStreamProvider: GenericProtoStreamProvider
    private let logger = PrefixedLogger(prefix: "[Backups]")

    init() {
        self.genericProtoStreamProvider = GenericProtoStreamProvider()
    }

    /// Open an output stream to write an encrypted backup to a file on disk.
    /// The caller owns the returned stream, and is responsible for closing it
    /// once finished.
    func openEncryptedOutputFileStream(
        startDate: Date,
        encryptionMetadata: BackupExportPurpose.EncryptionMetadata,
        exportProgress: BackupArchiveExportProgress?,
        attachmentByteCounter: BackupArchiveAttachmentByteCounter,
        tx: DBReadTransaction,
    ) throws -> (
        protoOutputStream: BackupArchiveProtoOutputStream,
        streamMetadataProvider: () throws -> Upload.EncryptedBackupUploadMetadata,
    ) {
        let backupEncryptionKey = encryptionMetadata.encryptionKey
        do {
            let outputTrackingTransform = MetadataStreamTransform()

            let transforms: [any StreamTransform] = [
                try GzipStreamTransform(.compress),
                try EncryptingStreamTransform(
                    iv: Randomness.generateRandomBytes(UInt(Cryptography.Constants.aescbcIVLength)),
                    encryptionKey: backupEncryptionKey.aesKey,
                ),
                try HmacStreamTransform(hmacKey: backupEncryptionKey.hmacKey, operation: .generate),
                encryptionMetadata.metadataHeader.map(NonceHeaderOutputStreamTransform.init(metadataHeader:)),
                outputTrackingTransform,
            ].compacted()

            let protoOutputStream: BackupArchiveProtoOutputStream
            let fileUrl: URL
            (
                protoOutputStream,
                fileUrl,
            ) = try genericProtoStreamProvider.openOutputFileStream(
                additionalTransforms: transforms,
                exportProgress: exportProgress,
            )

            return (
                protoOutputStream: protoOutputStream,
                streamMetadataProvider: {
                    return Upload.EncryptedBackupUploadMetadata(
                        exportStartDate: startDate,
                        fileUrl: fileUrl,
                        digest: try outputTrackingTransform.digest(),
                        encryptedDataLength: UInt32(clamping: outputTrackingTransform.count),
                        remoteAttachmentByteSize: attachmentByteCounter.remoteAttachmentByteSize(),
                        localAttachmentByteSize: attachmentByteCounter.localAttachmentByteSize(),
                        nonceMetadata: encryptionMetadata.nonceMetadata,
                    )
                },
            )
        } catch {
            logger.error("Failed to open encrypted output file stream! \(error)")
            throw error
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
    ) throws -> BackupArchiveProtoInputStream {
        guard validateBackupHMAC(source: source, backupEncryptionKey: backupEncryptionKey, fileUrl: fileUrl, tx: tx) else {
            throw OWSGenericError("HMAC validation failed on encrypted file!")
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

            let (protoInputStream, _) = try genericProtoStreamProvider.openInputFileStream(
                fileUrl: fileUrl,
                transforms: transforms,
            )

            return protoInputStream
        } catch {
            throw OWSGenericError("Failed to construct and open input proto stream!")
        }
    }

    private func validateBackupHMAC(
        source: BackupImportSource,
        backupEncryptionKey: MessageBackupKey,
        fileUrl: URL,
        tx: DBReadTransaction,
    ) -> Bool {
        do {
            let (_, rawInputStream) = try genericProtoStreamProvider.openInputFileStream(
                fileUrl: fileUrl,
                transforms: [
                    NonceHeaderInputStreamTransform(source: source),
                    try HmacStreamTransform(hmacKey: backupEncryptionKey.hmacKey, operation: .validate),
                ],
            )

            // Read through the input stream. The HmacStreamTransform will both build
            // an HMAC of the input data and read the HMAC from the end of the input file.
            // Once the end of the stream is reached, the transform will compare the
            // HMACs and throw an exception if they differ.
            while try rawInputStream.read(maxLength: 32 * 1024).count > 0 {}
            rawInputStream.close()
            return true
        } catch {
            return false
        }
    }
}

// MARK: -

/// Responsible for creating input and output streams for varint-prefixed
/// serialized-proto Backup files, with optional additional transforms.
///
/// - SeeAlso `BackupArchiveProtoOutputStream`
private class GenericProtoStreamProvider {
    init() {}

    /// - Important
    /// The "varint-prefix"-ing of serialized protos is implemented via a
    /// `ChunkedOutputStreamTransform`, which is prepended to the given
    /// `additionalTransforms`.
    func openOutputFileStream(
        additionalTransforms: [any StreamTransform],
        exportProgress: BackupArchiveExportProgress?,
    ) throws -> (
        protoOutputStream: BackupArchiveProtoOutputStream,
        fileUrl: URL,
    ) {
        owsPrecondition(!additionalTransforms.contains(where: { $0 is ChunkedOutputStreamTransform }))

        let transforms = [ChunkedOutputStreamTransform()] + additionalTransforms

        let fileUrl = OWSFileSystem.temporaryFileUrl(
            fileExtension: nil,
            isAvailableWhileDeviceLocked: true,
        )

        guard let outputStream = OutputStream(url: fileUrl, append: false) else {
            throw OWSGenericError("Failed to open output stream!")
        }

        outputStream.open()

        guard outputStream.streamStatus == .open else {
            throw OWSGenericError("Output stream not open after calling .open()!")
        }

        // This type requires a ChunkedOutputStreamTransform in the given
        // transforms; enforced above.
        let protoOutputStream = BackupArchiveProtoOutputStream(
            transforms: transforms,
            outputStream: outputStream,
            exportProgress: exportProgress,
        )

        return (
            protoOutputStream: protoOutputStream,
            fileUrl: fileUrl,
        )
    }

    func openInputFileStream(
        fileUrl: URL,
        transforms: [any StreamTransform],
    ) throws -> (
        protoInputStream: BackupArchiveProtoInputStream,
        rawInputStream: TransformingInputStream,
    ) {
        guard OWSFileSystem.fileOrFolderExists(url: fileUrl) else {
            throw OWSGenericError("Missing input file!")
        }

        guard let inputStream = InputStream(url: fileUrl) else {
            throw OWSGenericError("Failed to open input stream!")
        }

        inputStream.open()

        guard inputStream.streamStatus == .open else {
            throw OWSGenericError("Input stream not open after calling .open()!")
        }

        let transformableInputStream = TransformingInputStream(
            transforms: transforms,
            inputStream: inputStream,
        )

        let protoInputStream = BackupArchiveProtoInputStream(
            inputStream: transformableInputStream,
        )

        return (
            protoInputStream: protoInputStream,
            rawInputStream: transformableInputStream,
        )
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
