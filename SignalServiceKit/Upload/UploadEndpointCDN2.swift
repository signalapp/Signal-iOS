//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct UploadEndpointCDN2: UploadEndpoint {

    private enum Constants {
        static let maxUploadLocationRetries = 2
    }

    private let uploadForm: Upload.Form
    private let signalService: OWSSignalServiceProtocol
    private let fileSystem: Upload.Shims.FileSystem
    private let logger: PrefixedLogger
    init(
        form: Upload.Form,
        signalService: OWSSignalServiceProtocol,
        fileSystem: Upload.Shims.FileSystem,
        logger: PrefixedLogger
    ) {
        self.uploadForm = form
        self.signalService = signalService
        self.fileSystem = fileSystem
        self.logger = logger
    }

    // This fetches a temporary URL that can be used for resumable uploads.
    //
    // See: https://cloud.google.com/storage/docs/performing-resumable-uploads#xml-api
    // NOTE: follow the "XML API" instructions.
    internal func fetchResumableUploadLocation() async throws -> URL {
        return try await _fetchResumableUploadLocation(attemptCount: 0)
    }

    private func _fetchResumableUploadLocation(attemptCount: Int = 0) async throws -> URL {
        if attemptCount > 0 {
            logger.info("attemptCount: \(attemptCount)")
        }

        let urlSession = signalService.urlSessionForCdn(cdnNumber: uploadForm.cdnNumber, maxResponseSize: nil)
        let urlString = uploadForm.signedUploadLocation
        guard urlString.lowercased().hasPrefix("http") else {
            throw OWSAssertionError("Invalid signedUploadLocation.")
        }

        var headers = uploadForm.headers
        // Remove host header.
        headers["Host"] = nil
        headers["Content-Length"] = "0"
        headers["Content-Type"] = MimeType.applicationOctetStream.rawValue

        do {
            let response = try await urlSession.performRequest(
                urlString,
                method: .post,
                headers: headers,
                body: nil
            )

            guard response.responseStatusCode == 201 else {
                throw OWSAssertionError("Invalid statusCode: \(response.responseStatusCode).")
            }
            guard
                let locationHeader = response.headers["location"],
                locationHeader.lowercased().hasPrefix("http"),
                let locationUrl = URL(string: locationHeader)
            else {
                throw OWSAssertionError("Invalid location header.")
            }
            return locationUrl
        } catch {
            guard error.isNetworkFailureOrTimeout else {
                throw error
            }
            guard attemptCount <= Constants.maxUploadLocationRetries else {
                logger.warn("No more retries: \(attemptCount). ")
                throw error
            }
            return try await self._fetchResumableUploadLocation(attemptCount: attemptCount + 1)
        }
    }

    // Determine how much has already been uploaded.
    internal func getResumableUploadProgress<Metadata: UploadMetadata>(
        attempt: Upload.Attempt<Metadata>
    ) async throws -> Upload.ResumeProgress {
        var headers = HttpHeaders()
        headers["Content-Length"] = "0"
        headers["Content-Range"] = "bytes */\(attempt.encryptedDataLength)"

        let urlSession = signalService.urlSessionForCdn(cdnNumber: uploadForm.cdnNumber, maxResponseSize: nil)
        let response = try await urlSession.performRequest(
            attempt.uploadLocation.absoluteString,
            method: .put,
            headers: headers,
            body: nil
        )

        let statusCode = response.responseStatusCode
        switch statusCode {
        case 200, 201:
            // completed, so return 'OK' TODO:
            return .complete
        case 308:
            break
        default:
            owsFailDebug("Invalid status code: \(statusCode).")
            // Any other error should result in restarting the upload.
            return .restart
        }

        // If you receive a '308 Resume Incomplete' response, it may or may
        // not have a valid Range header.  If the header is missing, resume
        // the upload from the beginning.
        //
        // See: https://cloud.google.com/storage/docs/performing-resumable-uploads#status-check
        let expectedPrefix = "bytes=0-"
        guard
            let rangeHeader = response.headers["range"],
            rangeHeader.hasPrefix(expectedPrefix)
        else {
            // Return zero to restart the upload.
            return .uploaded(0)
        }

        let rangeEndString = rangeHeader.suffix(rangeHeader.count - expectedPrefix.count)
        guard
            !rangeEndString.isEmpty,
            let rangeEnd = Int(rangeEndString)
        else {
            logger.warn("Invalid Range header: \(rangeHeader) (\(rangeEndString)).")
            // There was a range header present, but it was
            // invalid - restart the upload from scratch
            return .restart
        }

        // rangeEnd is the _index_ of the last uploaded bytes, e.g.:
        // * 0 if 1 byte has been uploaded,
        // * N if N+1 bytes have been uploaded.
        let bytesAlreadyUploaded = rangeEnd + 1
        logger.verbose("rangeEnd: \(rangeEnd), bytesAlreadyUploaded: \(bytesAlreadyUploaded).")
        return .uploaded(bytesAlreadyUploaded)
    }

    func performUpload<Metadata: UploadMetadata>(
        startPoint: Int,
        attempt: Upload.Attempt<Metadata>,
        progress: OWSProgressSource?
    ) async throws(Upload.Error) {
        let totalDataLength = attempt.encryptedDataLength
        var headers = HttpHeaders()
        let fileUrl: URL
        var fileToCleanup: URL?

        if startPoint == 0 {
            headers["Content-Length"] = "\(totalDataLength)"
            fileUrl = attempt.fileUrl
        } else {
            // Resuming, slice attachment data in memory.
            let dataSliceFileUrl: URL
            let dataSliceLength: Int
            do {
                (dataSliceFileUrl, dataSliceLength) = try fileSystem.createTempFileSlice(
                    url: attempt.fileUrl,
                    start: startPoint
                )
            } catch {
                attempt.logger.warn("Failed to create temp file slice.")
                throw Upload.Error.unknown
            }

            fileUrl = dataSliceFileUrl
            fileToCleanup = dataSliceFileUrl

            // Example: Resuming after uploading 2359296 of 7351375 bytes.
            // Content-Range: bytes 2359296-7351374/7351375
            // Content-Length: 4992079
            headers["Content-Length"] = "\(dataSliceLength)"
            headers["Content-Range"] = "bytes \(startPoint)-\(totalDataLength - 1)/\(totalDataLength)"
        }

        defer {
            if let fileToCleanup {
                do {
                    try fileSystem.deleteFile(url: fileToCleanup)
                } catch {
                    owsFailDebug("Error: \(error)")
                }
            }
        }

        do {
            let urlSession = signalService.urlSessionForCdn(cdnNumber: uploadForm.cdnNumber, maxResponseSize: nil)
            let response = try await urlSession.performUpload(
                attempt.uploadLocation.absoluteString,
                method: .put,
                headers: headers,
                fileUrl: fileUrl,
                progress: progress
            )
            switch response.responseStatusCode {
            case 200, 201:
                return
            default:
                throw Upload.Error.unknown
            }
        } catch {
            let retryMode: Upload.FailureMode.RetryMode = {
                if
                    // Allow the server to override the default backoff with a specified value
                    let retryHeader = error.httpResponseHeaders?.value(forHeader: "retry-after"),
                    let delay = TimeInterval(retryHeader)
                {
                    return .afterServerRequestedDelay(delay)
                } else {
                    return .afterBackoff
                }
            }()

            switch error {
            case let error as OWSHTTPError where (500...599).contains(error.responseStatusCode):
                // On 5XX errors, clients should try to resume the upload
                attempt.logger.warn("Temporary upload failure, retry.")
                // Check for any progress here
                throw Upload.Error.uploadFailure(recovery: .resume(retryMode))
            case OWSHTTPError.networkFailure(let wrappedError):
                let debugMessage = DebugFlags.internalLogging ? " Error: \(wrappedError.debugDescription)" : ""
                if wrappedError.isTimeoutImpl {
                    attempt.logger.warn("Network timeout during upload.\(debugMessage)")
                    throw Upload.Error.networkTimeout
                } else {
                    attempt.logger.warn("Network failure during upload.\(debugMessage)")
                    throw Upload.Error.networkError
                }
            default:
                attempt.logger.warn("Unknown upload failure.")
                throw Upload.Error.unknown
            }
        }
    }
}
