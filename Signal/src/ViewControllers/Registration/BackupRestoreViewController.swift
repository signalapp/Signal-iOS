//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class BackupRestoreViewController: OWSTableViewController {

    private var hasBegunImport = false

    private var backup: OWSBackup {
        return AppEnvironment.shared.backup
    }

    override public func loadView() {
        navigationItem.title = NSLocalizedString("SETTINGS_BACKUP", comment: "Label for the backup view in app settings.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didPressCancelButton))
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(backupStateDidChange),
                                               name: NSNotification.Name(NSNotificationNameBackupStateDidChange),
                                               object: nil)

        updateTableContents()
    }

    private func updateTableContents() {
        if hasBegunImport {
            updateProgressContents()
        } else {
            updateDecisionContents()
        }
    }

    private func updateDecisionContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()

        section.headerTitle = NSLocalizedString("BACKUP_RESTORE_DECISION_TITLE", comment: "Label for the backup restore decision section.")

        section.add(OWSTableItem.actionItem(withText: NSLocalizedString("CHECK_FOR_BACKUP_DO_NOT_RESTORE",
                                                                        comment: "The label for the 'do not restore backup' button."), actionBlock: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.cancelAndDismiss()
        }))
        section.add(OWSTableItem.actionItem(withText: NSLocalizedString("CHECK_FOR_BACKUP_RESTORE",
                                                                        comment: "The label for the 'restore backup' button."), actionBlock: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.startImport()
        }))

        contents.addSection(section)
        self.contents = contents
    }

    private func updateProgressContents() {
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

        cancelAndDismiss()
    }

    @objc
    private func cancelAndDismiss() {
        Logger.info("")

        backup.setHasPendingRestoreDecision(false)

        self.dismiss(animated: true)
    }

    @objc
    private func startImport() {
        Logger.info("")

        backup.tryToImport()
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
