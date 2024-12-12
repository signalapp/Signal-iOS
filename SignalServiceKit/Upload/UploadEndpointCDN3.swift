//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// CDN3 implements the TUS resumable upload protocol.
/// https://tus.io/protocols/resumable-upload
struct UploadEndpointCDN3: UploadEndpoint {

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

    func fetchResumableUploadLocation() async throws -> URL {
        guard let url = URL(string: uploadForm.signedUploadLocation) else {
            throw Upload.Error.invalidUploadURL
        }
        return url
    }

    internal func getResumableUploadProgress<Metadata: UploadMetadata>(attempt: Upload.Attempt<Metadata>) async throws -> Upload.ResumeProgress {
        var headers = uploadForm.headers
        headers["Tus-Resumable"] = "1.0.0"

        let urlSession = signalService.urlSessionForCdn(cdnNumber: uploadForm.cdnNumber, maxResponseSize: nil)

        let response: HTTPResponse
        do {
            let url = attempt.uploadLocation.appendingPathComponent(uploadForm.cdnKey)
            response = try await urlSession.performRequest(
                url.absoluteString,
                method: .head,
                headers: headers
            )
        } catch {
            switch error.httpStatusCode ?? 0 {
            case 404, 410, 403:
                return .uploaded(0)
            default:
                throw error
            }
        }

        let statusCode = response.responseStatusCode
        guard statusCode == 200 else {
            owsFailDebug("Invalid status code: \(statusCode).")
            // If a success results in something other than 200,
            // throw a 'Restart' error to try with a different upload form
            return .restart
        }

        guard
            let bytesAlreadyUploadedString = response.responseHeaders["upload-offset"],
            let bytesAlreadyUploaded = Int(bytesAlreadyUploadedString)
        else {
            owsFailDebug("Missing upload offset data")
            return .restart
        }

        return .uploaded(bytesAlreadyUploaded)
    }

    func performUpload<Metadata: UploadMetadata>(
        startPoint: Int,
        attempt: Upload.Attempt<Metadata>,
        progress: OWSProgressSource?
    ) async throws {
        let urlSession = signalService.urlSessionForCdn(cdnNumber: uploadForm.cdnNumber, maxResponseSize: nil)
        let totalDataLength = attempt.encryptedDataLength

        var headers = uploadForm.headers
        headers["Content-Type"] = "application/offset+octet-stream"
        headers["Tus-Resumable"] = "1.0.0"
        headers["Upload-Offset"] = "\(startPoint)"

        let method: HTTPMethod
        let temporaryFileUrl: URL
        var fileToCleanup: URL?
        let uploadURL: String
        if startPoint == 0 {
            // Either first attempt or no progress so far, use entire encrypted data.
            uploadURL = attempt.uploadLocation.absoluteString

            // For initial uploads, send a POST to create the file
            method = .post
            temporaryFileUrl = attempt.fileUrl
            headers["Content-Length"] = "\(totalDataLength)"
            headers["Upload-Length"] = "\(totalDataLength)"

            // On creation, provide a checksum for the server to validate
            if let metadata = attempt.localMetadata as? ValidatedUploadMetadata {
                headers["x-signal-checksum-sha256"] = metadata.digest.base64EncodedString()
            }
        } else {
            // Resuming, slice attachment data in memory.
            // TODO[CDN3]: Avoid slicing file and instead use a input stream
            let (dataSliceFileUrl, dataSliceLength) = try fileSystem.createTempFileSlice(
                url: attempt.fileUrl,
                start: startPoint
            )

            uploadURL = attempt.uploadLocation.absoluteString + "/" + uploadForm.cdnKey

            // Use PATCH to resume the upload
            method = .patch
            temporaryFileUrl = dataSliceFileUrl
            fileToCleanup = dataSliceFileUrl
            headers["Content-Length"] = "\(dataSliceLength)"
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
            let response = try await urlSession.performUpload(
                uploadURL,
                method: method,
                headers: headers,
                fileUrl: temporaryFileUrl,
                progress: progress
            )

            switch response.responseStatusCode {
            case 200...204:
                return
            default:
                throw Upload.Error.unexpectedResponseStatusCode(response.responseStatusCode)
            }
        } catch let error as Upload.Error {
            switch error {
            case .unexpectedResponseStatusCode(let statusCode):
                attempt.logger.warn("Unexpected response status code: \(statusCode)")
                throw Upload.Error.unknown
            case .invalidUploadURL, .unknown, .unsupportedEndpoint, .uploadFailure:
                attempt.logger.warn("Unexpected upload error")
                throw error
            }
        } catch let error as OWSHTTPError {
            let retryMode: Upload.FailureMode.RetryMode = {
                guard
                    let retryHeader = error.httpResponseHeaders?.value(forHeader: "retry-after"),
                    let delay = TimeInterval(retryHeader)
                else { return .immediately }
                return .afterDelay(delay)
            }()

            let debugInfo: String
            if
                DebugFlags.internalLogging,
                error.httpResponseJson.debugDescription.isEmpty.negated
            {
                debugInfo = " [ERROR RESPONSE: \(error.httpResponseJson.debugDescription)]"
            } else {
                debugInfo = ""
            }

            switch error.httpStatusCode {
            case .some(415):
                // 415 is a checksum error, log the error and retry
                attempt.logger.warn("Upload checksum validation failed, retry.\(debugInfo)")
                throw Upload.Error.uploadFailure(recovery: .restart(retryMode))
            case .some(400...499):
                // On 4XX errors, clients should restart the upload
                attempt.logger.warn("Unexpected upload failure, restart.\(debugInfo)")
                throw Upload.Error.uploadFailure(recovery: .restart(retryMode))
            case .some(500...599):
                // On 5XX errors, clients should try to resume the upload
                attempt.logger.warn("Temporary upload failure, retry.\(debugInfo)")
                throw Upload.Error.uploadFailure(recovery: .resume(retryMode))
            case .some(let httpStatusCode):
                attempt.logger.warn("Unknown upload failure. (HTTP status code: \(httpStatusCode)) \(debugInfo)")
                throw Upload.Error.unknown
            default:
                if DebugFlags.internalLogging {
                    attempt.logger.warn("Unknown network failure during upload. \(debugInfo) Error: \(error)")
                } else {
                    attempt.logger.warn("Unknown network failure during upload. \(debugInfo)")
                }
                throw Upload.Error.unknown
            }
        } catch _ as CancellationError {
            attempt.logger.warn("upload cancelled.")
            throw Upload.Error.unknown
        } catch {
            attempt.logger.warn("Unknown upload failure.")
            throw Upload.Error.unknown
        }
    }
}
