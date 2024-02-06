//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum Upload {
    public typealias ProgressBlock = (Progress) -> Void

    public static let uploadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "OWSUpload"
        queue.maxConcurrentOperationCount = CurrentAppContext().isNSE ? 2 : 8
        return queue
    }()

    public enum Constants {
        public static let uploadProgressNotification = NSNotification.Name("UploadProgressNotification")
        public static let uploadProgressKey = "UploadProgressKey"
        public static let uploadAttachmentIDKey = "UploadAttachmentIDKey"
    }

    internal struct Form: Codable {
        private enum CodingKeys: String, CodingKey {
            case headers = "headers"
            case signedUploadLocation = "signedUploadLocation"
            case cdnKey = "key"
            case cdnNumber = "cdn"
        }

        let headers: [String: String]
        let signedUploadLocation: String
        let cdnKey: String
        let cdnNumber: UInt32
    }

    // MARK: -

    public enum FailureMode {
        public enum RetryMode {
            case immediately
            case afterDelay(TimeInterval)
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
        case complete(Upload.Result)

        // Contains the number of bytes the upload endpoint has received.  This
        // can be 0 bytes, which is effectively a new upload, but can use the
        // existing upload form.
        case uploaded(Int)
    }

    public enum Error: Swift.Error, IsRetryableProvider, LocalizedError {
        case invalidUploadURL
        case uploadFailure(recovery: FailureMode)
        case unsupportedEndpoint
        case unknown

        public var isRetryableProvider: Bool {
            switch self {
            case .invalidUploadURL, .uploadFailure, .unsupportedEndpoint, .unknown:
                return false
            }
        }

        public var errorDescription: String? {
            localizedDescription
        }

        public var localizedDescription: String {
            return OWSLocalizedString(
                "ERROR_MESSAGE_ATTACHMENT_UPLOAD_FAILED",
                comment: "Error message indicating that attachment upload(s) failed."
            )
        }
    }

    public struct LocalUploadMetadata {
        /// File URL of the data consisting of "iv  + encrypted data + hmac"
        let fileUrl: URL

        /// encryption key + hmac
        let key: Data

        /// The digest of the encrypted file.  The encrypted file consist of "iv + encrypted data + hmac"
        let digest: Data

        /// The length of the encrypted data, consiting of "iv  + encrypted data + hmac"
        let encryptedDataLength: Int
    }

    public enum FormVersion {
        case v3
        case v4
    }

    public struct Result {
        let cdnKey: String
        let cdnNumber: UInt32
        let localUploadMetadata: LocalUploadMetadata

        // Timestamp the upload attempt began
        let beginTimestamp: UInt64

        // Timestamp the upload attempt completed
        let finishTimestamp: UInt64
    }

    public struct Attempt {
        let localMetadata: Upload.LocalUploadMetadata
        let beginTimestamp: UInt64
        let endpoint: UploadEndpoint
        let uploadLocation: URL
        let logger: PrefixedLogger
    }
}
