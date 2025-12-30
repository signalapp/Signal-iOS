//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum Upload {
    public static let uploadQueue = ConcurrentTaskQueue(concurrentLimit: CurrentAppContext().isNSE ? 2 : 12)

    public enum Constants {
        public static let attachmentUploadProgressNotification = NSNotification.Name("AttachmentUploadProgressNotification")
        public static let uploadProgressKey = "UploadProgressKey"
        public static let uploadAttachmentIDKey = "UploadAttachmentIDKey"

        /// If within this window, we can reause existing attachment transit tier uploads for resending.
        public static let uploadReuseWindow: TimeInterval = 60 * 60 * 24 * 3 // 3 days
        public static let uploadFormReuseWindow: TimeInterval = 60 * 60 * 24 * 6 // 6 days

        public static let maxUploadAttempts = 5
    }

    public enum FormSource {
        case remote
        case local(Upload.Form)
    }

    public struct Form: Codable {
        private enum CodingKeys: String, CodingKey {
            case headers = "headers"
            case signedUploadLocation = "signedUploadLocation"
            case cdnKey = "key"
            case cdnNumber = "cdn"
        }

        let headers: HttpHeaders
        let signedUploadLocation: String
        let cdnKey: String
        let cdnNumber: UInt32
    }

    // MARK: -

    public enum FailureMode: Equatable {
        public enum RetryMode: Equatable {
            /// This was a temporary failure, such as a network
            /// timeout, so an immediate retry should be possible
            case immediately
            /// The remote server sent back a retry-after header that should be honored
            /// when attempting a backoff before retry
            case afterServerRequestedDelay(TimeInterval)
            /// An error was encountered and the server didn't provide a backoff, so
            /// use the internal exponential backoff
            case afterBackoff
        }

        // The overall upload has hit the max number of retries.
        case noMoreRetries

        // Attempt to resume the current upload from the last known good state.
        case resume(RetryMode)

        // Restart the upload by discarding any current upload progres and
        // fetching a new upload form.
        case restart(RetryMode)
    }

    public enum ResumeProgress {
        // There was an issue with the resume data, discard the current upload
        // form and restart the upload with a new form
        case restart

        // The endpoint reported a complete upload.
        case complete

        // Contains the number of bytes the upload endpoint has received.  This
        // can be 0 bytes, which is effectively a new upload, but can use the
        // existing upload form.
        case uploaded(Int)
    }

    public enum Error: Swift.Error, IsRetryableProvider, LocalizedError, Equatable {
        case invalidUploadURL
        case networkError
        case networkTimeout
        case uploadFailure(recovery: FailureMode)
        case partialUpload(bytesUploaded: UInt32)
        case unsupportedEndpoint
        case unexpectedResponseStatusCode(Int)
        case missingFile
        case unknown

        public var isRetryableProvider: Bool {
            switch self {
            case .invalidUploadURL, .uploadFailure, .partialUpload, .unsupportedEndpoint, .unexpectedResponseStatusCode, .networkTimeout, .networkError, .missingFile, .unknown:
                return false
            }
        }

        public var errorDescription: String? {
            localizedDescription
        }

        public var localizedDescription: String {
            return OWSLocalizedString(
                "ERROR_MESSAGE_ATTACHMENT_UPLOAD_FAILED",
                comment: "Error message indicating that attachment upload(s) failed.",
            )
        }
    }

    public struct EncryptedBackupUploadMetadata: UploadMetadata {
        /// When we started the export of this backup.
        public let exportStartTimestamp: Date

        /// File URL of the data consisting of "iv  + encrypted data + hmac"
        public let fileUrl: URL

        /// The digest of the encrypted file.  The encrypted file consist of "iv + encrypted data + hmac"
        public let digest: Data

        /// The length of the encrypted data, consiting of "iv  + encrypted data + hmac"
        public let encryptedDataLength: UInt32

        /// The length of the unencrypted data
        public let plaintextDataLength: UInt32

        /// The total size of all backup-able attachments in the backup.
        /// Does NOT take into account current backup plan state; just per-attachment
        /// backup eligibility.
        public let attachmentByteSize: UInt64

        /// Metadata related to the SVRB nonce used for forward secrecy that should be persisted
        /// after upload success.
        let nonceMetadata: BackupExportPurpose.NonceMetadata?

        /// We don't enforce a size limit locally for backups; we let the server
        /// enforce the limit and fail the upload if we surpass it.
        public static var maxUploadSizeBytes: UInt { .max }
        public static var maxPlaintextSizeBytes: UInt { .max }
    }

    public struct LocalUploadMetadata: AttachmentUploadMetadata, Codable {
        /// File URL of the data consisting of "iv  + encrypted data + hmac"
        public let fileUrl: URL

        /// encryption key + hmac
        public let key: Data

        /// The digest of the encrypted file.  The encrypted file consist of "iv + encrypted data + hmac"
        public let digest: Data

        /// The length of the encrypted data, consiting of "iv  + encrypted data + hmac"
        public let encryptedDataLength: UInt32

        /// The length of the unencrypted data
        public let plaintextDataLength: UInt32

        public var isReusedTransitTierUpload: Bool { false }

        public static var maxUploadSizeBytes: UInt { OWSMediaUtils.kMaxAttachmentUploadSizeBytes }
        public static var maxPlaintextSizeBytes: UInt { OWSMediaUtils.kMaxFileSizeGeneric }
    }

    public struct LinkNSyncUploadMetadata: UploadMetadata {
        /// File URL of the link'n'sync transient backup.
        public let fileUrl: URL
        /// The length of the file.
        public let encryptedDataLength: UInt32

        /// We don't enforce a size limit locally for backups; we let the server
        /// enforce the limit and fail the upload if we surpass it.
        public static var maxUploadSizeBytes: UInt { .max }
        public static var maxPlaintextSizeBytes: UInt { .max }
    }

    public struct ReusedUploadMetadata: AttachmentUploadMetadata {
        public let cdnKey: String

        public let cdnNumber: UInt32

        /// encryption key + hmac
        public let key: Data

        /// The digest of the encrypted file.  The encrypted file consist of "iv + encrypted data + hmac"
        public let digest: Data

        /// The length of the unencrypted data
        public let plaintextDataLength: UInt32

        /// The length of the encrypted data, consiting of "iv  + encrypted data + hmac"
        public let encryptedDataLength: UInt32

        public var isReusedTransitTierUpload: Bool { true }

        public static var maxUploadSizeBytes: UInt { OWSMediaUtils.kMaxAttachmentUploadSizeBytes }
        public static var maxPlaintextSizeBytes: UInt { OWSMediaUtils.kMaxFileSizeGeneric }
    }

    public struct Result<Metadata: UploadMetadata> {
        let cdnKey: String
        let cdnNumber: UInt32
        let localUploadMetadata: Metadata

        // Timestamp the upload attempt began
        let beginTimestamp: UInt64

        // Timestamp the upload attempt completed
        let finishTimestamp: UInt64
    }

    public struct AttachmentResult {
        let cdnKey: String
        let cdnNumber: UInt32
        let localUploadMetadata: AttachmentUploadMetadata

        // Timestamp the upload attempt began
        let beginTimestamp: UInt64

        // Timestamp the upload attempt completed
        let finishTimestamp: UInt64
    }

    public struct Attempt<Metadata: UploadMetadata> {
        let cdnKey: String
        let cdnNumber: UInt32
        /// File URL of the data consisting of "iv  + encrypted data + hmac"
        let fileUrl: URL
        /// The length of the encrypted data, consiting of "iv  + encrypted data + hmac"
        let encryptedDataLength: UInt32
        let localMetadata: Metadata
        let beginTimestamp: UInt64
        let endpoint: UploadEndpoint
        let uploadLocation: URL
        let isResumedUpload: Bool
        let logger: PrefixedLogger
    }
}

extension Upload.LocalUploadMetadata {

    static func validateAndBuild(
        fileUrl: URL,
        metadata: EncryptionMetadata,
    ) throws -> Upload.LocalUploadMetadata {
        guard
            let encryptedLength = UInt32(exactly: metadata.encryptedLength),
            encryptedLength > 0,
            let plaintextLength = UInt32(exactly: metadata.plaintextLength),
            plaintextLength > 0
        else {
            throw OWSAssertionError("Invalid length.")
        }

        guard
            plaintextLength <= Self.maxPlaintextSizeBytes,
            encryptedLength <= Self.maxUploadSizeBytes
        else {
            throw OWSAssertionError("Data is too large: \(encryptedLength).")
        }

        let digest = metadata.digest

        return Upload.LocalUploadMetadata(
            fileUrl: fileUrl,
            key: metadata.key.combinedKey,
            digest: digest,
            encryptedDataLength: encryptedLength,
            plaintextDataLength: plaintextLength,
        )
    }
}

extension UploadEndpoint {
    func readUploadFileChunk(
        fileSystem: Upload.Shims.FileSystem,
        url: URL,
        startIndex chunkStartIndex: Int,
    ) throws(Upload.Error) -> (data: Data, truncated: Bool) {
        guard fileSystem.fileOrFolderExists(url: url) else {
            throw .missingFile
        }

        let fileData: Data
        do {
            fileData = try fileSystem.readMemoryMappedFileData(url: url)
        } catch {
            Logger.error("Unable to map upload file into memory")
            throw .missingFile
        }

        let remainingData = fileData.dropFirst(chunkStartIndex)
        let dataChunk = remainingData.prefix(fileSystem.maxFileChunkSizeBytes())
        return (
            dataChunk,
            dataChunk.count != remainingData.count,
        )
    }
}
