//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SSZipArchive
import zlib
import SignalCoreKit
import SignalMessaging

private enum DebugLogUploader {
    static func uploadFile(fileUrl: URL, mimeType: String) -> Promise<URL> {
        firstly(on: .global()) {
            getUploadParameters(fileUrl: fileUrl)
        }.then(on: .global()) { (uploadParameters: UploadParameters) -> Promise<URL> in
            uploadFile(fileUrl: fileUrl, mimeType: mimeType, uploadParameters: uploadParameters)
        }
    }

    private static func buildOWSURLSession() -> OWSURLSessionProtocol {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.urlCache = nil
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        let urlSession = OWSURLSession(
            baseUrl: nil,
            securityPolicy: OWSURLSession.defaultSecurityPolicy,
            configuration: sessionConfig
        )
        return urlSession
    }

    private static func getUploadParameters(fileUrl: URL) -> Promise<UploadParameters> {
        let url = URL(string: "https://debuglogs.org/")!
        return firstly(on: .global()) { () -> Promise<(HTTPResponse)> in
            buildOWSURLSession().dataTaskPromise(url.absoluteString, method: .get, ignoreAppExpiry: true)
        }.map(on: .global()) { (response: HTTPResponse) -> (UploadParameters) in
            guard let responseObject = response.responseBodyJson else {
                throw OWSAssertionError("Invalid response.")
            }
            guard let params = ParamParser(responseObject: responseObject) else {
                throw OWSAssertionError("Invalid response: \(String(describing: responseObject))")
            }
            let uploadUrl: String = try params.required(key: "url")
            let fieldMap: [String: String] = try params.required(key: "fields")
            guard !fieldMap.isEmpty else {
                throw OWSAssertionError("Invalid response: \(String(describing: responseObject))")
            }
            for (key, value) in fieldMap {
                guard nil != key.nilIfEmpty,
                      nil != value.nilIfEmpty else {
                          throw OWSAssertionError("Invalid response: \(String(describing: responseObject))")
                      }
            }
            guard let rawUploadKey = fieldMap["key"]?.nilIfEmpty else {
                throw OWSAssertionError("Invalid response: \(String(describing: responseObject))")
            }
            guard let fileExtension = (fileUrl.lastPathComponent as NSString).pathExtension.nilIfEmpty else {
                throw OWSAssertionError("Invalid fileUrl: \(fileUrl)")
            }
            guard let uploadKey: String = (rawUploadKey as NSString).appendingPathExtension(fileExtension) else {
                throw OWSAssertionError("Could not modify uploadKey.")
            }
            var orderedFieldMap = OrderedDictionary<String, String>()
            for (key, value) in fieldMap {
                orderedFieldMap.append(key: key, value: value)
            }
            orderedFieldMap.replace(key: "key", value: uploadKey)
            return UploadParameters(uploadUrl: uploadUrl, fieldMap: orderedFieldMap, uploadKey: uploadKey)
        }
    }

    private struct UploadParameters {
        let uploadUrl: String
        let fieldMap: OrderedDictionary<String, String>
        let uploadKey: String
    }

    private static func uploadFile(
        fileUrl: URL,
        mimeType: String,
        uploadParameters: UploadParameters
    ) -> Promise<URL> {
        firstly(on: .global()) { () -> Promise<(HTTPResponse)> in
            let urlSession = buildOWSURLSession()

            guard let url = URL(string: uploadParameters.uploadUrl) else {
                throw OWSAssertionError("Invalid url: \(uploadParameters.uploadUrl)")
            }
            let request = URLRequest(url: url)

            var textParts = uploadParameters.fieldMap
            textParts.append(key: "Content-Type", value: mimeType)

            return urlSession.multiPartUploadTaskPromise(request: request,
                                                         fileUrl: fileUrl,
                                                         name: "file",
                                                         fileName: fileUrl.lastPathComponent,
                                                         mimeType: mimeType,
                                                         textParts: textParts,
                                                         ignoreAppExpiry: true,
                                                         progress: nil)
        }.map(on: .global()) { (response: HTTPResponse) -> URL in
            let statusCode = response.responseStatusCode
            // We'll accept any 2xx status code.
            let statusCodeClass = statusCode - (statusCode % 100)
            guard statusCodeClass == 200 else {
                Logger.error("statusCode: \(statusCode), \(statusCodeClass)")
                Logger.error("headers: \(response.responseHeaders)")
                throw OWSAssertionError("Invalid status code: \(statusCode), \(statusCodeClass)")
            }

            let urlString = "https://debuglogs.org/\(uploadParameters.uploadKey)"
            guard let url = URL(string: urlString) else {
                throw OWSAssertionError("Invalid url: \(urlString)")
            }
            return url
        }
    }
}

extension Pastelog {
    private struct NoLogsError: Error {
        var errorString: String {
            NSLocalizedString(
                "DEBUG_LOG_ALERT_NO_LOGS",
                comment: "Error indicating that no debug logs could be found."
            )
        }
    }

    private static func collectLogs() -> Result<String, NoLogsError> {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy.MM.dd hh.mm.ss"
        let dateString = dateFormatter.string(from: Date())
        let logsName = "\(dateString) \(UUID().uuidString)"

        let zipDirUrl = URL(fileURLWithPath: OWSTemporaryDirectory()).appendingPathComponent(logsName)
        let zipDirPath = zipDirUrl.path
        OWSFileSystem.ensureDirectoryExists(zipDirPath)

        let logFilePaths = DebugLogger.shared().allLogFilePaths()
        if logFilePaths.isEmpty {
            return .failure(NoLogsError())
        }

        for logFilePath in logFilePaths {
            let lastLogFilePathComponent = URL(fileURLWithPath: logFilePath).lastPathComponent
            let copyFilePath = zipDirUrl.appendingPathComponent(lastLogFilePathComponent).path
            do {
                try FileManager.default.copyItem(atPath: logFilePath, toPath: copyFilePath)
            } catch {
                Logger.error("could not copy log file at \(logFilePath): \(error)")
                // Write the error to the file that would have been copied.
                try? error.localizedDescription.write(toFile: copyFilePath, atomically: true, encoding: .utf8)
            }
            OWSFileSystem.protectFileOrFolder(atPath: copyFilePath)
        }

        return .success(zipDirPath)
    }

    public static func exportLogs() {
        AssertIsOnMainThread()
        switch collectLogs() {
        case let .success(logsDirPath):
            AttachmentSharing.showShareUI(for: URL(fileURLWithPath: logsDirPath), sender: nil) {
                OWSFileSystem.deleteFile(logsDirPath)
            }
        case let .failure(error):
            Self.showFailureAlert(with: error.errorString, logArchiveOrDirectoryPath: nil)
            return
        }
    }

    @objc(uploadLogsWithSuccess:failure:)
    static func uploadLogs(
        success: @escaping UploadDebugLogsSuccess,
        failure: @escaping UploadDebugLogsFailure
    ) {
        // Ensure that we call the completions on the main thread.
        let wrappedSuccess: UploadDebugLogsSuccess = { url in
            DispatchMainThreadSafe { success(url) }
        }
        let wrappedFailure: UploadDebugLogsFailure = { localizedErrorMessage, logArchiveOrDirectoryPath in
            DispatchMainThreadSafe { failure(localizedErrorMessage, logArchiveOrDirectoryPath) }
        }

        // Phase 1. Make a local copy of all of the log files.
        let zipDirPath: String
        switch collectLogs() {
        case let .success(logsDirPath):
            zipDirPath = logsDirPath
        case let .failure(error):
            wrappedFailure(error.errorString, nil)
            return
        }

        // Phase 2. Zip up the log files.
        let zipFilePath = zipDirPath.appendingFileExtension("zip")
        let zipSuccess = SSZipArchive.createZipFile(
            atPath: zipFilePath,
            withContentsOfDirectory: zipDirPath,
            keepParentDirectory: true,
            compressionLevel: Z_DEFAULT_COMPRESSION,
            password: nil,
            aes: false,
            progressHandler: nil
        )
        guard zipSuccess else {
            let errorMessage = NSLocalizedString(
                "DEBUG_LOG_ALERT_COULD_NOT_PACKAGE_LOGS",
                comment: "Error indicating that the debug logs could not be packaged."
            )
            wrappedFailure(errorMessage, zipDirPath)
            return
        }

        OWSFileSystem.protectFileOrFolder(atPath: zipFilePath)
        OWSFileSystem.deleteFile(zipDirPath)

        // Phase 3. Upload the log files.
        DebugLogUploader.uploadFile(
            fileUrl: URL(fileURLWithPath: zipFilePath),
            mimeType: OWSMimeTypeApplicationZip
        ).done(on: .global()) { url in
            OWSFileSystem.deleteFile(zipFilePath)
            wrappedSuccess(url)
        }.catch(on: .global()) { error in
            let errorMessage = NSLocalizedString(
                "DEBUG_LOG_ALERT_ERROR_UPLOADING_LOG",
                comment: "Error indicating that a debug log could not be uploaded."
            )
            wrappedFailure(errorMessage, zipFilePath)
        }
    }

    @objc(showFailureAlertWithMessage:logArchiveOrDirectoryPath:)
    static func showFailureAlert(with message: String, logArchiveOrDirectoryPath: String?) {
        func deleteArchive() {
            guard let logArchiveOrDirectoryPath = logArchiveOrDirectoryPath else { return }
            OWSFileSystem.deleteFile(logArchiveOrDirectoryPath)
        }

        let alert = ActionSheetController(title: nil, message: message)

        if let logArchiveOrDirectoryPath = logArchiveOrDirectoryPath {
            alert.addAction(.init(
                title: NSLocalizedString(
                    "DEBUG_LOG_ALERT_OPTION_EXPORT_LOG_ARCHIVE",
                    comment: "Label for the 'Export Logs' fallback option for the alert when debug log uploading fails."
                ),
                accessibilityIdentifier: "export_log_archive"
            ) { _ in
                AttachmentSharing.showShareUI(
                    for: URL(fileURLWithPath: logArchiveOrDirectoryPath),
                    sender: nil,
                    completion: deleteArchive
                )
            })
        }

        alert.addAction(.init(title: CommonStrings.okButton, accessibilityIdentifier: "ok") { _ in
            deleteArchive()
        })

        let presentingViewController = UIApplication.shared.frontmostViewControllerIgnoringAlerts
        presentingViewController?.presentActionSheet(alert)
    }
}
