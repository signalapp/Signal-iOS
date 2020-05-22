//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public class ContactSupportAlert {
    public class func presentAlert(title: String, message: String, emailSubject: String, fromViewController: UIViewController, additionalActions: [ActionSheetAction] = []) {
        presentStep1(title: title, message: message, emailSubject: emailSubject, fromViewController: fromViewController, additionalActions: additionalActions)
    }

    // MARK: -

    private class func presentStep1(title: String, message: String, emailSubject: String, fromViewController: UIViewController, additionalActions: [ActionSheetAction]) {
        let actionSheet = ActionSheetController(title: title, message: message)

        additionalActions.forEach { actionSheet.addAction($0) }

        let proceedAction = ActionSheetAction(title: CommonStrings.contactSupport, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }
            self.presentStep2(emailSubject: emailSubject, fromViewController: fromViewController)
        }
        actionSheet.addAction(proceedAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        fromViewController.present(actionSheet, animated: true)
    }

    private class func presentStep2(emailSubject: String, fromViewController: UIViewController) {
        let submitWithLogTitle = NSLocalizedString("CONTACT_SUPPORT_SUBMIT_WITH_LOG", comment: "Button text")
        let submitWithLogAction = ActionSheetAction(title: submitWithLogTitle, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }

            ModalActivityIndicatorViewController.present(fromViewController: fromViewController,
                                                         canCancel: true) { modal in
                firstly {
                    Pastelog.uploadLog()
                }.done { logUrl in
                    guard !modal.wasCancelled else { return }
                    modal.dismiss {
                        do {
                            try Pastelog.submitEmail(subject: emailSubject, logUrl: logUrl)
                        } catch {
                            showError(error, emailSubject: emailSubject, fromViewController: fromViewController)
                        }
                    }
                }.catch { error in
                    guard !modal.wasCancelled else { return }
                    showError(error, emailSubject: emailSubject, fromViewController: fromViewController)
                }
            }
        }

        let submitWithoutLogTitle = NSLocalizedString("CONTACT_SUPPORT_SUBMIT_WITHOUT_LOG", comment: "Button text")
        let submitWithoutLogAction = ActionSheetAction(title: submitWithoutLogTitle, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }

            do {
                try Pastelog.submitEmail(subject: emailSubject, logUrl: nil)
            } catch {
                showError(error, emailSubject: emailSubject, fromViewController: fromViewController)
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

    private class func showError(_ error: Error, emailSubject: String, fromViewController: UIViewController) {
        let retryTitle = NSLocalizedString("CONTACT_SUPPORT_PROMPT_ERROR_TRY_AGAIN", comment: "button text")
        let retryAction = ActionSheetAction(title: retryTitle, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }

            presentStep2(emailSubject: emailSubject, fromViewController: fromViewController)
        }

        let message = NSLocalizedString("CONTACT_SUPPORT_PROMPT_ERROR_ALERT_BODY", comment: "Alert body")
        let actionSheet = ActionSheetController(title: error.localizedDescription, message: message)
        actionSheet.addAction(retryAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        fromViewController.present(actionSheet, animated: true)
    }
}

enum ContactSupportError: Error {
    case pasteLogError(localizedDescription: String)
}
extension ContactSupportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .pasteLogError(let localizedDescription):
            return localizedDescription
        }
    }
}

extension Pastelog {
    class func uploadLog() -> Promise<URL> {
        return Promise { resolver in
            Pastelog.uploadLogs(success: resolver.fulfill,
                                failure: { localizedErrorDescription in
                                    let error = ContactSupportError.pasteLogError(localizedDescription: localizedErrorDescription)
                                    resolver.reject(error)
            })
        }
    }
}
