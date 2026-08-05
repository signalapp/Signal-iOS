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
        section.add(.actionItem(withText: "Enable Local Backups onboarding flow") { [weak self] in
            let localFileBackupStore = LocalFileBackupStore()
            let db = DependenciesBridge.shared.db

            db.write { tx in
                localFileBackupStore.setShouldOverrideShowLocalBackupsOnboarding(true, tx: tx)
            }

            self?.presentToast(text: "Local backups onboarding enabled!")
        })
        section.add(.actionItem(withText: #"Show "Backup Key Reminder" flow"#) { [weak self] in
            guard let self else { return }

            let accountKeyStore = DependenciesBridge.shared.accountKeyStore
            let db = DependenciesBridge.shared.db

            guard let aep = db.read(block: { accountKeyStore.getAccountEntropyPool(tx: $0) }) else {
                presentToast(text: "Missing AEP?!")
                return
            }

            BackupRecoveryKeyReminderCoordinator().present(
                aep: aep,
                fromViewController: self,
                onSuccess: {
                    self.presentToast(text: "Success!")
                },
            )
        })
        section.add(.actionItem(withText: "Backup media integrity check") { [weak self] in
            let vc = InternalListMediaViewController()
            self?.navigationController?.pushViewController(vc, animated: true)
        })
        section.add(.switch(
            withText: "Regenerate backup thumbnails",
            subtitle: "Regenerate backup thumbnails on next offloading run",
            isOn: { db.read(block: backupSettingsStore.shouldGenerateThumbnailsOnNextOffloading(tx:)) },
            actionBlock: { _ in
                db.write { tx in
                    let currentValue = backupSettingsStore.shouldGenerateThumbnailsOnNextOffloading(tx: tx)
                    backupSettingsStore.setShouldGenerateThumbnailsOnNextOffloading(!currentValue, tx: tx)
                }
            },
        ))
        section.add(.switch(
            withText: "Aggressive optimize media",
            subtitle: "Don't keep recent attachments when optimize media is enabled",
            isOn: { Attachment.offloadingThresholdOverride },
            actionBlock: { _ in
                Attachment.offloadingThresholdOverride = !Attachment.offloadingThresholdOverride
            },
        ))

        if BuildFlags.LocalFileBackups.archive {
            section.add(.actionItem(withText: "Choose local file backup destination") {
                DependenciesBridge.shared.localFileBackupManager.promptUserToChooseFileLocation(fromViewController: self, completion: nil)
            })

            section.add(.actionItem(withText: "Save Local File Backup") {
                let localFileBackupExportJob = LocalFileBackupExportJob(
                    accountKeyStore: DependenciesBridge.shared.accountKeyStore,
                    backupArchiveManager: DependenciesBridge.shared.backupArchiveManager,
                    db: DependenciesBridge.shared.db,
                    tsAccountManager: DependenciesBridge.shared.tsAccountManager,
                    localFileBackupManager: DependenciesBridge.shared.localFileBackupManager,
                    securityScopedBookmarkAccess: SecurityScopedBookmarkAccessImpl(),
                )

                let localFileBackupManager = DependenciesBridge.shared.localFileBackupManager

                Task {
                    do {
                        try await localFileBackupExportJob.run(mode: .manual)
                    } catch LocalFileBackupError.unableToAccessLocalFile(let reason) {
                        switch reason {
                        case .stale, .missing:
                            self.presentToast(text: "Unable to restore local file backup attachments (\(reason))")
                            Logger.error("Unable to restore local file backup attachments (\(reason))")
                            await db.awaitableWrite { tx in
                                // Prompt the user to pick a new backup location.
                                localFileBackupManager.setChooseNewLocalBackupLocation(tx: tx)
                            }
                        case .noAccess:
                            self.presentToast(text: "Unable to restore local file backup attachments (no access)")
                            Logger.error("Unable to restore local file backup attachments (no access)")
                        }
                    } catch {
                        self.presentToast(text: "Other error while archiving local file backup: \(error)")
                        Logger.error("Other error while archiving local file backup: \(error)")
                    }
                }
            })
        }

        contents.add(section)

        self.contents = contents
    }
}
