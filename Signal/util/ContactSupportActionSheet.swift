//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

extension ActionSheetAction {
    static func contactSupport(
        emailFilter: ContactSupportActionSheet.EmailFilter,
        fromViewController: UIViewController,
    ) -> ActionSheetAction {
        ActionSheetAction(title: CommonStrings.contactSupport) { _ in
            ContactSupportActionSheet.present(
                emailFilter: emailFilter,
                logDumper: .fromGlobals(),
                fromViewController: fromViewController,
            )
        }
    }
}

enum ContactSupportActionSheet {
    enum EmailFilter: Equatable {
        enum RegistrationPINMode: String {
            case v1
            case v2NoReglock
            case v2WithReglock
            case v2WithUnknownReglockState
        }

        case registrationPINMode(RegistrationPINMode)
        case deviceTransfer
        case backupExportFailed
        case backupImportFailed
        case backupDisableFailed
        case custom(String)

        fileprivate var asString: String {
            return switch self {
            case .registrationPINMode(.v1): "Signal PIN - iOS (V1 PIN)"
            case .registrationPINMode(.v2NoReglock): "Signal PIN - iOS (V2 PIN without RegLock)"
            case .registrationPINMode(.v2WithReglock): "Signal PIN - iOS (V2 PIN)"
            case .registrationPINMode(.v2WithUnknownReglockState): "Signal PIN - iOS (V2 PIN with unknown reglock)"
            case .deviceTransfer: "Signal iOS Transfer"
            case .backupExportFailed: "iOS Backup Export Failed"
            case .backupImportFailed: "iOS Backup Import Failed"
            case .backupDisableFailed: "iOS Backup Disable Failed"
            case .custom(let string): string
            }
        }
    }

    static func present(
        emailFilter: EmailFilter,
        logDumper: DebugLogDumper,
        fromViewController: UIViewController,
        completion: (() -> Void)? = nil
    ) {
        Logger.warn("Presenting contact-support action sheet!")

        let submitWithLogTitle = OWSLocalizedString("CONTACT_SUPPORT_SUBMIT_WITH_LOG", comment: "Button text")
        let submitWithLogAction = ActionSheetAction(title: submitWithLogTitle, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }

            var emailRequest = SupportEmailModel()
            emailRequest.supportFilter = emailFilter.asString
            emailRequest.debugLogPolicy = .requireUpload(logDumper)

            ModalActivityIndicatorViewController.present(
                fromViewController: fromViewController,
                canCancel: true,
                asyncBlock: { modal in
                    let result = await Result {
                        try await ComposeSupportEmailOperation(model: emailRequest).perform()
                    }
                    modal.dismissIfNotCanceled(completionIfNotCanceled: {
                        do {
                            try result.get()
                            completion?()
                        } catch {
                            showError(
                                error,
                                emailFilter: emailFilter,
                                logDumper: logDumper,
                                fromViewController: fromViewController,
                                completion: completion
                            )
                        }
                    })
                }
            )
        }

        let submitWithoutLogTitle = OWSLocalizedString("CONTACT_SUPPORT_SUBMIT_WITHOUT_LOG", comment: "Button text")
        let submitWithoutLogAction = ActionSheetAction(title: submitWithoutLogTitle, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }
            Task {
                do {
                    try await ComposeSupportEmailOperation.sendEmail(supportFilter: emailFilter.asString)
                } catch {
                    showError(error, emailFilter: emailFilter, logDumper: logDumper, fromViewController: fromViewController)
                }
            }
        }

        let title = OWSLocalizedString("CONTACT_SUPPORT_PROMPT_TO_INCLUDE_DEBUG_LOG_TITLE", comment: "Alert title")
        let message = OWSLocalizedString("CONTACT_SUPPORT_PROMPT_TO_INCLUDE_DEBUG_LOG_MESSAGE", comment: "Alert body")
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(submitWithLogAction)
        actionSheet.addAction(submitWithoutLogAction)
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
            handler: { _ in
                completion?()
            }
        ))

        fromViewController.present(actionSheet, animated: true)
    }

    private static func showError(
        _ error: Error,
        emailFilter: EmailFilter,
        logDumper: DebugLogDumper,
        fromViewController: UIViewController,
        completion: (() -> Void)? = nil
    ) {
        let retryTitle = OWSLocalizedString("CONTACT_SUPPORT_PROMPT_ERROR_TRY_AGAIN", comment: "button text")
        let retryAction = ActionSheetAction(title: retryTitle, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }

            present(
                emailFilter: emailFilter,
                logDumper: logDumper,
                fromViewController: fromViewController,
                completion: completion
            )
        }

        let message = OWSLocalizedString("CONTACT_SUPPORT_PROMPT_ERROR_ALERT_BODY", comment: "Alert body")
        let actionSheet = ActionSheetController(title: error.userErrorDescription, message: message)
        actionSheet.addAction(retryAction)
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
            handler: { _ in
                completion?()
            }
        ))

        fromViewController.present(actionSheet, animated: true)
    }
}
