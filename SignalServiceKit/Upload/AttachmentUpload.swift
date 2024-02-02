//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Upload.Constants {
    fileprivate static let uploadMaxRetries = 8
    fileprivate static let maxUploadProgressRetries = 2
}

public struct AttachmentUpload {

    private let db: DB
    private let signalService: OWSSignalServiceProtocol
    private let networkManager: NetworkManager
    private let socketManager: SocketManager

    private let attachmentEncrypter: Upload.Shims.AttachmentEncrypter
    private let fileSystem: Upload.Shims.FileSystem

    private let sourceURL: URL
    private let version: Upload.FormVersion

    private let logger: PrefixedLogger

    public init(
        db: DB,
        signalService: OWSSignalServiceProtocol,
        networkManager: NetworkManager,
        socketManager: SocketManager,
        attachmentEncrypter: Upload.Shims.AttachmentEncrypter,
        fileSystem: Upload.Shims.FileSystem,
        sourceURL: URL,
        version: Upload.FormVersion,
        logger: PrefixedLogger
    ) {
        self.db = db
        self.signalService = signalService
        self.networkManager = networkManager
        self.socketManager = socketManager

        self.attachmentEncrypter = attachmentEncrypter
        self.fileSystem = fileSystem

        self.sourceURL = sourceURL
        self.version = version

        self.logger = logger
    }

    // MARK: - Upload Entrypoint

    /// The main entry point into the CDN2/CDN3 upload flow.
    /// This method is responsible for encrypting the source data and creating the temporary file that
    /// the rest of the upload will use. From this point forward,  the upload doesn't have any
    /// knowledge of the source (attachment, backup, image, etc)
    public func start(progress: Upload.ProgressBlock?) async throws -> Upload.Result {
        try Task.checkCancellation()

        // Encrypt local data to a temporary location. This is stable across retries
        let localMetadata = try buildLocalAttachmentMetadata(for: sourceURL)

        progress?(buildProgress(done: 0, total: localMetadata.encryptedDataLength))

        defer {
            do {
                try fileSystem.deleteFile(url: localMetadata.fileUrl)
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }

        return try await attemptUpload(localMetadata: localMetadata, progress: progress)
    }

    /// The retriable parts of the upload.
    /// 1. Fetch upload form
    /// 2. Create upload endpoint
    /// 3. Get the target URL from the endpoint
    /// 4. Initate the upload via the endpoint
    ///
    /// - Parameters:
    ///   - localMetadata: The metadata and URL path for the local upload data
    ///   will create a new request and fetch a new form.
    ///   - count: For certain failure types, the attempt will be retried.  This keeps track and will error
    ///   out after a certain number of retries.
    ///   - progressBlock: Callback notified up upload progress.
    /// - returns: `Upload.Result` reflecting the metadata of the final upload result.
    ///
    /// Resumption of an active upload can be handled at a lower level, but if the endpoint returns an
    /// error that requires a full restart, this is the method that will be called to fetch a new upload form and
    /// rebuild the endpoint and upload state before trying again
    private func attemptUpload(localMetadata: Upload.LocalUploadMetadata, count: UInt = 0, progress: Upload.ProgressBlock?) async throws -> Upload.Result {
        do {
            let attempt = try await buildAttempt(for: localMetadata, version: version, count: count, logger: logger)
            return try await performResumableUpload(attempt: attempt, progress: progress)
        } catch {
            // Anything besides 'restart' should be handled below this method,
            // or is an unhandled error that should be thrown to the caller
            if
                case Upload.Error.uploadFailure(let recoveryMode) = error,
                case .restart(let backOff) = recoveryMode
            {
                switch backOff {
                case .immediately:
                    break
                case .afterDelay(let delay):
                    try await sleep(for: delay)
                }

                return try await attemptUpload(localMetadata: localMetadata, count: count + 1, progress: progress)
            } else {
                throw error
            }
        }
    }

    /// Consult the UploadEndpoint to determine how much has already been uploaded.
    private func getResumableUploadProgress(
        attempt: Upload.Attempt,
        count: UInt = 0
    ) async throws -> Upload.ResumeProgress {
        do {
            return try await attempt.endpoint.getResumableUploadProgress(attempt: attempt)
        } catch {
            guard
                count < Upload.Constants.maxUploadProgressRetries,
                error.isNetworkFailureOrTimeout
            else {
                throw error
            }
            if
                case Upload.Error.uploadFailure(let recoveryMode) = error,
                case .restart = recoveryMode
            {
                throw error
            }
            return try await getResumableUploadProgress(attempt: attempt, count: count + 1)
        }
    }

    /// Upload the file using the endpoint and report progress
    private func performResumableUpload(
        attempt: Upload.Attempt,
        count: UInt = 0,
        progress: Upload.ProgressBlock?
    ) async throws -> Upload.Result {
        guard count < Upload.Constants.uploadMaxRetries else {
            throw Upload.Error.uploadFailure(recovery: .noMoreRetries)
        }

        let totalDataLength = attempt.localMetadata.encryptedDataLength
        var bytesAlreadyUploaded = 0

        let uploadProgress = try await getResumableUploadProgress(attempt: attempt)
        switch uploadProgress {
        case .complete(let result):
            return result
        case .uploaded(let updatedBytesAlreadUploaded):
            bytesAlreadyUploaded = updatedBytesAlreadUploaded
        case .restart:
            let backoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: count + 1)
            throw Upload.Error.uploadFailure(recovery: .restart(.afterDelay(backoff)))
        }

        // Wrap the progress block.
        let wrappedProgressBlock = { (_: URLSessionTask, wrappedProgress: Progress) in
            // Total progress is (progress from previous attempts/slices +
            // progress from this attempt/slice).
            let totalCompleted: Int = bytesAlreadyUploaded + Int(wrappedProgress.completedUnitCount)
            owsAssertDebug(totalCompleted >= 0)
            owsAssertDebug(totalCompleted <= totalDataLength)

            // When resuming, we'll only upload a slice of the data.
            // We need to massage the progress to reflect the bytes already uploaded.
            progress?(self.buildProgress(done: totalCompleted, total: totalDataLength))
        }

        do {
            return try await attempt.endpoint.performUpload(
                startPoint: bytesAlreadyUploaded,
                attempt: attempt,
                progress: wrappedProgressBlock
            )
        } catch {
            if let statusCode = error.httpStatusCode {
                attempt.logger.warn("Encountered error during upload. (code=\(statusCode)")
            } else {
                attempt.logger.warn("Encountered error during upload. ")
            }

            var failureMode: Upload.FailureMode = .noMoreRetries
            if case Upload.Error.uploadFailure(let retryMode) = error {
                // if a failure mode was passed back
                failureMode = retryMode
            } else {
                // if this isn't an understood error, map into a failure mode
                let backoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: count + 1)
                failureMode = .resume(.afterDelay(backoff))
            }

            switch failureMode {
            case .noMoreRetries:
                attempt.logger.warn("No more retries.")
                throw error
            case .resume(let recoveryMode):
                switch recoveryMode {
                case .immediately:
                    attempt.logger.warn("Retry upload immediately")
                case .afterDelay(let delay):
                    attempt.logger.warn("Retry upload after \(delay) seconds")
                    try await sleep(for: delay)
                }
            case .restart:
                // Restart is handled at a higher level since the whole
                // upload form needs to be rebuilt.
                throw error
            }

            return try await performResumableUpload(attempt: attempt, count: count + 1, progress: progress)
        }
    }

    // MARK: - Helper Methods

    private func buildAttempt(
        for localMetadata: Upload.LocalUploadMetadata,
        version: Upload.FormVersion,
        count: UInt = 0,
        logger: PrefixedLogger
    ) async throws -> Upload.Attempt {
        let request = {
            switch version {
            case .v3:
                return OWSRequestFactory.allocAttachmentRequestV3()
            }
        }()
        let form: Upload.Form = try await fetchUploadForm(request: request)
        let endpoint = try {
            switch form.cdnNumber {
            case 2:
                return UploadEndpointCDN2(
                    form: form,
                    signalService: signalService,
                    fileSystem: fileSystem,
                    logger: logger
                )
            default:
                throw OWSAssertionError("Unsupported Endpoint: \(form.cdnNumber)")
            }
        }()
        let uploadLocation = try await endpoint.fetchResumableUploadLocation()
        return Upload.Attempt(
            localMetadata: localMetadata,
            beginTimestamp: Date.ows_millisecondTimestamp(),
            endpoint: endpoint,
            uploadLocation: uploadLocation,
            logger: logger
        )
    }

    private func buildLocalAttachmentMetadata(for sourceURL: URL) throws -> Upload.LocalUploadMetadata {
        let temporaryFile = fileSystem.temporaryFileUrl()
        let metadata = try attachmentEncrypter.encryptAttachment(at: sourceURL, output: temporaryFile)

        guard let length = metadata.length, let plaintextLength = metadata.plaintextLength else {
            throw OWSAssertionError("Missing length.")
        }

        guard
            plaintextLength <= OWSMediaUtils.kMaxFileSizeGeneric,
            length <= OWSMediaUtils.kMaxAttachmentUploadSizeBytes
        else {
            throw OWSAssertionError("Data is too large: \(length).")
        }

        guard let digest = metadata.digest else {
            throw OWSAssertionError("Digest missing for attachment")
        }

        return Upload.LocalUploadMetadata(
            fileUrl: temporaryFile,
            key: metadata.key,
            digest: digest,
            encryptedDataLength: length
        )
    }

    private func fetchUploadForm<T: Decodable>(request: TSRequest ) async throws -> T {
        guard let data = try await performRequest(request).responseBodyData else {
            throw OWSAssertionError("Invalid JSON")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func performRequest(_ request: TSRequest) async throws -> HTTPResponse {
        try await networkManager.makePromise(
            request: request,
            canUseWebSocket: socketManager.canMakeRequests(webSocketType: .identified)
        ).awaitable()
    }

    private func sleep(for delay: TimeInterval) async throws {
        let delayInNs = UInt64(delay * Double(NSEC_PER_SEC))
        try await Task.sleep(nanoseconds: delayInNs)
    }

    private func buildProgress(done: Int, total: Int) -> Progress {
        let progress = Progress(parent: nil, userInfo: nil)
        progress.totalUnitCount = Int64(total)
        progress.completedUnitCount = Int64(done)
        return progress
    }
}
