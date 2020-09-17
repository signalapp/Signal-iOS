//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class RegistrationController: NSObject {

    // MARK: - Dependencies

    private static var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    private static var backup: OWSBackup {
        return AppEnvironment.shared.backup
    }

    // MARK: -

    private override init() {}

    // MARK: -

    private class func showBackupRestoreView(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = view.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        let restoreView = BackupRestoreViewController()
        navigationController.setViewControllers([restoreView], animated: true)
    }

    // TODO: OnboardingController will eventually need to do something like this.
//    private class func checkCanImportBackup(fromView view: UIViewController) {
//        AssertIsOnMainThread()
//
//        Logger.info("")
//
//        self.backup.checkCanImport({ (canImport) in
//            Logger.info("canImport: \(canImport)")
//
//            if (canImport) {
//                self.backup.setHasPendingRestoreDecision(true)
//
//                self.showBackupRestoreView(fromView: view)
//            } else {
//                self.showProfileView(fromView: view)
//            }
//        }) { (_) in
//            self.showBackupCheckFailedAlert(fromView: view)
//        }
//    }
//
//    private class func showBackupCheckFailedAlert(fromView view: UIViewController) {
//        AssertIsOnMainThread()
//
//        Logger.info("")
//
//        let alert = UIAlertController(title: NSLocalizedString("CHECK_FOR_BACKUP_FAILED_TITLE",
//                                                               comment: "Title for alert shown when the app failed to check for an existing backup."),
//                                      message: NSLocalizedString("CHECK_FOR_BACKUP_FAILED_MESSAGE",
//                                                                  comment: "Message for alert shown when the app failed to check for an existing backup."),
//                                      preferredStyle: .alert)
//        alert.addAction(UIAlertAction(title: NSLocalizedString("REGISTER_FAILED_TRY_AGAIN", comment: ""),
//                                      style: .default) { (_) in
//                                        self.checkCanImportBackup(fromView: view)
//        })
//        alert.addAction(UIAlertAction(title: NSLocalizedString("CHECK_FOR_BACKUP_DO_NOT_RESTORE", comment: "The label for the 'do not restore backup' button."),
//                                      style: .destructive) { (_) in
//                                        self.showProfileView(fromView: view)
//        })
//        view.presentAlert(alert)
//    }
}
