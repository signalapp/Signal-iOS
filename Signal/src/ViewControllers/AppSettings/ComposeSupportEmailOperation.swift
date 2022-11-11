//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import MessageUI

struct SupportEmailModel: Dependencies {

    enum LogPolicy {
        /// Do not upload logs
        case none

        /// Attempt to upload the logs and include the resulting URL in the email body
        /// If the upload fails for one reason or another, continue anyway
        case attemptUpload

        /// Upload the logs. If they fail to upload, fail the operation
        case requireUpload

        /// Don't upload new logs, instead use the provided link
        case link(URL)
    }

    public static let supportFilterDefault = "Signal iOS Support Request"
    public static let supportFilterPayments = "Signal iOS Support Request - Payments"

    /// An unlocalized string used for filtering by support
    var supportFilter: String = SupportEmailModel.supportFilterDefault

    var localizedSubject: String = NSLocalizedString(
        "SUPPORT_EMAIL_SUBJECT",
        comment: "Localized subject for support request emails"
    )
    var deviceType: String = UIDevice.current.model
    var deviceIdentifier: String = String(sysctlKey: "hw.machine")?.replacingOccurrences(of: UIDevice.current.model, with: "") ?? "Unknown"
    var iosVersion: String = AppVersion.iOSVersionString
    var signalVersion4: String = appVersion.currentAppVersion4
    var locale: String = NSLocale.current.identifier

    var userDescription: String? = NSLocalizedString(
        "SUPPORT_EMAIL_DEFAULT_DESCRIPTION",
        comment: "Default prompt for user description in support email requests"
    )
    var emojiMood: EmojiMoodPickerView.Mood?
    var debugLogPolicy: LogPolicy = .none
    fileprivate var resolvedDebugString: String?
}

// MARK: -

@objc
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
                return NSLocalizedString("ERROR_DESCRIPTION_REQUEST_TIMED_OUT",
                                         comment: "Error indicating that a socket request timed out.")
            case let .logUploadFailure(underlyingError):
                return underlyingError?.errorDescription ??
                    NSLocalizedString("ERROR_DESCRIPTION_LOG_UPLOAD_FAILED",
                                      comment: "Generic error indicating that log upload failed")
            case .invalidURL:
                return NSLocalizedString("ERROR_DESCRIPTION_INVALID_SUPPORT_EMAIL",
                                         comment: "Error indicating that a support mailto link could not be created.")
            case .failedToOpenURL:
                return NSLocalizedString("ERROR_DESCRIPTION_COULD_NOT_LAUNCH_EMAIL",
                                         comment: "Error indicating that openURL for a mailto: URL failed.")
            }
        }
    }

    @objc
    public static var canSendEmails: Bool {
        return UIApplication.shared.canOpenURL(MailtoLink(to: "", subject: "", body: "").url!)
    }

    private var model: SupportEmailModel
    private var isCancelled: Bool = false

    @objc
    class func sendEmailWithDefaultErrorHandling(supportFilter: String, logUrl: URL? = nil) {
        sendEmail(supportFilter: supportFilter, logUrl: logUrl).catch { error in
            OWSActionSheets.showErrorAlert(message: error.userErrorDescription)
        }
    }

    class func sendEmail(supportFilter: String, logUrl: URL? = nil) -> Promise<Void> {
        var model = SupportEmailModel()
        model.supportFilter = supportFilter
        if let logUrl = logUrl { model.debugLogPolicy = .link(logUrl) }
        return sendEmail(model: model)
    }

    class func sendEmail(model: SupportEmailModel) -> Promise<Void> {
        let operation = ComposeSupportEmailOperation(model: model)
        return operation.perform(on: .sharedUserInitiated)
    }

    init(model: SupportEmailModel) {
        self.model = model
        super.init()
    }

    func perform(on workQueue: DispatchQueue = .sharedUtility) -> Promise<Void> {
        guard !isCancelled else {
            // If we're cancelled, return an empty success
            return Promise()
        }
        guard Self.canSendEmails else {
            // If we can't send emails, fail early
            return Promise(error: EmailError.failedToOpenURL)
        }

        return firstly { () -> Promise<String?> in
            // Returns an appropriate string for the debug logs
            // If we're not uploading, returns nil
            switch model.debugLogPolicy {
            case .none:
                return .value(nil)
            case let .link(url):
                return .value(url.absoluteString)
            case .attemptUpload, .requireUpload:
                return Pastelog.uploadLog().map { $0.absoluteString }
            }

        }.timeout(seconds: 60, timeoutErrorBlock: { () -> Error in
            // If we haven't finished uploading logs in 10s, give up
            return EmailError.logUploadTimedOut

        })
        .recover(on: workQueue) { error -> Promise<String?> in
            // Suppress the error unless we're required to provide logs
            if case .requireUpload = self.model.debugLogPolicy {
                let emailError = EmailError.logUploadFailure(underlyingError: (error as? LocalizedError))
                return Promise(error: emailError)
            } else {
                return .value("[Support note: Log upload failed — \(error.userErrorDescription)]")
            }

        }.then(on: workQueue) { (debugURLString) -> Promise<URL> in
            self.model.resolvedDebugString = debugURLString

            if let url = self.emailURL {
                return .value(url)
            } else {
                return Promise(error: EmailError.invalidURL)
            }

        }.then(on: .main) { (emailURL: URL) -> Promise<Void> in
            (self.isCancelled == false) ? self.open(mailURL: emailURL) : Promise()
        }
    }

    /// If invoked before the operation completes, will prevent the operation from opening email
    /// Must be called from main queue. Note: This doesn't really *stop* the operation so much as
    /// render it invisible to the user.
    func cancel() {
        AssertIsOnMainThread()
        isCancelled = true
    }

    private func open(mailURL url: URL) -> Promise<Void> {
        Promise { future in
            UIApplication.shared.open(url, options: [:]) { (success) in
                if success {
                    future.resolve()
                } else {
                    future.reject(EmailError.failedToOpenURL)
                }
            }
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
            NSLocalizedString(
                "SUPPORT_EMAIL_INFO_DIVIDER",
                comment: "Localized divider for support request emails internal information"
            ),
            String(
                format: NSLocalizedString(
                    "SUPPORT_EMAIL_FILTER_LABEL_FORMAT",
                    comment: "Localized label for support request email filter string. Embeds {{filter text}}."
                ), model.supportFilter
            ),
            String(
                format: NSLocalizedString(
                    "SUPPORT_EMAIL_HARDWARE_LABEL_FORMAT",
                    comment: "Localized label for support request email hardware string (e.g. iPhone or iPad). Embeds {{hardware text}}."
                ), model.deviceType
            ),
            String(
                format: NSLocalizedString(
                    "SUPPORT_EMAIL_HID_LABEL_FORMAT",
                    comment: "Localized label for support request email HID string (e.g. 12,1). Embeds {{hid text}}."
                ), model.deviceIdentifier
            ),
            String(
                format: NSLocalizedString(
                    "SUPPORT_EMAIL_IOS_VERSION_LABEL_FORMAT",
                    comment: "Localized label for support request email iOS Version string (e.g. 13.4). Embeds {{ios version}}."
                ), model.iosVersion
            ),
            String(
                format: NSLocalizedString(
                    "SUPPORT_EMAIL_SIGNAL_VERSION_LABEL_FORMAT",
                    comment: "Localized label for support request email signal version string. Embeds {{signal version}}."
                ), model.signalVersion4
            ), {
                if let debugURLString = model.resolvedDebugString {
                    return String(
                        format: NSLocalizedString(
                            "SUPPORT_EMAIL_LOG_URL_LABEL_FORMAT",
                            comment: "Localized label for support request email debug log URL. Embeds {{debug log url}}."
                        ), debugURLString
                    )
                } else { return nil }
            }(),
            String(
                format: NSLocalizedString(
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
