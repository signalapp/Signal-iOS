//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class InternalBackupSettingsViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Backups"

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()

        let backupSettingsStore = BackupSettingsStore()
        let db = DependenciesBridge.shared.db
        let lastBackupDetails = db.read { tx in
            return backupSettingsStore.lastBackupDetails(tx: tx)
        }

        section.add(.copyableItem(
            label: "Last Backup chats/messages file size",
            value: lastBackupDetails.flatMap { ByteCountFormatter().string(for: $0.backupFileSizeBytes) },
        ))
        section.add(.actionItem(withText: "Enable Backups onboarding flow") { [weak self] in
            let backupSettingsStore = BackupSettingsStore()
            let db = DependenciesBridge.shared.db

            db.write { tx in
                backupSettingsStore.setShouldOverrideShowBackupsOnboarding(true, tx: tx)
            }

            self?.presentToast(text: "Backups onboarding enabled!")
        })
        section.add(.actionItem(withText: #"Show "Backup Key Reminder" flow"#) { [weak self] in
            guard let self else { return }

            let accountKeyStore = DependenciesBridge.shared.accountKeyStore
            let db = DependenciesBridge.shared.db

            guard let aep = db.read(block: { accountKeyStore.getAccountEntropyPool(tx: $0) }) else {
                presentToast(text: "Missing AEP?!")
                return
            }

            BackupRecoveryKeyReminderCoordinator(
                aep: aep,
                fromViewController: self,
                onSuccess: {
                    self.presentToast(text: "Success!")
                },
            ).presentVerifyFlow()
        })
        section.add(.actionItem(withText: "Backup media integrity check") { [weak self] in
            let vc = InternalListMediaViewController()
            self?.navigationController?.pushViewController(vc, animated: true)
        })
        if RemoteConfig.current.isOptimizeStorageEnabled {
            section.add(.switch(
                withText: "Aggressive optimize media",
                subtitle: "Don't keep recent attachments when optimize media is enabled",
                isOn: { Attachment.offloadingThresholdOverride },
                actionBlock: { _ in
                    Attachment.offloadingThresholdOverride = !Attachment.offloadingThresholdOverride
                },
            ))
        }

        contents.add(section)

        self.contents = contents
    }
}
