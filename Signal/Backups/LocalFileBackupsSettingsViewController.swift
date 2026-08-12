//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class LocalFileBackupsSettingsViewController: OWSTableViewController2 {
    private let localFileBackupExportJobRunner: LocalFileBackupExportJobRunner
    private let localFileBackupStore: LocalFileBackupStore
    private let db: DB
    private let accountKeyStore: AccountKeyStore
    private let localFileBackupManager: LocalFileBackupManager

    init(
        localFileBackupExportJobRunner: LocalFileBackupExportJobRunner,
        localFileBackupStore: LocalFileBackupStore,
        db: DB,
        accountKeyStore: AccountKeyStore,
        localFileBackupManager: LocalFileBackupManager,
    ) {
        self.localFileBackupExportJobRunner = localFileBackupExportJobRunner
        self.localFileBackupStore = localFileBackupStore
        self.db = db
        self.accountKeyStore = accountKeyStore
        self.localFileBackupManager = localFileBackupManager
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_LOCAL_FILE_BACKUPS",
            comment: "Title for the 'on-device backups' settings page.",
        )
        OWSTableViewController2.removeBackButtonText(viewController: self)

        view.backgroundColor = UIColor.Signal.groupedBackground

        updateTableContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lastLocalBackupDetailsDidChange),
            name: .lastLocalBackupDetailsDidChange,
            object: nil,
        )
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    @objc
    private func lastLocalBackupDetailsDidChange() {
        updateTableContents()
    }

    override func topHeader() -> UIView? {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "SETTINGS_LOCAL_FILE_BACKUPS_HEADER_DESCRIPTION",
            comment: "Description shown at the top of the on-device backups settings page.",
        )
        label.font = .dynamicTypeCaption1Clamped
        label.textColor = .Signal.secondaryLabel
        label.numberOfLines = 0

        let container = UIView()
        container.addSubview(label)
        label.autoPinEdge(toSuperviewEdge: .leading, withInset: 32)
        label.autoPinEdge(toSuperviewEdge: .trailing, withInset: 32)
        label.autoPinEdge(toSuperviewEdge: .top, withInset: 12)
        label.autoPinEdge(toSuperviewEdge: .bottom, withInset: 8)
        container.backgroundColor = UIColor.Signal.groupedBackground
        return container
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        contents.add(sections: [
            makeBackUpNowSection(),
            makeDetailsSection(),
            makeTurnOffSection(),
        ])

        self.contents = contents
    }

    // MARK: - Sections

    private func makeBackUpNowSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.add(OWSTableItem(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.preservesSuperviewLayoutMargins = true
                cell.contentView.preservesSuperviewLayoutMargins = true

                let iconView = UIImageView(image: .backup)
                iconView.contentMode = .scaleAspectFit
                iconView.tintColor = Theme.primaryIconColor
                iconView.autoSetDimensions(to: .square(24))
                iconView.setContentHuggingHorizontalHigh()
                iconView.setCompressionResistanceHorizontalHigh()

                let label = UILabel()
                label.text = OWSLocalizedString(
                    "SETTINGS_LOCAL_FILE_BACKUPS_BACK_UP_NOW",
                    comment: "Label for the button that starts a manual on-device backup.",
                )
                label.font = OWSTableItem.primaryLabelFont
                label.textColor = Theme.primaryTextColor
                label.adjustsFontForContentSizeCategory = true

                let stack = UIStackView(arrangedSubviews: [iconView, label])
                stack.axis = .horizontal
                stack.alignment = .center
                stack.spacing = 12

                cell.contentView.addSubview(stack)
                stack.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: { [weak self] in
                guard let self else { return }
                let task = localFileBackupExportJobRunner.startIfNecessary(mode: .manual)
                Task { @MainActor [weak self] in
                    do {
                        try await task.value
                    } catch BackupExportLockError.remoteBackupInProgress {
                        // TODO: [KC] figure out what we want to do here.
                        self?.presentToast(text: "Unable to perform local backup because a remote backup is in progress. Try again later.")
                    }
                }
            },
        ))

        return section
    }

    private func makeDetailsSection() -> OWSTableSection {
        let section = OWSTableSection()

        let lastBackupDetails = db.read { tx in
            localFileBackupStore.lastBackupDetails(tx: tx)
        }

        if let lastBackupDate = lastBackupDetails?.date {
            let lastBackupMessage = BackupSettingsView.Strings.lastBackupString(date: lastBackupDate)
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.buildCell(
                        itemName: OWSLocalizedString(
                            "SETTINGS_LOCAL_FILE_BACKUPS_LAST_BACKUP_DATE",
                            comment: "Label for the row showing when the last on-device backup occurred.",
                        ),
                        accessoryText: lastBackupMessage,
                    )
                    cell.selectionStyle = .none
                    return cell
                },
                actionBlock: nil,
            ))
        }

        if let lastBackupSizeBytes = lastBackupDetails?.backupTotalSizeBytes {
            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.buildCell(
                        itemName: OWSLocalizedString(
                            "SETTINGS_LOCAL_FILE_BACKUPS_BACKUP_SIZE",
                            comment: "Label for the row showing the size of the on-device backup.",
                        ),
                        accessoryText: lastBackupSizeBytes.formatted(.owsByteCount()),
                    )
                    cell.selectionStyle = .none
                    return cell
                },
                actionBlock: nil,
            ))
        }

        if let localFileBackupLocation = try? localFileBackupManager.getSavedSecurityScopedBookmark(type: .archive)?.lastPathComponent {
            section.add(.disclosureItem(
                withText: OWSLocalizedString(
                    "SETTINGS_LOCAL_FILE_BACKUPS_BACKUP_FOLDER",
                    comment: "Label for the row that lets the user choose the folder for on-device backups.",
                ),
                accessoryText: localFileBackupLocation,
                actionBlock: { [weak self] in
                    guard let self else { return }

                    localFileBackupManager.promptUserToChooseFileLocationForArchiving(fromViewController: self, completion: {
                        self.presentToast(
                            text: OWSLocalizedString(
                                "SETTINGS_LOCAL_FILE_BACKUP_FOLDER_UPDATED",
                                comment: "Text for a toast confirming the user changed their local file backup location.",
                            ),
                            image: .checkCircle,
                        )
                    })
                },
            ))
        }

        section.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_LOCAL_FILE_BACKUPS_VIEW_RECOVERY_KEY",
                comment: "Label for the row that shows the on-device backup recovery key.",
            ),
            actionBlock: { [weak self] in
                self?.showViewRecoveryKey()
            },
        ))

        return section
    }

    fileprivate func showViewRecoveryKey() {
        Task { await _showViewRecoveryKey() }
    }

    private func _showViewRecoveryKey() async {
        guard
            let navigationController,
            let authSuccess = await LocalDeviceAuthentication().performBiometricAuth(),
            let aep = db.read(block: { accountKeyStore.getAccountEntropyPool(tx: $0) })
        else {
            return
        }

        let saveAndConfirmKeyCoordinator = BackupSaveAndConfirmKeyCoordinator(
            navigationController: navigationController,
        )
        saveAndConfirmKeyCoordinator.present(
            aepMode: .current(aep, authSuccess),
            options: [
                .showSaveKeyToPasswordManager(onConfirmed: { [weak self, weak navigationController] in
                    guard let self, let navigationController else { return }

                    navigationController.popToViewController(self, animated: true) {
                        self.presentToast(
                            text: OWSLocalizedString(
                                "BACKUP_SETTINGS_CONFIRM_KEY_SUCCESS_TOAST",
                                comment: "Toast shown when the user's Recovery Key has been confirmed successfully.",
                            ),
                            image: .checkCircle,
                        )
                    }
                }),
            ],
        )
    }

    private func makeTurnOffSection() -> OWSTableSection {
        let section = OWSTableSection()

        section.add(.item(
            name: OWSLocalizedString(
                "SETTINGS_LOCAL_FILE_BACKUPS_TURN_OFF",
                comment: "Label for the button that turns off on-device backups.",
            ),
            textColor: UIColor.Signal.red,
            actionBlock: {
                // TODO: [KC] turned-off UI
            },
        ))

        let font = UIFont.dynamicTypeCaption1Clamped
        section.footerAttributedTitle = NSAttributedString.composed(of: [
            OWSLocalizedString(
                "SETTINGS_LOCAL_FILE_BACKUPS_RESTORE_FOOTER",
                comment: "Footer text on the on-device backups settings page explaining how to restore a backup.",
            ),
            " ",
            CommonStrings.learnMore.styled(
                with: .link(URL.Support.backups),
                .font(font),
            ),
        ])
        .styled(
            with: .font(font),
            .color(defaultFooterTextColor),
        )

        return section
    }
}
