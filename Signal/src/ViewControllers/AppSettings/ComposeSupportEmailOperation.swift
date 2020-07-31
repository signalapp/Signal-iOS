//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit
import MessageUI
import PromiseKit

struct SupportEmailModel {

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

    /// Should be the unlocalized English string localizedSubject
    var subject: String = "Signal iOS Support Request"
    var localizedSubject: String = NSLocalizedString("SUPPORT_EMAIL_SUBJECT",
                                                     comment: "Localized subject for support request emails")
    var device: String = AppVersion.hardwareInfoString
    var osBuild: String = AppVersion.iOSVersionString
    var signalBuild: String = AppVersion.sharedInstance().currentAppVersion
    var locale: String = NSLocale.current.identifier

    var userDescription: String?
    var emojiMood: EmojiMoodPickerView.Mood?
    var debugLogPolicy: LogPolicy = .none
    fileprivate var resolvedDebugString: String?
}

class ComposeSupportEmailOperation {

    enum EmailError: LocalizedError {
        case logUploadTimedOut
        case logUploadFailure(underlyingError: LocalizedError?)
        case invalidURL
        case failedToOpenURL

        public var errorDescription: String? {
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

    static var canSendEmails: Bool {
        return MFMailComposeViewController.canSendMail()
    }

    private var model: SupportEmailModel
    private var isCancelled: Bool = false

    init(model: SupportEmailModel) {
        self.model = model
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
                return .value("[Support note: Log upload failed — \(error.localizedDescription)]")
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
        Promise { (resolver) in
            UIApplication.shared.open(url, options: [:]) { (success) in
                if success {
                    resolver.fulfill_()
                } else {
                    resolver.reject(EmailError.failedToOpenURL)
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
            "--- Support Info ---",
            "Subject: \(model.subject)",
            "Device info: \(model.device)",
            "iOS version: \(model.osBuild)",
            "Signal version: \(model.signalBuild)",
            "Locale: \(model.locale)",
            {
                if let debugURLString = model.resolvedDebugString {
                    return "Debug log: \(debugURLString)"
                } else { return nil }
            }(),
            "",
            model.emojiMood?.stringRepresentation,
            model.emojiMood?.emojiRepresentation
        ]

        return bodyComponents
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}
