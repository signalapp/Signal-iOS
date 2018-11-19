//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class BackupRestoreViewController: OWSTableViewController {

    private var backup: OWSBackup {
        return AppEnvironment.shared.backup
    }

    override public func loadView() {
        navigationItem.title = NSLocalizedString("REMINDER_2FA_NAV_TITLE", comment: "Navbar title for when user is periodically prompted to enter their registration lock PIN")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didPressCancelButton))
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(backupStateDidChange),
                                               name: NSNotification.Name(NSNotificationNameBackupStateDidChange),
                                               object: nil)

        backup.tryToImport()

        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()

        section.add(OWSTableItem.label(withText: NSLocalizedString("BACKUP_RESTORE_STATUS", comment: "Label for the backup restore status."), accessoryText: NSStringForBackupImportState(backup.backupImportState)))

        if backup.backupImportState == .inProgress {
            if let backupImportDescription = backup.backupImportDescription {
                section.add(OWSTableItem.label(withText: NSLocalizedString("BACKUP_RESTORE_DESCRIPTION", comment: "Label for the backup restore description."), accessoryText: backupImportDescription))
            }

            if let backupImportProgress = backup.backupImportProgress {
                let progressInt = backupImportProgress.floatValue * 100
                let numberFormatter = NumberFormatter()
                numberFormatter.numberStyle = .percent
                numberFormatter.maximumFractionDigits = 0
                numberFormatter.multiplier = 1
                if let progressString = numberFormatter.string(from: NSNumber(value: progressInt)) {
                    section.add(OWSTableItem.label(withText: NSLocalizedString("BACKUP_RESTORE_PROGRESS", comment: "Label for the backup restore progress."), accessoryText: progressString))
                } else {
                    owsFailDebug("Could not format progress: \(progressInt)")
                }
            }
        }

        contents.addSection(section)
        self.contents = contents

        // TODO: Add cancel button.
    }

    // MARK: Helpers

    @objc
    private func didPressCancelButton(sender: UIButton) {
        Logger.info("")

        // TODO: Cancel import.

        self.dismiss(animated: true)
    }

    private func showHomeView() {
        SignalApp.shared().showHomeView()
    }

    // MARK: - Notifications

    @objc func backupStateDidChange() {
        AssertIsOnMainThread()

        if backup.backupImportState == .succeeded {
            showHomeView()
        } else {
            updateTableContents()
        }
    }
}
