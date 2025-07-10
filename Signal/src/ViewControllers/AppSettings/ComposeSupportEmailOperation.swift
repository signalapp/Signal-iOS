//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MessageUI
import SignalServiceKit
import SignalUI

struct SupportEmailModel {

    enum LogPolicy {
        /// Do not upload logs
        case none

        /// Attempt to upload the logs and include the resulting URL in the email body
        /// If the upload fails for one reason or another, continue anyway
        case attemptUpload(DebugLogDumper)

        /// Upload the logs. If they fail to upload, fail the operation
        case requireUpload(DebugLogDumper)

        /// Don't upload new logs, instead use the provided link
        case link(URL)
    }

    public static let supportFilterDefault = "Signal iOS Support Request"
    public static let supportFilterPayments = "Signal iOS Support Request - Payments"

    /// An unlocalized string used for filtering by support
    var supportFilter: String = SupportEmailModel.supportFilterDefault

    var localizedSubject: String = OWSLocalizedString(
        "SUPPORT_EMAIL_SUBJECT",
        comment: "Localized subject for support request emails"
    )
    var deviceType: String = UIDevice.current.model
    var deviceIdentifier: String = String(sysctlKey: "hw.machine")?.replacingOccurrences(of: UIDevice.current.model, with: "") ?? "Unknown"
    var iosVersion: String = AppVersionImpl.shared.iosVersionString
    var signalAppVersion: String = AppVersionImpl.shared.currentAppVersion
    var locale: String = NSLocale.current.identifier

    var userDescription: String? = OWSLocalizedString(
        "SUPPORT_EMAIL_DEFAULT_DESCRIPTION",
        comment: "Default prompt for user description in support email requests"
    )
    var emojiMood: EmojiMoodPickerView.Mood?
    var debugLogPolicy: LogPolicy = .none
    fileprivate var resolvedDebugString: String?
}

// MARK: -

final class ComposeSupportEmailOperation: NSObject {

    enum EmailError: LocalizedError, UserErrorDescriptionProvider {
        case logUploadTimedOut
        case logUploadFailure(underlyingError: LocalizedError?)
        case invalidURL
        case failedToOpenURL

        public var errorDescription: String? {
            localizedDescription
        }

        public var localizedDescription: String {
            switch self {
            case .logUploadTimedOut:
                return OWSLocalizedString("ERROR_DESCRIPTION_REQUEST_TIMED_OUT",
                                         comment: "Error indicating that a socket request timed out.")
            case let .logUploadFailure(underlyingError):
                return underlyingError?.errorDescription ??
                    OWSLocalizedString("ERROR_DESCRIPTION_LOG_UPLOAD_FAILED",
                                      comment: "Generic error indicating that log upload failed")
            case .invalidURL:
                return OWSLocalizedString("ERROR_DESCRIPTION_INVALID_SUPPORT_EMAIL",
                                         comment: "Error indicating that a support mailto link could not be created.")
            case .failedToOpenURL:
                return OWSLocalizedString("ERROR_DESCRIPTION_COULD_NOT_LAUNCH_EMAIL",
                                         comment: "Error indicating that openURL for a mailto: URL failed.")
            }
        }
    }

    public static var canSendEmails: Bool {
        return UIApplication.shared.canOpenURL(MailtoLink(to: "", subject: "", body: "").url!)
    }

    private var model: SupportEmailModel
    private var isCancelled: Bool = false

    class func sendEmailWithDefaultErrorHandling(supportFilter: String, logUrl: URL? = nil) async {
        do {
            try await sendEmail(supportFilter: supportFilter, logUrl: logUrl)
        } catch {
            OWSActionSheets.showErrorAlert(message: error.userErrorDescription)
        }
    }

    class func sendEmail(supportFilter: String, logUrl: URL? = nil) async throws {
        var model = SupportEmailModel()
        model.supportFilter = supportFilter
        if let logUrl {
            model.debugLogPolicy = .link(logUrl)
        }
        try await sendEmail(model: model)
    }

    class func sendEmail(model: SupportEmailModel) async throws(EmailError) {
        return try await ComposeSupportEmailOperation(model: model).perform()
    }

    init(model: SupportEmailModel) {
        self.model = model
        super.init()
    }

    func perform() async throws(EmailError) {
        if Task.isCancelled {
            return
        }

        guard Self.canSendEmails else {
            // If we can't send emails, fail early
            throw EmailError.failedToOpenURL
        }

        let debugUrlString: String?
        switch model.debugLogPolicy {
        case .none:
            debugUrlString = nil
        case .link(let url):
            debugUrlString = url.absoluteString
        case .attemptUpload(let dumper):
            do {
                debugUrlString = try await uploadDebugLogWithTimeout(dumper: dumper).absoluteString
            } catch {
                debugUrlString = "[Support note: Log upload failed — \(error.userErrorDescription)]"
            }
        case .requireUpload(let dumper):
            do {
                debugUrlString = try await uploadDebugLogWithTimeout(dumper: dumper).absoluteString
            } catch {
                throw EmailError.logUploadFailure(underlyingError: (error as? LocalizedError))
            }
        }

        self.model.resolvedDebugString = debugUrlString

        guard let emailURL else {
            throw EmailError.invalidURL
        }

        if Task.isCancelled {
            return
        }

        let result = await UIApplication.shared.open(emailURL)
        guard result else {
            throw EmailError.failedToOpenURL
        }
    }

    private func uploadDebugLogWithTimeout(dumper: DebugLogDumper) async throws -> URL {
        do {
            return try await withCooperativeTimeout(seconds: 60) {
                do throws(DebugLogs.UploadDebugLogError) {
                    return try await DebugLogs.uploadLogs(dumper: dumper)
                } catch {
                    // FIXME: Should we do something with the local log file?
                    if let logArchiveOrDirectoryPath = error.logArchiveOrDirectoryPath {
                        _ = OWSFileSystem.deleteFile(logArchiveOrDirectoryPath)
                    }
                    throw DebugLogsUploadError(localizedDescription: error.localizedErrorMessage)
                }
            }
        } catch is CooperativeTimeoutError {
            throw EmailError.logUploadTimedOut
        }
    }

    private var emailURL: URL? {
        let linkBuilder = MailtoLink(to: SupportConstants.supportEmail,
                                     subject: model.localizedSubject,
                                     body: emailBody)
        return linkBuilder.url
    }

    private var emailBody: String {

        // Items in this array will be separated by newlines
        // Return nil to omit the item
        let bodyComponents: [String?] = [
            model.userDescription,
            "",
            OWSLocalizedString(
                "SUPPORT_EMAIL_INFO_DIVIDER",
                comment: "Localized divider for support request emails internal information"
            ),
            String(
                format: OWSLocalizedString(
                    "SUPPORT_EMAIL_FILTER_LABEL_FORMAT",
                    comment: "Localized label for support request email filter string. Embeds {{filter text}}."
                ), model.supportFilter
            ),
            String(
                format: OWSLocalizedString(
                    "SUPPORT_EMAIL_HARDWARE_LABEL_FORMAT",
                    comment: "Localized label for support request email hardware string (e.g. iPhone or iPad). Embeds {{hardware text}}."
                ), model.deviceType
            ),
            String(
                format: OWSLocalizedString(
                    "SUPPORT_EMAIL_HID_LABEL_FORMAT",
                    comment: "Localized label for support request email HID string (e.g. 12,1). Embeds {{hid text}}."
                ), model.deviceIdentifier
            ),
            String(
                format: OWSLocalizedString(
                    "SUPPORT_EMAIL_IOS_VERSION_LABEL_FORMAT",
                    comment: "Localized label for support request email iOS Version string (e.g. 13.4). Embeds {{ios version}}."
                ), model.iosVersion
            ),
            "Signal Version: \(model.signalAppVersion)",
            {
                if let debugURLString = model.resolvedDebugString {
                    return String(
                        format: OWSLocalizedString(
                            "SUPPORT_EMAIL_LOG_URL_LABEL_FORMAT",
                            comment: "Localized label for support request email debug log URL. Embeds {{debug log url}}."
                        ), debugURLString
                    )
                } else { return nil }
            }(),
            String(
                format: OWSLocalizedString(
                    "SUPPORT_EMAIL_LOCALE_LABEL_FORMAT",
                    comment: "Localized label for support request email locale string. Embeds {{locale}}."
                ), model.locale
            ),
            "",
            model.emojiMood?.stringRepresentation,
            model.emojiMood?.emojiRepresentation
        ]

        return bodyComponents
            .compactMap { $0 }
            .joined(separator: "\r\n")
    }
}

struct DebugLogsUploadError: Error, LocalizedError, UserErrorDescriptionProvider {
    let localizedDescription: String

    var errorDescription: String? {
        localizedDescription
    }
}
