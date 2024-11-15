//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

extension MessageBackup {
    public enum ProtoStream {
        public typealias EncryptionMetadataProvider = () throws -> Upload.EncryptedBackupUploadMetadata

        public enum OpenOutputStreamResult<T> {
            /// A stream was opened successfully.
            case success(MessageBackupProtoOutputStream, T)
            /// Unable to open a file stream due to I/O errors.
            case unableToOpenFileStream
        }

        public enum OpenInputStreamResult {
            /// A stream was opened successfully.
            case success(MessageBackupProtoInputStream, rawStream: TransformingInputStream)
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

/// Creates streams for reading and writing to a plaintext Backup file on-disk.
///
/// A Backup file is a sequence of concatenated serialized proto bytes delimited
/// by varint byte sizes, which tell us how much to read into memory to
/// deserialize the next proto. The streams provided by this type abstract over
/// this serialized format, allowing callers instead to think in terms of
/// "frames", or individual proto objects that we read or write individually.
///
/// - SeeAlso: ``MessageBackupEncryptedProtoStreamProvider``
public protocol MessageBackupPlaintextProtoStreamProvider {
    typealias ProtoStream = MessageBackup.ProtoStream

    /// Open an output stream to write a plaintext backup to a file on disk. The
    /// caller owns the returned stream, and is responsible for closing it once
    /// finished.
    func openPlaintextOutputFileStream(
        progress: MessageBackupExportProgress,
        memorySampler: MemorySampler
    ) -> ProtoStream.OpenOutputStreamResult<URL>

    /// Open an input stream to read a plaintext backup from a file on disk. The
    /// caller becomes the owner of the stream, and is responsible for closing
    /// it once finished.
    func openPlaintextInputFileStream(
        fileUrl: URL,
        progress: MessageBackupImportProgress,
        memorySampler: MemorySampler
    ) -> ProtoStream.OpenInputStreamResult
}

/// Creates streams for reading and writing to an encrypted Backup file on-disk.
///
/// A Backup file is a sequence of concatenated serialized proto bytes delimited
/// by varint byte sizes, which tell us how much to read into memory to
/// deserialize the next proto. The streams provided by this type abstract over
/// this serialized format, allowing callers instead to think in terms of
/// "frames", or individual proto objects that we read or write individually.
///
/// - SeeAlso: ``MessageBackupPlaintextProtoStreamProvider``
public protocol MessageBackupEncryptedProtoStreamProvider {
    typealias ProtoStream = MessageBackup.ProtoStream

    /// Open an output stream to write an encrypted backup to a file on disk.
    /// The caller owns the returned stream, and is responsible for closing it
    /// once finished.
    func openEncryptedOutputFileStream(
        localAci: Aci,
        backupKey: BackupKey,
        progress: MessageBackupExportProgress,
        memorySampler: MemorySampler,
        tx: DBReadTransaction
    ) -> ProtoStream.OpenOutputStreamResult<ProtoStream.EncryptionMetadataProvider>

    /// Open an input stream to read an encrypted backup from a file on disk.
    /// The caller becomes the owner of the stream, and is responsible for
    /// closing it once finished.
    func openEncryptedInputFileStream(
        fileUrl: URL,
        localAci: Aci,
        backupKey: BackupKey,
        progress: MessageBackupImportProgress,
        memorySampler: MemorySampler,
        tx: DBReadTransaction
    ) -> ProtoStream.OpenInputStreamResult
}

// MARK: -

public class MessageBackupEncryptedProtoStreamProviderImpl: MessageBackupEncryptedProtoStreamProvider {
    private let backupKeyMaterial: MessageBackupKeyMaterial
    private let genericStreamProvider: GenericStreamProvider

    public init(backupKeyMaterial: MessageBackupKeyMaterial) {
        self.backupKeyMaterial = backupKeyMaterial
        self.genericStreamProvider = GenericStreamProvider()
    }

    public func openEncryptedOutputFileStream(
        localAci: Aci,
        backupKey: BackupKey,
        progress: MessageBackupExportProgress,
        memorySampler: MemorySampler,
        tx: any DBReadTransaction
    ) -> ProtoStream.OpenOutputStreamResult<ProtoStream.EncryptionMetadataProvider> {
        do {
            let messageBackupKey = try backupKey.asMessageBackupKey(for: localAci)
            let inputTrackingTransform = MetadataStreamTransform(calculateDigest: false)
            let outputTrackingTransform = MetadataStreamTransform(calculateDigest: true)

            let transforms: [any StreamTransform] = [
                MemorySamplerStreamTransform(memorySampler: memorySampler),
                inputTrackingTransform,
                ChunkedOutputStreamTransform(),
                try GzipStreamTransform(.compress),
                try EncryptingStreamTransform(
                    iv: Randomness.generateRandomBytes(UInt(Cryptography.Constants.aescbcIVLength)),
                    encryptionKey: Data(messageBackupKey.aesKey)
                ),
                try HmacStreamTransform(hmacKey: Data(messageBackupKey.hmacKey), operation: .generate),
                outputTrackingTransform
            ]

            let outputStream: MessageBackupProtoOutputStream
            let fileUrl: URL
            switch genericStreamProvider.openOutputFileStream(
                transforms: transforms,
                progress: progress
            ) {
            case .success(let _outputStream, let _fileUrl):
                outputStream = _outputStream
                fileUrl = _fileUrl
            case .unableToOpenFileStream:
                return .unableToOpenFileStream
            }

            return .success(
                outputStream,
                {
                    return Upload.EncryptedBackupUploadMetadata(
                        fileUrl: fileUrl,
                        digest: try outputTrackingTransform.digest(),
                        encryptedDataLength: UInt32(clamping: outputTrackingTransform.count),
                        plaintextDataLength: UInt32(clamping: inputTrackingTransform.count)
                    )
                }
            )
        } catch {
            return .unableToOpenFileStream
        }
    }

    public func openEncryptedInputFileStream(
        fileUrl: URL,
        localAci: Aci,
        backupKey: BackupKey,
        progress: MessageBackupImportProgress,
        memorySampler: MemorySampler,
        tx: any DBReadTransaction
    ) -> ProtoStream.OpenInputStreamResult {
        guard validateBackupHMAC(localAci: localAci, backupKey: backupKey, fileUrl: fileUrl, tx: tx) else {
            return .hmacValidationFailedOnEncryptedFile
        }

        do {
            let messageBackupKey = try backupKey.asMessageBackupKey(for: localAci)
            let transforms: [any StreamTransform] = [
                MemorySamplerStreamTransform(memorySampler: memorySampler),
                InputProgressStreamTransform(progress: progress),
                try HmacStreamTransform(hmacKey: Data(messageBackupKey.hmacKey), operation: .validate),
                try DecryptingStreamTransform(encryptionKey: Data(messageBackupKey.aesKey)),
                try GzipStreamTransform(.decompress),
                ChunkedInputStreamTransform(),
            ]

            return genericStreamProvider.openInputFileStream(
                fileUrl: fileUrl,
                transforms: transforms
            )
        } catch {
            return .unableToOpenFileStream
        }
    }

    private func validateBackupHMAC(
        localAci: Aci,
        backupKey: BackupKey,
        fileUrl: URL,
        tx: DBReadTransaction
    ) -> Bool {
        do {
            let messageBackupKey = try backupKey.asMessageBackupKey(for: localAci)
            let inputStreamResult = genericStreamProvider.openInputFileStream(
                fileUrl: fileUrl,
                transforms: [
                    try HmacStreamTransform(hmacKey: Data(messageBackupKey.hmacKey), operation: .validate)
                ]
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

public class MessageBackupPlaintextProtoStreamProviderImpl: MessageBackupPlaintextProtoStreamProvider {
    private let genericStreamProvider: GenericStreamProvider

    init() {
        self.genericStreamProvider = GenericStreamProvider()
    }

    public func openPlaintextOutputFileStream(
        progress: MessageBackupExportProgress,
        memorySampler: MemorySampler
    ) -> ProtoStream.OpenOutputStreamResult<URL> {
        let transforms: [any StreamTransform] = [
            MemorySamplerStreamTransform(memorySampler: memorySampler),
            ChunkedOutputStreamTransform(),
        ]

        return genericStreamProvider.openOutputFileStream(
            transforms: transforms,
            progress: progress
        )
    }

    public func openPlaintextInputFileStream(
        fileUrl: URL,
        progress: MessageBackupImportProgress,
        memorySampler: MemorySampler
    ) -> ProtoStream.OpenInputStreamResult {
        let transforms: [any StreamTransform] = [
            MemorySamplerStreamTransform(memorySampler: memorySampler),
            InputProgressStreamTransform(progress: progress),
            ChunkedInputStreamTransform(),
        ]

        return genericStreamProvider.openInputFileStream(
            fileUrl: fileUrl,
            transforms: transforms
        )
    }
}

// MARK: -

private class GenericStreamProvider {
    typealias ProtoStream = MessageBackup.ProtoStream

    init() {}

    func openOutputFileStream(
        transforms: [any StreamTransform],
        progress: MessageBackupExportProgress
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
            runLoop: streamRunloop
        )

        let messageBackupOutputStream = MessageBackupProtoOutputStreamImpl(
            outputStream: transformingOutputStream,
            progress: progress
        )

        return .success(messageBackupOutputStream, fileUrl)
    }

    func openInputFileStream(
        fileUrl: URL,
        transforms: [any StreamTransform]
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
            runLoop: streamRunloop
        )

        let messageBackupInputStream = MessageBackupProtoInputStreamImpl(
            inputStream: transformableInputStream,
            inputStreamDelegate: inputStreamDelegate
        )

        return .success(messageBackupInputStream, rawStream: transformableInputStream)
    }

    private class StreamDelegate: NSObject, Foundation.StreamDelegate {
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

private class InputProgressStreamTransform: StreamTransform {

    private let progress: MessageBackupImportProgress

    init(progress: MessageBackupImportProgress) {
        self.progress = progress
    }

    func transform(data: Data) throws -> Data {
        progress.didReadBytes(byteLength: Int64(data.byteLength))
        return data
    }
}

/// We sample memory after every frame we write, just because that's a convenient hook for sampling.
private class MemorySamplerStreamTransform: StreamTransform {

    private let memorySampler: MemorySampler

    init(memorySampler: MemorySampler) {
        self.memorySampler = memorySampler
    }

    func transform(data: Data) throws -> Data {
        memorySampler.sample()
        return data
    }
}
