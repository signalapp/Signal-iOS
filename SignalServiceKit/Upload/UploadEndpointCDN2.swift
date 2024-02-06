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

        let urlSession = signalService.urlSessionForCdn(cdnNumber: uploadForm.cdnNumber)
        let urlString = uploadForm.signedUploadLocation
        guard urlString.lowercased().hasPrefix("http") else {
            throw OWSAssertionError("Invalid signedUploadLocation.")
        }

        var headers = uploadForm.headers
        // Remove host header.
        headers = headers.filter { $0.key.lowercased() != "host" }
        headers["Content-Length"] = "0"
        headers["Content-Type"] = OWSMimeTypeApplicationOctetStream

        do {
            let response = try await urlSession.dataTaskPromise(
                urlString,
                method: .post,
                headers: headers,
                body: nil
            ).awaitable()

            guard response.responseStatusCode == 201 else {
                throw OWSAssertionError("Invalid statusCode: \(response.responseStatusCode).")
            }
            guard
                let locationHeader = response.responseHeaders["Location"],
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
    internal func getResumableUploadProgress(attempt: Upload.Attempt) async throws -> Upload.ResumeProgress {
        var headers = [String: String]()
        headers["Content-Length"] = "0"
        headers["Content-Range"] = "bytes */\(OWSFormat.formatInt(attempt.localMetadata.encryptedDataLength))"

        let urlSession = signalService.urlSessionForCdn(cdnNumber: uploadForm.cdnNumber)
        let response = try await urlSession.dataTaskPromise(
            attempt.uploadLocation.absoluteString,
            method: .put,
            headers: headers,
            body: nil
        ).awaitable()

        let statusCode = response.responseStatusCode
        switch statusCode {
        case 200, 201:
            // completed, so return 'OK' TODO:
            return .complete(Upload.Result(
                cdnKey: uploadForm.cdnKey,
                cdnNumber: uploadForm.cdnNumber,
                localUploadMetadata: attempt.localMetadata,
                beginTimestamp: attempt.beginTimestamp,
                finishTimestamp: Date().ows_millisecondsSince1970
            ))
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
            let rangeHeader = response.responseHeaders["Range"],
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

    func performUpload(
        startPoint: Int,
        attempt: Upload.Attempt,
        progress progressBlock: @escaping UploadEndpointProgress
    ) async throws -> Upload.Result {
        let formatInt = OWSFormat.formatInt
        let totalDataLength = attempt.localMetadata.encryptedDataLength
        var headers = [String: String]()
        let fileUrl: URL

        if startPoint == 0 {
            headers["Content-Length"] = formatInt(totalDataLength)
            fileUrl = attempt.localMetadata.fileUrl
        } else {
            // Resuming, slice attachment data in memory.
            let (dataSliceFileUrl, dataSliceLength) = try fileSystem.createTempFileSlice(
                url: attempt.localMetadata.fileUrl,
                start: startPoint
            )
            fileUrl = dataSliceFileUrl
            defer {
                do {
                    try fileSystem.deleteFile(url: dataSliceFileUrl)
                } catch {
                    owsFailDebug("Error: \(error)")
                }
            }

            // Example: Resuming after uploading 2359296 of 7351375 bytes.
            // Content-Range: bytes 2359296-7351374/7351375
            // Content-Length: 4992079
            headers["Content-Length"] = formatInt(dataSliceLength)
            headers["Content-Range"] = "bytes \(formatInt(startPoint))-\(formatInt(totalDataLength - 1))/\(formatInt(totalDataLength))"
        }

        let urlSession = signalService.urlSessionForCdn(cdnNumber: uploadForm.cdnNumber)
        _ = try await urlSession.uploadTaskPromise(
            attempt.uploadLocation.absoluteString,
            method: .put,
            headers: headers,
            fileUrl: fileUrl,
            progress: progressBlock
        ).awaitable()

        return Upload.Result(
            cdnKey: uploadForm.cdnKey,
            cdnNumber: uploadForm.cdnNumber,
            localUploadMetadata: attempt.localMetadata,
            beginTimestamp: attempt.beginTimestamp,
            finishTimestamp: Date().ows_millisecondsSince1970
        )
    }
}
