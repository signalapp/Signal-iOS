//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import zlib

struct DebugLogDumper {
    fileprivate var accountManager: (any TSAccountManager)?
    fileprivate var appVersion: any AppVersion
    fileprivate var db: (any DB)?

    static func preLaunch() -> Self {
        return Self(appVersion: AppVersionImpl.shared)
    }

    static func fromGlobals() -> Self {
        return Self(
            accountManager: DependenciesBridge.shared.tsAccountManager,
            appVersion: AppVersionImpl.shared,
            db: DependenciesBridge.shared.db,
        )
    }

    func challengeReceivedRecently() -> Bool {
        guard let db else {
            return false
        }

        let challengeFloorDate = Date().addingTimeInterval(.day * -3)
        return db.read { tx in
            SupportKeyValueStore().lastChallengeWithinTimeframe(transaction: tx, lastChallengeFloor: challengeFloorDate)
        }
    }

    fileprivate func dump() {
        appVersion.dumpToLog()
        if let db {
            db.read { tx in
                if let accountManager {
                    if let localIdentifiers = accountManager.localIdentifiers(tx: tx) {
                        let deviceId = accountManager.storedDeviceId(tx: tx)
                        Logger.info("local ACI: \(localIdentifiers.aci), device ID: \(deviceId)")
                    } else {
                        let state = accountManager.registrationState(tx: tx)
                        Logger.info("no local ACI! registration state: \(state.logString)")
                    }
                }
                if DebugFlags.internalLogging {
                    NewKeyValueStore.logCollectionStatistics(tx: tx)
                }
            }
        }
    }
}

final class DebugLogs {
    private let dumper: DebugLogDumper
    private var logsDirPath: String?

    init(dumper: DebugLogDumper) {
        self.dumper = dumper
        self.logsDirPath = DebugLogs.collectAndFlushLogs(dumper: dumper)
    }

    deinit {
        if let logsDirPath {
            OWSFileSystem.deleteFile(logsDirPath)
        }
    }

    func showPreview(
        from viewController: UIViewController,
        onSubmit: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
    ) {
        guard let logsDirPath else {
            Logger.error("No logs path found for preview")
            handleError(error: .noLogs, viewController: viewController)
            onCancel?()
            return
        }
        let logFilePaths = ((try? FileManager.default.contentsOfDirectory(atPath: logsDirPath)) ?? []).map {
            URL(fileURLWithPath: logsDirPath).appendingPathComponent($0).path
        }
        let previewVC = DebugLogPreviewViewController(logFilePaths: logFilePaths, onSubmit: onSubmit, onCancel: onCancel)
        let nav = OWSNavigationController(rootViewController: previewVC)
        viewController.present(nav, animated: true)
    }

    /// Presents a log preview with an option to submit. Completion is only
    /// called if the user submits, after the submission is completed.
    @MainActor
    func promptToSubmitLogs(
        from viewController: UIViewController,
        supportTag: String? = nil,
        completion: (() -> Void)? = nil,
    ) {
        showPreview(from: viewController, onSubmit: {
            Task {
                await viewController.awaitableDismiss(animated: true)
                await self.submitLogs(supportTag: supportTag)
                if let completion {
                    try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
                    completion()
                }
            }
        })
    }

    @MainActor
    func promptToSubmitLogs(
        from viewController: UIViewController,
        supportTag: String? = nil,
    ) async {
        let didSubmit = await withCheckedContinuation { continuation in
            showPreview(
                from: viewController,
                onSubmit: {
                    continuation.resume(returning: true)
                },
                onCancel: {
                    continuation.resume(returning: false)
                },
            )
        }
        if didSubmit {
            await viewController.awaitableDismiss(animated: true)
            await submitLogs(supportTag: supportTag)
        }
    }

    enum DebugLogsError: LocalizedError {
        case noLogs
        case couldNotPackageLogs
        case uploadError(zipFilePath: String)

        var errorDescription: String? { localizedErrorMessage }
        var localizedErrorMessage: String {
            switch self {
            case .noLogs:
                OWSLocalizedString(
                    "DEBUG_LOG_ALERT_NO_LOGS",
                    comment: "Error indicating that no debug logs could be found.",
                )
            case .couldNotPackageLogs:
                OWSLocalizedString(
                    "DEBUG_LOG_ALERT_COULD_NOT_PACKAGE_LOGS",
                    comment: "Error indicating that the debug logs could not be packaged.",
                )
            case .uploadError:
                OWSLocalizedString(
                    "DEBUG_LOG_ALERT_ERROR_UPLOADING_LOG",
                    comment: "Error indicating that a debug log could not be uploaded.",
                )
            }
        }
    }

    @MainActor
    private func submitLogs(supportTag: String?) async {
        var supportFilter = "Signal - iOS Debug Log"
        if let supportTag {
            supportFilter += " - \(supportTag)"
        }

        guard let frontmostViewController = UIApplication.shared.frontmostViewControllerIgnoringAlerts else {
            return
        }

        let url: URL?
        do {
            url = try await uploadLogsWithUI(from: frontmostViewController)
        } catch {
            self.handleError(error: error, viewController: frontmostViewController)
            return
        }
        guard let url else { return }

        guard let presentingViewController = UIApplication.shared.frontmostViewControllerIgnoringAlerts else {
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alert = ActionSheetController(
                title: NSLocalizedString("DEBUG_LOG_ALERT_TITLE", comment: "Title of the debug log alert."),
                message: NSLocalizedString("DEBUG_LOG_ALERT_MESSAGE", comment: "Message of the debug log alert."),
            )

            if ComposeSupportEmailOperation.canSendEmails {
                alert.addAction(ActionSheetAction(
                    title: NSLocalizedString(
                        "DEBUG_LOG_ALERT_OPTION_EMAIL",
                        comment: "Label for the 'email debug log' option of the debug log alert.",
                    ),
                    style: .default,
                    handler: { _ in
                        Task {
                            await ComposeSupportEmailOperation.sendEmailWithDefaultErrorHandling(
                                supportFilter: supportFilter,
                                logUrl: url,
                                hasRecentChallenge: self.dumper.challengeReceivedRecently(),
                            )
                        }
                        continuation.resume()
                    },
                ))
            }
            alert.addAction(ActionSheetAction(
                title: NSLocalizedString(
                    "DEBUG_LOG_ALERT_OPTION_COPY_LINK",
                    comment: "Label for the 'copy link' option of the debug log alert.",
                ),
                style: .default,
                handler: { _ in
                    UIPasteboard.general.string = url.absoluteString
                    presentingViewController.presentToast(text: CommonStrings.copiedToClipboardToast, image: .copy)
                    continuation.resume()
                },
            ))
            alert.addAction(ActionSheetAction(
                title: NSLocalizedString(
                    "DEBUG_LOG_ALERT_OPTION_SHARE",
                    comment: "Label for the 'Share' option of the debug log alert.",
                ),
                style: .default,
                handler: { _ in
                    AttachmentSharing.showShareUI(
                        for: url.absoluteString,
                        sender: nil,
                        completion: { continuation.resume() },
                    )
                },
            ))
            alert.addAction(ActionSheetAction(
                title: CommonStrings.cancelButton,
                style: .cancel,
                handler: { _ in continuation.resume() },
            ))
            presentingViewController.presentActionSheet(alert)
        }
    }

    @MainActor
    private func uploadLogsWithUI(from viewController: UIViewController) async throws(DebugLogsError) -> URL? {
        return try await ModalActivityIndicatorViewController.presentAndPropagateResult(
            from: viewController,
            canCancel: true,
        ) { () throws(DebugLogsError) -> URL? in
            do throws(DebugLogsError) {
                return try await self.uploadLogs()
            } catch {
                if Task.isCancelled {
                    return nil
                }
                throw error
            }
        }
    }

    // MARK: - Collecting & uploading

    private static func collectLogs() -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy.MM.dd hh.mm.ss"
        let dateString = dateFormatter.string(from: Date())
        let logsName = "\(dateString) \(UUID().uuidString)"

        let zipDirUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: false).appendingPathComponent(logsName)
        let zipDirPath = zipDirUrl.path
        OWSFileSystem.ensureDirectoryExists(zipDirPath)

        let logFilePaths = DebugLogger.shared.allLogFilePaths
        if logFilePaths.isEmpty {
            return nil
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

        return zipDirPath
    }

    func exportLogs(viewController: UIViewController) {
        AssertIsOnMainThread()
        guard let logsDirPath else {
            return handleError(
                error: .noLogs,
                viewController: viewController,
            )
        }
        AttachmentSharing.showShareUI(for: URL(fileURLWithPath: logsDirPath), sender: nil) {
            OWSFileSystem.deleteFile(logsDirPath)
        }
    }

    private static func collectAndFlushLogs(
        dumper: DebugLogDumper,
    ) -> String? {
        // Dump any additional details that are relevant.
        dumper.dump()
        Logger.info("About to zip debug logs")

        // Flush pending logs to disk.
        Logger.flush()

        // Make a local copy of all of the log files.
        return collectLogs()
    }

    func uploadLogs() async throws(DebugLogsError) -> URL {
        guard let logsDirPath else {
            throw DebugLogsError.noLogs
        }

        // Zip up the log files.
        let zipDirUrl = URL(fileURLWithPath: logsDirPath)
        let zipFileUrl = URL(fileURLWithPath: (logsDirPath as NSString).appendingPathExtension("zip")!)
        let fileCoordinator = NSFileCoordinator()
        var zipError: NSError?
        fileCoordinator.coordinate(readingItemAt: zipDirUrl, options: [.forUploading], error: &zipError) { temporaryFileUrl in
            do {
                try FileManager.default.copyItem(at: temporaryFileUrl, to: zipFileUrl)
            } catch {
                Logger.warn("Couldn't copy zipped file: \(error)")
            }
        }
        if zipError != nil || !OWSFileSystem.fileOrFolderExists(url: zipFileUrl) {
            throw DebugLogsError.couldNotPackageLogs
        }

        OWSFileSystem.protectFileOrFolder(atPath: zipFileUrl.path)

        // Upload the log files.
        do {
            let url = try await DebugLogUploader.uploadFile(fileUrl: zipFileUrl, mimeType: MimeType.applicationZip.rawValue)
            try OWSFileSystem.deleteFile(url: zipFileUrl)
            return url
        } catch {
            throw DebugLogsError.uploadError(zipFilePath: zipFileUrl.path)
        }
    }

    private func handleError(
        error: DebugLogsError,
        viewController: UIViewController,
    ) {
        let logsPath: String?
        let completion: (() -> Void)?
        switch error {
        case .noLogs:
            logsPath = nil
            completion = nil
        case .couldNotPackageLogs:
            logsPath = self.logsDirPath
            completion = nil
        case .uploadError(let zipFilePath):
            logsPath = zipFilePath
            completion = {
                OWSFileSystem.deleteFile(zipFilePath)
            }
        }

        let alert = ActionSheetController(message: error.localizedErrorMessage)

        if let logsPath {
            alert.addAction(.init(
                title: OWSLocalizedString(
                    "DEBUG_LOG_ALERT_OPTION_EXPORT_LOG_ARCHIVE",
                    comment: "Label for the 'Export Logs' fallback option for the alert when debug log uploading fails.",
                ),
            ) { _ in
                AttachmentSharing.showShareUI(
                    for: URL(fileURLWithPath: logsPath),
                    sender: nil,
                    completion: completion,
                )
            })
        }

        alert.addAction(.init(title: CommonStrings.okButton) { _ in
            completion?()
        })

        viewController.presentActionSheet(alert)
    }
}

private enum DebugLogUploader {

    static func uploadFile(fileUrl: URL, mimeType: String) async throws -> URL {
        do {
            let uploadParameters = try await getUploadParameters(fileUrl: fileUrl)
            return try await uploadFile(fileUrl: fileUrl, mimeType: mimeType, uploadParameters: uploadParameters)
        } catch {
            Logger.warn("\(error)")
            throw error
        }
    }

    private static func buildOWSURLSession() -> OWSURLSessionProtocol {
        OWSURLSession(
            securityPolicy: OWSURLSession.defaultSecurityPolicy,
            configuration: OWSURLSession.defaultConfigurationWithoutCaching,
        )
    }

    private static func getUploadParameters(fileUrl: URL) async throws -> UploadParameters {
        let url = URL(string: "https://debuglogs.org/")!
        let response = try await buildOWSURLSession().performRequest(url.absoluteString, method: .get, maxResponseSize: .max, ignoreAppExpiry: true)
        guard let params = response.responseBodyParamParser else {
            throw OWSAssertionError("Invalid response.")
        }
        let uploadUrl: String = try params.required(key: "url")
        let fieldMap: [String: String] = try params.required(key: "fields")
        guard !fieldMap.isEmpty else {
            throw OWSAssertionError("Empty fieldMap!")
        }
        for (key, value) in fieldMap {
            guard
                nil != key.nilIfEmpty,
                nil != value.nilIfEmpty
            else {
                throw OWSAssertionError("Empty key or value in fieldMap!")
            }
        }
        guard let rawUploadKey = fieldMap["key"]?.nilIfEmpty else {
            throw OWSAssertionError("Missing rawUploadKey!")
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

    private struct UploadParameters {
        let uploadUrl: String
        let fieldMap: OrderedDictionary<String, String>
        let uploadKey: String
    }

    private static func uploadFile(
        fileUrl: URL,
        mimeType: String,
        uploadParameters: UploadParameters,
    ) async throws -> URL {
        let urlSession = buildOWSURLSession()

        guard let url = URL(string: uploadParameters.uploadUrl) else {
            throw OWSAssertionError("Invalid url: \(uploadParameters.uploadUrl)")
        }
        let request = URLRequest(url: url)

        var textParts = uploadParameters.fieldMap
        textParts.append(key: "Content-Type", value: mimeType)

        let response = try await urlSession.performMultiPartUpload(
            request: request,
            fileUrl: fileUrl,
            name: "file",
            fileName: fileUrl.lastPathComponent,
            mimeType: mimeType,
            textParts: textParts,
            maxResponseSize: .max,
            ignoreAppExpiry: true,
        )

        let statusCode = response.responseStatusCode
        // We'll accept any 2xx status code.
        guard statusCode / 100 == 2 else {
            Logger.error("statusCode: \(statusCode)")
            Logger.error("headers: \(response.headers)")
            throw OWSAssertionError("Invalid status code: \(statusCode)")
        }

        let urlString = "https://debuglogs.org/\(uploadParameters.uploadKey)"
        guard let url = URL(string: urlString) else {
            throw OWSAssertionError("Invalid url: \(urlString)")
        }
        return url
    }
}
