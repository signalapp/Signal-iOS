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
    // MARK: - Upload Entrypoint

    /// The main entry point into the CDN2/CDN3 upload flow.
    /// This method is responsible for prepping the source data and its metadata.
    /// From this point forward,  the upload doesn't have any knowledge of the source (attachment, backup, image, etc)
    public static func start<Metadata: UploadMetadata>(
        attempt: Upload.Attempt<Metadata>,
        dateProvider: @escaping DateProvider,
        progress: OWSProgressSink?
    ) async throws -> Upload.Result<Metadata> {
        try Task.checkCancellation()

        let progressSource = await progress?.addSource(
            withLabel: "upload",
            unitCount: UInt64(attempt.encryptedDataLength)
        )

        return try await attemptUpload(
            attempt: attempt,
            dateProvider: dateProvider,
            progress: progressSource
        )
    }

    /// The retriable parts of the upload.
    /// 1. Create upload endpoint
    /// 2. Get the target URL from the endpoint
    /// 3. Initate the upload via the endpoint
    ///
    /// - Parameters:
    ///   - localMetadata: The metadata and URL path for the local upload data
    ///   will create a new request and fetch a new form.
    ///   - progressBlock: Callback notified up upload progress.
    /// - returns: `Upload.Result` reflecting the metadata of the final upload result.
    ///
    private static func attemptUpload<Metadata: UploadMetadata>(
        attempt: Upload.Attempt<Metadata>,
        dateProvider: @escaping DateProvider,
        progress: OWSProgressSource?
    ) async throws -> Upload.Result<Metadata> {
        attempt.logger.info("Begin upload. (CDN\(attempt.cdnNumber))")
        try await performResumableUpload(
            attempt: attempt,
            progress: progress
        )
        return Upload.Result(
            cdnKey: attempt.cdnKey,
            cdnNumber: attempt.cdnNumber,
            localUploadMetadata: attempt.localMetadata,
            beginTimestamp: attempt.beginTimestamp,
            finishTimestamp: dateProvider().ows_millisecondsSince1970
        )
    }

    /// Consult the UploadEndpoint to determine how much has already been uploaded.
    private static func getResumableUploadProgress<Metadata: UploadMetadata>(
        attempt: Upload.Attempt<Metadata>,
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
            attempt.logger.info("Retry fetching upload progress.")
            return try await getResumableUploadProgress(attempt: attempt, count: count + 1)
        }
    }

    /// Upload the file using the endpoint and report progress
    private static func performResumableUpload<Metadata: UploadMetadata>(
        attempt: Upload.Attempt<Metadata>,
        count: UInt = 0,
        progress: OWSProgressSource?
    ) async throws {
        guard count < Upload.Constants.uploadMaxRetries else {
            throw Upload.Error.uploadFailure(recovery: .noMoreRetries)
        }

        let totalDataLength = attempt.encryptedDataLength
        let bytesAlreadyUploaded: Int

        // Only check remote upload progress if we think progress was made locally
        if attempt.isResumedUpload || count > 0 {
            let uploadProgress = try await getResumableUploadProgress(attempt: attempt)
            switch uploadProgress {
            case .complete:
                attempt.logger.info("Complete upload reported by endpoint.")

                progress?.incrementCompletedUnitCount(by: UInt64(totalDataLength))

                return
            case .uploaded(let updatedBytesAlreadUploaded):
                attempt.logger.info("Endpoint reported \(updatedBytesAlreadUploaded)/\(attempt.encryptedDataLength) uploaded.")
                bytesAlreadyUploaded = updatedBytesAlreadUploaded
            case .restart:
                attempt.logger.warn("Error with fetching progress. Restart upload.")
                let backoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: count + 1)
                throw Upload.Error.uploadFailure(recovery: .restart(.afterDelay(backoff)))
            }
        } else {
            bytesAlreadyUploaded = 0
        }

        let internalProgress: OWSProgressSource
        if let progress {
            internalProgress = progress
        } else {
            let internalProgressSink = OWSProgress.createSink { _ in }
            internalProgress = await internalProgressSink.addSource(withLabel: "upload", unitCount: UInt64(totalDataLength))
        }

        // Total progress is (progress from previous attempts/slices +
        // progress from this attempt/slice).
        if internalProgress.completedUnitCount < bytesAlreadyUploaded {
            internalProgress.incrementCompletedUnitCount(by: UInt64(bytesAlreadyUploaded) - internalProgress.completedUnitCount)
        }

        do {
            try await attempt.endpoint.performUpload(
                startPoint: bytesAlreadyUploaded,
                attempt: attempt,
                progress: progress
            )
            attempt.logger.info("Attachment uploaded successfully. (\(internalProgress.completedUnitCount) bytes)")
        } catch {
            if let statusCode = error.httpStatusCode {
                attempt.logger.warn("Encountered error during upload. (code=\(statusCode)")
            } else {
                attempt.logger.warn("Encountered error during upload. ")
            }

            let didUploadMakeProgress = internalProgress.completedUnitCount > bytesAlreadyUploaded
            if didUploadMakeProgress {
                attempt.logger.warn("Upload made progress: \(bytesAlreadyUploaded) -> \(internalProgress.completedUnitCount)")
            }
            var failureMode: Upload.FailureMode = .noMoreRetries
            if case Upload.Error.uploadFailure(let retryMode) = error {
                // if a failure mode was passed back
                failureMode = retryMode
            } else {
                // if this isn't an understood error, map into a failure mode
                let backoff = OWSOperation.retryIntervalForExponentialBackoff(failureCount: count)
                failureMode = .resume(.afterDelay(backoff))
            }

            switch failureMode {
            case .noMoreRetries:
                attempt.logger.warn("No more retries.")
                throw error
            case .resume(let recoveryMode):
                switch recoveryMode {
                case .immediately:
                    attempt.logger.warn("Retry upload immediately.")
                case .afterDelay(let delay):
                    attempt.logger.warn("Retry upload after \(delay) seconds.")
                    try await Upload.sleep(for: delay)
                }
            case .restart:
                // Restart is handled at a higher level since the whole
                // upload form needs to be rebuilt.
                throw error
            }

            attempt.logger.info("Resuming upload.")
            // Reset the attempt count to 1 as long as progress was made. Make it 1, since 0
            // will behave like a fresh upload and skip fetching the remote upload progress.
            let nextAttemptCount = didUploadMakeProgress ? 1 : count + 1
            try await performResumableUpload(attempt: attempt, count: nextAttemptCount, progress: progress)
        }
    }

    // MARK: - Helper Methods

    public static func buildAttempt(
        for localMetadata: Upload.LocalUploadMetadata,
        form: Upload.Form,
        existingSessionUrl: URL? = nil,
        signalService: OWSSignalServiceProtocol,
        fileSystem: Upload.Shims.FileSystem,
        dateProvider: @escaping DateProvider,
        logger: PrefixedLogger
    ) async throws -> Upload.Attempt<Upload.LocalUploadMetadata> {
        return try await buildAttempt(
            for: localMetadata,
            fileUrl: localMetadata.fileUrl,
            encryptedDataLength: localMetadata.encryptedDataLength,
            form: form,
            existingSessionUrl: existingSessionUrl,
            signalService: signalService,
            fileSystem: fileSystem,
            dateProvider: dateProvider,
            logger: logger
        )
    }

    public static func buildAttempt(
        for metadata: Upload.LinkNSyncUploadMetadata,
        form: Upload.Form,
        existingSessionUrl: URL? = nil,
        signalService: OWSSignalServiceProtocol,
        fileSystem: Upload.Shims.FileSystem,
        dateProvider: @escaping DateProvider,
        logger: PrefixedLogger
    ) async throws -> Upload.Attempt<Upload.LinkNSyncUploadMetadata> {
        return try await buildAttempt(
            for: metadata,
            fileUrl: metadata.fileUrl,
            encryptedDataLength: metadata.encryptedDataLength,
            form: form,
            existingSessionUrl: existingSessionUrl,
            signalService: signalService,
            fileSystem: fileSystem,
            dateProvider: dateProvider,
            logger: logger
        )
    }

    public static func buildAttempt(
        for localMetadata: Upload.EncryptedBackupUploadMetadata,
        form: Upload.Form,
        existingSessionUrl: URL? = nil,
        signalService: OWSSignalServiceProtocol,
        fileSystem: Upload.Shims.FileSystem,
        dateProvider: @escaping DateProvider,
        logger: PrefixedLogger
    ) async throws -> Upload.Attempt<Upload.EncryptedBackupUploadMetadata> {
        return try await buildAttempt(
            for: localMetadata,
            fileUrl: localMetadata.fileUrl,
            encryptedDataLength: localMetadata.encryptedDataLength,
            form: form,
            existingSessionUrl: existingSessionUrl,
            signalService: signalService,
            fileSystem: fileSystem,
            dateProvider: dateProvider,
            logger: logger
        )
    }

    public static func buildAttempt<Metadata: UploadMetadata>(
        for localMetadata: Metadata,
        fileUrl: URL,
        encryptedDataLength: UInt32,
        form: Upload.Form,
        existingSessionUrl: URL? = nil,
        signalService: OWSSignalServiceProtocol,
        fileSystem: Upload.Shims.FileSystem,
        dateProvider: @escaping DateProvider,
        logger: PrefixedLogger
    ) async throws -> Upload.Attempt<Metadata> {
        let endpoint: UploadEndpoint = try {
            switch form.cdnNumber {
            case 2:
                return UploadEndpointCDN2(
                    form: form,
                    signalService: signalService,
                    fileSystem: fileSystem,
                    logger: logger
                )
            case 3:
                return UploadEndpointCDN3(
                    form: form,
                    signalService: signalService,
                    fileSystem: fileSystem,
                    logger: logger
                )
            default:
                throw OWSAssertionError("Unsupported Endpoint: \(form.cdnNumber)")
            }
        }()
        let uploadLocation = try await {
            if let existingSessionUrl {
                return existingSessionUrl
            }
            return try await endpoint.fetchResumableUploadLocation()
        }()
        return Upload.Attempt(
            cdnKey: form.cdnKey,
            cdnNumber: form.cdnNumber,
            fileUrl: fileUrl,
            encryptedDataLength: encryptedDataLength,
            localMetadata: localMetadata,
            beginTimestamp: dateProvider().ows_millisecondsSince1970,
            endpoint: endpoint,
            uploadLocation: uploadLocation,
            isResumedUpload: existingSessionUrl != nil,
            logger: logger
        )
    }
}

extension Upload {
    static func sleep(for delay: TimeInterval) async throws {
        let delayInNs = UInt64(delay * Double(NSEC_PER_SEC))
        try await Task.sleep(nanoseconds: delayInNs)
    }
}

extension Upload {
    struct FormRequest {
        private let networkManager: NetworkManager
        private let chatConnectionManager: ChatConnectionManager

        public init(
            networkManager: NetworkManager,
            chatConnectionManager: ChatConnectionManager
        ) {
            self.networkManager = networkManager
            self.chatConnectionManager = chatConnectionManager
        }

        public func start() async throws -> Upload.Form {
            let request = OWSRequestFactory.allocAttachmentRequestV4()
            return try await fetchUploadForm(request: request)
        }

        private func fetchUploadForm<T: Decodable>(request: TSRequest ) async throws -> T {
            guard let data = try await performRequest(request).responseBodyData else {
                throw OWSAssertionError("Invalid JSON")
            }
            return try JSONDecoder().decode(T.self, from: data)
        }

        private func performRequest(_ request: TSRequest) async throws -> HTTPResponse {
            try await networkManager.asyncRequest(request, canUseWebSocket: chatConnectionManager.canMakeRequests(connectionType: .identified))
        }
    }
}
