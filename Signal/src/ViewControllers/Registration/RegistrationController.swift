//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class RegistrationController: NSObject {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var backup: OWSBackup {
        return AppEnvironment.shared.backup
    }

    // MARK: registration

    @objc
    public func verificationWasCompleted(fromView view: UIViewController) {
        AssertIsOnMainThread()

        if tsAccountManager.isReregistering() {
            showProfileView(fromView: view)
        } else {
            checkCanImportBackup(fromView: view)
        }
    }

    private func showProfileView(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = view.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        ProfileViewController.present(forRegistration: navigationController)
    }

    private func showBackupRestoreView(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = view.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        let restoreView = BackupRestoreViewController()
        navigationController.setViewControllers([restoreView], animated: true)
    }

    private func checkCanImportBackup(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        self.backup.checkCanImport({ [weak self] (canImport) in
            guard let strongSelf = self else {
                return
            }

            Logger.info("canImport: \(canImport)")

            if (canImport) {
                strongSelf.backup.setHasPendingRestoreDecision(true)

                strongSelf.showBackupRestoreView(fromView: view)
            } else {
                strongSelf.showProfileView(fromView: view)
            }
        }) { [weak self] (_) in
            guard let strongSelf = self else {
                return
            }
            strongSelf.showBackupCheckFailedAlert(fromView: view)
        }
    }

    private func showBackupCheckFailedAlert(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        let alert = UIAlertController(title: NSLocalizedString("CHECK_FOR_BACKUP_FAILED_TITLE",
                                                               comment: "Title for alert shown when the app failed to check for an existing backup."),
                                      message: NSLocalizedString("CHECK_FOR_BACKUP_FAILED_MESSAGE",
                                                                  comment: "Message for alert shown when the app failed to check for an existing backup."),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("REGISTER_FAILED_TRY_AGAIN", comment: ""),
                                      style: .default) { [weak self] (_) in
                                        guard let strongSelf = self else {
                                            return
                                        }
                                        strongSelf.checkCanImportBackup(fromView: view)
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("CHECK_FOR_BACKUP_DO_NOT_RESTORE", comment: "The label for the 'do not restore backup' button."),
                                      style: .destructive) { [weak self] (_) in
                                        guard let strongSelf = self else {
                                            return
                                        }
                                        strongSelf.showProfileView(fromView: view)
        })
        view.present(alert, animated: true)
    }
}
