//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SafariServices
import SignalServiceKit
import SignalUI
import LibSignalClient

public enum RegistrationBackupRestoreError {
    case generic
    case backupNotFound
    case incorrectBackupKey
    case versionMismatch
    case networkError
    case timeout
}

public enum RegistrationBackupErrorNextStep {
    case skipRestore
    case incorrectBackupKey
    case tryAgain
    case restartQuickRestore
}

public protocol RegistrationCoordinatorBackupErrorPresenter {
    func mapToRegistrationError(
        error: Error
    ) -> RegistrationBackupRestoreError

    func presentError(
        error: RegistrationBackupRestoreError,
        isQuickRestore: Bool
    ) async -> RegistrationBackupErrorNextStep?
}

public class RegistrationCoordinatorBackupErrorPresenterImpl:
    NSObject,
    RegistrationCoordinatorBackupErrorPresenter,
    SFSafariViewControllerDelegate
{
    private enum Constants {
        static let incompatibleVersionFAQURL = URL(string: "https://support.signal.org/hc/articles/360007059752")!
        static let backupKeyFAQURL = URL(string: "https://support.signal.org/hc/articles/360007059752")!
        static let itunesStoreUrl = URL(string: "https://itunes.apple.com/app/id874139669")!
    }

    public func mapToRegistrationError(error: Error) -> RegistrationBackupRestoreError {
        switch error {
        case _ where error.isNetworkFailureOrTimeout:
            return .networkError
        case _ where error is BackupKeyMaterialError:
            // Missing backup key
            return .incorrectBackupKey
        case BackupAuthCredentialFetchError.noExistingBackupId:
            // Usually because backups haven't been set up yet.
            return .backupNotFound
        case SignalError.verificationFailed:
            return .incorrectBackupKey
        case _ where error is SignalError:
            // LibSignalError (e.g. - creating credentials)
            return .incorrectBackupKey
        case let httpError as OWSHTTPError where httpError.responseStatusCode == 404:
            // No backup found in the CDN
            return .backupNotFound
        case _ where error is DecodingError:
            fallthrough
        case _ where error is EncodingError:
            return .generic
        case _ where error is CancellationError:
            // Consider this a timeout, try again
            return .timeout
        case BackupImportError.unsupportedVersion:
            return .versionMismatch
        default:
            return .generic
        }
    }

    @MainActor
    public func presentError(
        error: RegistrationBackupRestoreError,
        isQuickRestore: Bool
    ) async -> RegistrationBackupErrorNextStep? {
        guard let topMostVc = UIApplication.shared.frontmostViewController else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            presentError(
                error: error,
                isQuickRestore: isQuickRestore,
                from: topMostVc,
                continuation: continuation
            )
        }
    }

    @MainActor
    private func presentError(
        error: RegistrationBackupRestoreError,
        isQuickRestore: Bool,
        from presenter: UIViewController,
        continuation: CheckedContinuation<RegistrationBackupErrorNextStep?, Never>
    ) {
        let title: String
        let message: String
        let tryAgainString = OWSLocalizedString(
            "REGISTRATION_BACKUP_RESTORE_ERROR_TRY_AGAIN_ACTION",
            comment: "Try again action label for backup restore error recovery."
        )
        let skipRestoreString = OWSLocalizedString(
            "REGISTRATION_BACKUP_RESTORE_ERROR_SKIP_RESTORE_ACTION",
            comment: "Skip restore action label for backup restore error recovery."
        )
        let checkUpdateString = OWSLocalizedString(
            "REGISTRATION_BACKUP_RESTORE_ERROR_CHECK_UPDATE_ACTION",
            comment: "Check for update action label for backup restore error recovery."
        )

        var actions = [ActionSheetAction]()

        switch error {
        case .generic where isQuickRestore:
            // If this is QuickRestore flow, present message about re-scanning
            title = OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_GENERIC_RETRY_TITLE",
                comment: "Title for a sheet warning users about a generic backup restore failure."
            )
            message = OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_GENERIC_RETRY_BODY",
                comment: "Body for a sheet warning users about a generic backup restore failure."
            )
            actions.append(ActionSheetAction(title: CommonStrings.okButton) { _ in
                continuation.resume(returning: .restartQuickRestore)
            })
        case .generic:
            title = OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_GENERIC_TITLE",
                comment: "Title for a sheet warning users about a generic backup manual restore failure."
            )
            message = OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_GENERIC_BODY",
                comment: "Body for a sheet warning users about a generic backup manual restore failure."
            )
            actions.append(ActionSheetAction(title: tryAgainString) { _ in
                continuation.resume(returning: .tryAgain)
            })
            actions.append(ActionSheetAction(title: skipRestoreString) { _ in
                continuation.resume(returning: .skipRestore)
            })
        case .backupNotFound:
            title = OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_BACKUP_NOT_FOUND_TITLE",
                comment: "Title for a sheet warning users about a missing backup."
            )
            message = OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_BACKUP_NOT_FOUND_BODY",
                comment: "Body for a sheet warning users about a missing backup."
            )
            actions.append(ActionSheetAction(title: skipRestoreString) { _ in
                continuation.resume(returning: .skipRestore)
            })
            actions.append(ActionSheetAction(title: tryAgainString) { _ in
                continuation.resume(returning: .tryAgain)
            })
        case .incorrectBackupKey:
            title = OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_INCORRECT_KEY_TITLE",
                comment: "Title for a sheet warning users about an incorrect backup key."
            )
            message = OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_INCORRECT_KEY_BODY",
                comment: "Body for a sheet warning users about an incorrect backup key."
            )
            actions.append(ActionSheetAction(title: tryAgainString) { _ in
                continuation.resume(returning: .incorrectBackupKey)
            })
            actions.append(ActionSheetAction(title: CommonStrings.help) { _ in
                self.presentSupportArticle(
                    url: Constants.backupKeyFAQURL,
                    presenter: presenter
                ) {
                    self.presentError(
                        error: error,
                        isQuickRestore: isQuickRestore,
                        from: presenter,
                        continuation: continuation
                    )
                }
            })
        case .versionMismatch:
            title = OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_UNSUPPORTED_BACKUP_VERSION_TITLE",
                comment: "Title for a sheet warning users about an incompatible backup version."
            )
            message = OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_UNSUPPORTED_BACKUP_VERSION_BODY",
                comment: "Body for a sheet warning users about an incompatible backup version."
            )

            actions.append(ActionSheetAction(title: checkUpdateString) { _ in
                self.presentAppStorePage {
                    self.presentError(
                        error: error,
                        isQuickRestore: isQuickRestore,
                        from: presenter,
                        continuation: continuation
                    )
                }
            })
            if !isQuickRestore {
                actions.append(ActionSheetAction(title: skipRestoreString) { _ in
                    continuation.resume(returning: .skipRestore)
                })
            }
            actions.append(ActionSheetAction(title: CommonStrings.learnMore) { _ in
                self.presentSupportArticle(
                    url: Constants.incompatibleVersionFAQURL,
                    presenter: presenter
                ) {
                    self.presentError(
                        error: error,
                        isQuickRestore: isQuickRestore,
                        from: presenter,
                        continuation: continuation
                    )
                }
            })
        case .networkError, .timeout:
            title = OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_NETWORK_TITLE",
                comment: "Title for a sheet warning users about a network error during backup restore."
            )
            message = OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_NETWORK_BODY",
                comment: "Body for a sheet warning users about a network error during backup restore."
            )

            actions.append(ActionSheetAction(title: tryAgainString) { _ in
                continuation.resume(returning: .tryAgain)
            })
            actions.append(ActionSheetAction(title: CommonStrings.contactSupport) { @MainActor _ in
                Task { @MainActor in
                    self.presentContactSupportSheet(presenter: presenter) {
                        self.presentError(
                            error: error,
                            isQuickRestore: isQuickRestore,
                            from: presenter,
                            continuation: continuation
                        )
                    }
                }
            })
            actions.append(ActionSheetAction(title: skipRestoreString) { _ in
                continuation.resume(returning: .skipRestore)
            })
        }

        let actionSheet = ActionSheetController(title: title, message: message)
        actions.forEach { actionSheet.addAction($0) }
        OWSActionSheets.showActionSheet(actionSheet, fromViewController: presenter)
    }

    @MainActor
    private func presentContactSupportSheet(
        presenter: UIViewController,
        completion: @escaping () -> Void
    ) {
        let title = OWSLocalizedString(
            "REGISTRATION_BACKUP_RESTORE_ERROR_CONTACT_SUPPORT_TITLE",
            comment: "Title for a sheet informing users about contacting support due to an error during backup restore."
        )
        let message = OWSLocalizedString(
            "REGISTRATION_BACKUP_RESTORE_ERROR_CONTACT_SUPPORT_BODY",
            comment: "Body for a sheet informing users about contacting support due to an error during backup restore."
        )
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_CONTACT_SUPPORT_WITH_LOGS_ACTION",
                comment: "Label for action to contact support with logs."
            )
        ) { _ in
            ContactSupportActionSheet.present(
                emailFilter: .backupImportFailed,
                logDumper: .fromGlobals(),
                fromViewController: presenter,
                completion: completion
            )
        })
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "REGISTRATION_BACKUP_RESTORE_ERROR_CONTACT_SUPPORT_WITHOUT_LOGS_ACTION",
                comment: "Label for action to contact support without logs."
            )
        ) { _ in
            ContactSupportActionSheet.present(
                emailFilter: .backupImportFailed,
                logDumper: .fromGlobals(),
                fromViewController: presenter,
                completion: completion
            )
        })
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.cancelButton) { _ in
            completion()
        })

        OWSActionSheets.showActionSheet(actionSheet, fromViewController: presenter)
    }

    private var presentSupportCompletion: (() -> Void)?
    private func presentSupportArticle(
        url: URL,
        presenter: UIViewController,
        completion: @escaping () -> Void
    ) {
        let vc = SFSafariViewController(url: url)
        vc.delegate = self
        presentSupportCompletion = completion
        presenter.present(vc, animated: true, completion: nil)
    }

    private func presentAppStorePage(
        completion: @escaping () -> Void
    ) {
        UIApplication.shared.open(Constants.itunesStoreUrl) { _ in
            completion()
        }
    }

    @objc
    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        presentSupportCompletion?()
        presentSupportCompletion = nil
    }
}

#if DEBUG
public class RegistrationCoordinatorBackupErrorPresenterMock: RegistrationCoordinatorBackupErrorPresenter {
    public func mapToRegistrationError(error: any Error) -> RegistrationBackupRestoreError {
        return .generic
    }

    public func presentError(error: RegistrationBackupRestoreError, isQuickRestore: Bool) async -> RegistrationBackupErrorNextStep? {
        return nil
    }
}
#endif
