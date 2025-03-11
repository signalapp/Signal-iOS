//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

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
            case .custom(let string): string
            }
        }
    }

    static func present(emailFilter: EmailFilter, fromViewController: UIViewController) {
        Logger.warn("Presenting contact-support action sheet!")

        let submitWithLogTitle = OWSLocalizedString("CONTACT_SUPPORT_SUBMIT_WITH_LOG", comment: "Button text")
        let submitWithLogAction = ActionSheetAction(title: submitWithLogTitle, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }

            var emailRequest = SupportEmailModel()
            emailRequest.supportFilter = emailFilter.asString
            emailRequest.debugLogPolicy = .requireUpload

            ModalActivityIndicatorViewController.present(
                fromViewController: fromViewController,
                canCancel: true
            ) { modal in
                let composeTask = Task {
                    return try await ComposeSupportEmailOperation(model: emailRequest).perform()
                }
                _ = modal.wasCancelledPromise.done { composeTask.cancel() }

                Promise.wrapAsync {
                    try await composeTask.value
                }.done {
                    modal.dismiss()
                }.catch { error in
                    guard !modal.wasCancelled else { return }
                    modal.dismiss(completion: {
                        showError(error, emailFilter: emailFilter, fromViewController: fromViewController)
                    })
                }
            }
        }

        let submitWithoutLogTitle = OWSLocalizedString("CONTACT_SUPPORT_SUBMIT_WITHOUT_LOG", comment: "Button text")
        let submitWithoutLogAction = ActionSheetAction(title: submitWithoutLogTitle, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }

            ComposeSupportEmailOperation.sendEmail(supportFilter: emailFilter.asString).catch { error in
                showError(error, emailFilter: emailFilter, fromViewController: fromViewController)
            }
        }

        let title = OWSLocalizedString("CONTACT_SUPPORT_PROMPT_TO_INCLUDE_DEBUG_LOG_TITLE", comment: "Alert title")
        let message = OWSLocalizedString("CONTACT_SUPPORT_PROMPT_TO_INCLUDE_DEBUG_LOG_MESSAGE", comment: "Alert body")
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(submitWithLogAction)
        actionSheet.addAction(submitWithoutLogAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        fromViewController.present(actionSheet, animated: true)
    }

    private static func showError(_ error: Error, emailFilter: EmailFilter, fromViewController: UIViewController) {
        let retryTitle = OWSLocalizedString("CONTACT_SUPPORT_PROMPT_ERROR_TRY_AGAIN", comment: "button text")
        let retryAction = ActionSheetAction(title: retryTitle, style: .default) { [weak fromViewController] _ in
            guard let fromViewController = fromViewController else { return }

            present(emailFilter: emailFilter, fromViewController: fromViewController)
        }

        let message = OWSLocalizedString("CONTACT_SUPPORT_PROMPT_ERROR_ALERT_BODY", comment: "Alert body")
        let actionSheet = ActionSheetController(title: error.userErrorDescription, message: message)
        actionSheet.addAction(retryAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        fromViewController.present(actionSheet, animated: true)
    }
}

// MARK: -

struct DebugLogsUploadError: Error, LocalizedError, UserErrorDescriptionProvider {
    let localizedDescription: String

    var errorDescription: String? {
        localizedDescription
    }
}

extension DebugLogs {
    static func uploadLog() async throws(DebugLogsUploadError) -> URL {
        do {
            return try await DebugLogs.uploadLogs()
        } catch {
            // FIXME: Should we do something with the local log file?
            if let logArchiveOrDirectoryPath = error.logArchiveOrDirectoryPath {
                _ = OWSFileSystem.deleteFile(logArchiveOrDirectoryPath)
            }
            throw DebugLogsUploadError(localizedDescription: error.localizedErrorMessage)
        }
    }
}
