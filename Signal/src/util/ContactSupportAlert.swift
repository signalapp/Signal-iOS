//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit

@objc
public class ContactSupportAlert: NSObject {
    @objc
    public class func presentAlert(title: String, message: String, emailSupportFilter: String, fromViewController: UIViewController, additionalActions: [ActionSheetAction] = [], customHeader: UIView? = nil, showCancel: Bool = true) {
        presentStep1(title: title, message: message, emailSupportFilter: emailSupportFilter, fromViewController: fromViewController, additionalActions: additionalActions, customHeader: customHeader, showCancel: showCancel)
    }

    // MARK: -

    private class func presentStep1(title: String, message: String, emailSupportFilter: String, fromViewController: UIViewController, additionalActions: [ActionSheetAction], customHeader: UIView? = nil, showCancel: Bool = true) {
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.customHeader = customHeader

        additionalActions.forEach { actionSheet.addAction($0) }

        let proceedAction = ActionSheetAction(title: CommonStrings.contactSupport, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }
            self.presentStep2(emailSupportFilter: emailSupportFilter, fromViewController: fromViewController)
        }
        actionSheet.addAction(proceedAction)
        if showCancel { actionSheet.addAction(OWSActionSheets.cancelAction) }

        fromViewController.present(actionSheet, animated: true)
    }

    public class func presentStep2(emailSupportFilter: String, fromViewController: UIViewController) {
        let submitWithLogTitle = NSLocalizedString("CONTACT_SUPPORT_SUBMIT_WITH_LOG", comment: "Button text")
        let submitWithLogAction = ActionSheetAction(title: submitWithLogTitle, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }

            var emailRequest = SupportEmailModel()
            emailRequest.supportFilter = emailSupportFilter
            emailRequest.debugLogPolicy = .requireUpload
            let operation = ComposeSupportEmailOperation(model: emailRequest)

            ModalActivityIndicatorViewController.present(
                fromViewController: fromViewController,
                canCancel: true
            ) { modal in
                _ = modal.wasCancelledPromise.done { operation.cancel() }

                firstly {
                    operation.perform(on: .sharedUserInitiated)
                }.done {
                    modal.dismiss()
                }.catch { error in
                    guard !modal.wasCancelled else { return }
                    showError(error, emailSupportFilter: emailSupportFilter, fromViewController: fromViewController)
                }
            }
        }

        let submitWithoutLogTitle = NSLocalizedString("CONTACT_SUPPORT_SUBMIT_WITHOUT_LOG", comment: "Button text")
        let submitWithoutLogAction = ActionSheetAction(title: submitWithoutLogTitle, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }

            ComposeSupportEmailOperation.sendEmail(supportFilter: emailSupportFilter).catch { error in
                showError(error, emailSupportFilter: emailSupportFilter, fromViewController: fromViewController)
            }
        }

        let title = NSLocalizedString("CONTACT_SUPPORT_PROMPT_TO_INCLUDE_DEBUG_LOG_TITLE", comment: "Alert title")
        let message = NSLocalizedString("CONTACT_SUPPORT_PROMPT_TO_INCLUDE_DEBUG_LOG_MESSAGE", comment: "Alert body")
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(submitWithLogAction)
        actionSheet.addAction(submitWithoutLogAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        fromViewController.present(actionSheet, animated: true)
    }

    private class func showError(_ error: Error, emailSupportFilter: String, fromViewController: UIViewController) {
        let retryTitle = NSLocalizedString("CONTACT_SUPPORT_PROMPT_ERROR_TRY_AGAIN", comment: "button text")
        let retryAction = ActionSheetAction(title: retryTitle, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }

            presentStep2(emailSupportFilter: emailSupportFilter, fromViewController: fromViewController)
        }

        let message = NSLocalizedString("CONTACT_SUPPORT_PROMPT_ERROR_ALERT_BODY", comment: "Alert body")
        let actionSheet = ActionSheetController(title: error.userErrorDescription, message: message)
        actionSheet.addAction(retryAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        fromViewController.present(actionSheet, animated: true)
    }
}

enum ContactSupportError: Error {
    case pasteLogError(localizedDescription: String)
}
extension ContactSupportError: LocalizedError, UserErrorDescriptionProvider {
    var errorDescription: String? {
        localizedDescription
    }

    public var localizedDescription: String {
        switch self {
        case .pasteLogError(let localizedDescription):
            return localizedDescription
        }
    }
}

extension Pastelog {
    class func uploadLog() -> Promise<URL> {
        return Promise { future in
            Pastelog.uploadLogs(success: future.resolve,
                                failure: { localizedErrorDescription, logArchiveOrDirectoryPath in
                // FIXME: Should we do something with the local log file?
                if let logArchiveOrDirectoryPath = logArchiveOrDirectoryPath {
                    _ = OWSFileSystem.deleteFile(logArchiveOrDirectoryPath)
                }
                let error = ContactSupportError.pasteLogError(localizedDescription: localizedErrorDescription)
                future.reject(error)
            })
        }
    }
}
