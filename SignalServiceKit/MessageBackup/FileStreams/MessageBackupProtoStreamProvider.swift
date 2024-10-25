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
    func openPlaintextOutputFileStream() -> ProtoStream.OpenOutputStreamResult<URL>

    /// Open an input stream to read a plaintext backup from a file on disk. The
    /// caller becomes the owner of the stream, and is responsible for closing
    /// it once finished.
    func openPlaintextInputFileStream(fileUrl: URL) -> ProtoStream.OpenInputStreamResult
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
        mode: MessageBackup.EncryptionMode,
        tx: DBReadTransaction
    ) -> ProtoStream.OpenOutputStreamResult<ProtoStream.EncryptionMetadataProvider>

    /// Open an input stream to read an encrypted backup from a file on disk.
    /// The caller becomes the owner of the stream, and is responsible for
    /// closing it once finished.
    func openEncryptedInputFileStream(
        fileUrl: URL,
        localAci: Aci,
        mode: MessageBackup.EncryptionMode,
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
        mode: MessageBackup.EncryptionMode,
        tx: any DBReadTransaction
    ) -> ProtoStream.OpenOutputStreamResult<ProtoStream.EncryptionMetadataProvider> {
        do {
            let inputTrackingTransform = MetadataStreamTransform(calculateDigest: false)
            let outputTrackingTransform = MetadataStreamTransform(calculateDigest: true)

            let transforms: [any StreamTransform] = [
                inputTrackingTransform,
                ChunkedOutputStreamTransform(),
                try GzipStreamTransform(.compress),
                try backupKeyMaterial.createEncryptingStreamTransform(localAci: localAci, mode: mode, tx: tx),
                try backupKeyMaterial.createHmacGeneratingStreamTransform(localAci: localAci, mode: mode, tx: tx),
                outputTrackingTransform
            ]

            let outputStream: MessageBackupProtoOutputStream
            let fileUrl: URL
            switch genericStreamProvider.openOutputFileStream(
                transforms: transforms
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
        mode: MessageBackup.EncryptionMode,
        tx: any DBReadTransaction
    ) -> ProtoStream.OpenInputStreamResult {
        guard validateBackupHMAC(localAci: localAci, mode: mode, fileUrl: fileUrl, tx: tx) else {
            return .hmacValidationFailedOnEncryptedFile
        }

        do {
            let transforms: [any StreamTransform] = [
                try backupKeyMaterial.createHmacValidatingStreamTransform(localAci: localAci, mode: mode, tx: tx),
                try backupKeyMaterial.createDecryptingStreamTransform(localAci: localAci, mode: mode, tx: tx),
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
        mode: MessageBackup.EncryptionMode,
        fileUrl: URL,
        tx: DBReadTransaction
    ) -> Bool {
        do {
            let inputStreamResult = genericStreamProvider.openInputFileStream(
                fileUrl: fileUrl,
                transforms: [
                    try backupKeyMaterial.createHmacGeneratingStreamTransform(
                        localAci: localAci,
                        mode: mode,
                        tx: tx
                    )
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

    public func openPlaintextOutputFileStream() -> ProtoStream.OpenOutputStreamResult<URL> {
        let transforms: [any StreamTransform] = [
            ChunkedOutputStreamTransform(),
        ]

        return genericStreamProvider.openOutputFileStream(
            transforms: transforms
        )
    }

    public func openPlaintextInputFileStream(fileUrl: URL) -> ProtoStream.OpenInputStreamResult {
        let transforms: [any StreamTransform] = [
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
        transforms: [any StreamTransform]
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
            outputStream: transformingOutputStream
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
