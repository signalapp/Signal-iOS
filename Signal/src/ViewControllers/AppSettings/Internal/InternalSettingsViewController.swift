//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AVFoundation
import GRDB
import LibSignalClient
import SignalServiceKit
import SignalUI

class InternalSettingsViewController: OWSTableViewController2 {

    enum Mode: Equatable {
        case registration
        case standard
    }

    private let mode: Mode

    init(
        mode: Mode = .standard,
    ) {
        self.mode = mode
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Internal"

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let debugSection = OWSTableSection()

        #if USE_DEBUG_UI
        debugSection.add(.disclosureItem(
            withText: "Debug UI",
            actionBlock: { [weak self] in
                guard let self = self else { return }
                DebugUITableViewController.presentDebugUI(
                    fromViewController: self,
                    thread: nil
                )
            }
        ))
        #endif

        if DebugFlags.audibleErrorLogging {
            debugSection.add(.disclosureItem(
                withText: OWSLocalizedString("SETTINGS_ADVANCED_VIEW_ERROR_LOG", comment: ""),
                actionBlock: { [weak self] in
                    Logger.flush()
                    let vc = LogPickerViewController(logDirUrl: DebugLogger.errorLogsDir)
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            ))
        }

        debugSection.add(.disclosureItem(
            withText: "Remote Configs",
            actionBlock: { [weak self] in
                let vc = FlagsViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        debugSection.add(.disclosureItem(
            withText: "Testing",
            actionBlock: { [weak self] in
                let vc = TestingViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        debugSection.add(.actionItem(
            withText: "Export Database",
            actionBlock: { [weak self] in
                guard let self = self else {
                    return
                }
                SignalApp.showExportDatabaseUI(from: self)
            }
        ))
        debugSection.add(.actionItem(
            withText: "Query Database",
            actionBlock: { [weak self] in
                let vc = InternalSQLClientViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        ))
        debugSection.add(.actionItem(
            withText: "Run Database Integrity Checks",
            actionBlock: { [weak self] in
                guard let self = self else {
                    return
                }
                SignalApp.showDatabaseIntegrityCheckUI(from: self, databaseStorage: SSKEnvironment.shared.databaseStorageRef)
            }
        ))
        debugSection.add(.actionItem(
            withText: "Clean Orphaned Data",
            actionBlock: { [weak self] in
                guard let self else { return }
                ModalActivityIndicatorViewController.present(
                    fromViewController: self,
                    canCancel: false,
                    asyncBlock: { modalActivityIndicator in
                        try? await OWSOrphanDataCleaner.cleanUp(shouldRemoveOrphanedData: true)
                        modalActivityIndicator.dismiss()
                    },
                )
            }
        ))

        if mode == .registration {
            debugSection.add(.actionItem(withText: "Submit debug logs") {
                DebugLogs.submitLogs(supportTag: "Registration", dumper: .fromGlobals())
            })
        }

        contents.add(debugSection)

        let backupsSection = OWSTableSection(title: "Backups")

        let backupSettingsStore = BackupSettingsStore()
        let db = DependenciesBridge.shared.db
        let lastBackupDetails = db.read { tx in
            return backupSettingsStore.lastBackupDetails(tx: tx)
        }

        if mode != .registration {
            backupsSection.add(.actionItem(withText: "Export + Validate Message Backup proto") { [self] in
                Task {
                    await exportMessageBackupProto()
                }
            })
        }
        if BuildFlags.Backups.showOptimizeMedia {
            backupsSection.add(.switch(
                withText: "Offload all attachments",
                subtitle: "If on and \"Optimize Storage\" enabled, offload all attachments instead of only those >30d old",
                isOn: { Attachment.offloadingThresholdOverride },
                actionBlock: { _ in
                    Attachment.offloadingThresholdOverride = !Attachment.offloadingThresholdOverride
                }
            ))
        }
        backupsSection.add(.switch(
            withText: "Disable transit tier downloads",
            subtitle: "Only download backed-up media, never last 45 days free tier media",
            isOn: { BackupAttachmentDownloadEligibility.disableTransitTierDownloadsOverride },
            actionBlock: { _ in
                BackupAttachmentDownloadEligibility.disableTransitTierDownloadsOverride =
                    !BackupAttachmentDownloadEligibility.disableTransitTierDownloadsOverride
            }
        ))
        backupsSection.add(.switch(
            withText: "Don't reuse transit tier uploads",
            subtitle: "Reupload all attachments for backups, even stuff <45d old",
            isOn: { Upload.disableTransitTierUploadReuse },
            actionBlock: { _ in
                Upload.disableTransitTierUploadReuse =
                    !Upload.disableTransitTierUploadReuse
            }
        ))
        backupsSection.add(.actionItem(withText: "Enable Backups onboarding flow") { [weak self] in
            let backupSettingsStore = BackupSettingsStore()
            let db = DependenciesBridge.shared.db

            db.write { tx in
                backupSettingsStore.wipeHaveBackupsEverBeenEnabled(tx: tx)
            }

            self?.presentToast(text: "Backups onboarding enabled!")
        })
        backupsSection.add(.actionItem(withText: "Backup media integrity check") { [weak self] in
            let vc = InternalListMediaViewController()
            self?.navigationController?.pushViewController(vc, animated: true)
        })
        backupsSection.add(.copyableItem(
            label: "Last Backup chats/messages file size",
            value: lastBackupDetails.flatMap { ByteCountFormatter().string(for: $0.backupFileSizeBytes) }
        ))

        if backupsSection.items.isEmpty.negated {
            contents.add(backupsSection)
        }

        do {
            func makeFileBrowsingActionItem(_ title: String, _ fileUrl: URL) -> OWSTableItem {
                return .actionItem(
                    withText: title,
                    actionBlock: { [weak self] in
                        guard let self else { return }
                        navigationController?.pushViewController(
                            InternalFileBrowserViewController(fileURL: fileUrl),
                            animated: true
                        )
                    }
                )
            }

            let fileBrowsingSection = OWSTableSection(title: "Browse App Files")
            fileBrowsingSection.add(makeFileBrowsingActionItem(
                "App Container: Library",
                URL(string: OWSFileSystem.appLibraryDirectoryPath())!.deletingLastPathComponent()
            ))
            fileBrowsingSection.add(makeFileBrowsingActionItem(
                "App Container: Documents",
                URL(string: OWSFileSystem.appDocumentDirectoryPath())!.deletingLastPathComponent()
            ))
            fileBrowsingSection.add(makeFileBrowsingActionItem(
                "Shared App Container",
                URL(string: OWSFileSystem.appSharedDataDirectoryPath())!.deletingLastPathComponent()
            ))
            contents.add(fileBrowsingSection)
        }

        let (
            contactThreadCount,
            groupThreadCount,
            messageCount,
            attachmentCount,
            donationSubscriberID,
            storageServiceManifestVersion,
            aciRegistrationId,
            pniRegistrationId
        ) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return (
                TSThread.anyFetchAll(transaction: tx).filter { !$0.isGroupThread }.count,
                TSThread.anyFetchAll(transaction: tx).filter { $0.isGroupThread }.count,
                TSInteraction.anyCount(transaction: tx),
                try? Attachment.Record.fetchCount(tx.database),
                DonationSubscriptionManager.getSubscriberID(transaction: tx),
                SSKEnvironment.shared.storageServiceManagerRef.currentManifestVersion(tx: tx),
                DependenciesBridge.shared.tsAccountManager.getRegistrationId(for: .aci, tx: tx),
                DependenciesBridge.shared.tsAccountManager.getRegistrationId(for: .pni, tx: tx)
            )
        }

        let regSection = OWSTableSection(title: "Account")
        let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction
        regSection.add(.copyableItem(label: "Phone Number", value: localIdentifiers?.phoneNumber))
        regSection.add(.copyableItem(label: "ACI", value: localIdentifiers?.aci.serviceIdString))
        regSection.add(.copyableItem(label: "PNI", value: localIdentifiers?.pni?.serviceIdString))
        regSection.add(.copyableItem(label: "Device ID", value: "\(DependenciesBridge.shared.tsAccountManager.storedDeviceIdWithMaybeTransaction)"))
        regSection.add(.copyableItem(label: "ACI Registration ID", value: aciRegistrationId.map({"\($0)"}) ?? "<missing>"))
        regSection.add(.copyableItem(label: "PNI Registration ID", value: pniRegistrationId.map({"\($0)"}) ?? "<missing>"))
        regSection.add(.copyableItem(label: "Push Token", value: SSKEnvironment.shared.preferencesRef.pushToken))
        regSection.add(.copyableItem(label: "Profile Key", value: SSKEnvironment.shared.databaseStorageRef.read(block: SSKEnvironment.shared.profileManagerRef.localUserProfile(tx:))?.profileKey?.keyData.hexadecimalString ?? "none"))
        if let donationSubscriberID {
            regSection.add(.copyableItem(label: "Donation Subscriber ID", value: donationSubscriberID.asBase64Url))
        }
        contents.add(regSection)

        let buildSection = OWSTableSection(title: "Build")
        buildSection.add(.copyableItem(label: "Environment", value: TSConstants.isUsingProductionService ? "Production" : "Staging"))
        buildSection.add(.copyableItem(label: "Variant", value: BuildFlags.buildVariantString))
        buildSection.add(.copyableItem(label: "Current Version", value: AppVersionImpl.shared.currentAppVersion))
        buildSection.add(.copyableItem(label: "First Version", value: AppVersionImpl.shared.firstAppVersion))
        if let buildDetails = Bundle.main.object(forInfoDictionaryKey: "BuildDetails") as? [String: AnyObject] {
            if let signalCommit = (buildDetails["SignalCommit"] as? String)?.strippedOrNil?.prefix(12) {
                buildSection.add(.copyableItem(label: "Git Commit", value: String(signalCommit)))
            }
        }
        contents.add(buildSection)

        // format counts with thousands separator
        let numberFormatter = NumberFormatter()
        numberFormatter.formatterBehavior = .behavior10_4
        numberFormatter.numberStyle = .decimal

        let dbSection = OWSTableSection(title: "Database")
        dbSection.add(.copyableItem(label: "Contact Threads", value: numberFormatter.string(for: contactThreadCount)))
        dbSection.add(.copyableItem(label: "Group Threads", value: numberFormatter.string(for: groupThreadCount)))
        dbSection.add(.copyableItem(label: "Messages", value: numberFormatter.string(for: messageCount)))
        dbSection.add(.copyableItem(label: "Attachments", value: numberFormatter.string(for: attachmentCount)))
        dbSection.add(.actionItem(
            withText: "Disk Usage",
            actionBlock: { [weak self] in
                ModalActivityIndicatorViewController.present(
                    fromViewController: self!,
                    asyncBlock: { [weak self] modal in
                        let vc = await InternalDiskUsageViewController.build()
                        self?.navigationController?.pushViewController(vc, animated: true)
                        modal.dismiss(animated: true)
                    })
            }
        ))
        contents.add(dbSection)

        let deviceSection = OWSTableSection(title: "Device")
        deviceSection.add(.copyableItem(label: "Model", value: AppVersionImpl.shared.hardwareInfoString))
        deviceSection.add(.copyableItem(label: "iOS Version", value: AppVersionImpl.shared.iosVersionString))
        let memoryUsage = LocalDevice.currentMemoryStatus(forceUpdate: true)?.footprint
        let memoryUsageString = memoryUsage.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) }
        deviceSection.add(.copyableItem(label: "Memory Usage", value: memoryUsageString))
        deviceSection.add(.copyableItem(label: "Locale Identifier", value: Locale.current.identifier.nilIfEmpty))
        deviceSection.add(.copyableItem(label: "Language Code", value: Locale.current.languageCode?.nilIfEmpty))
        deviceSection.add(.copyableItem(label: "Region Code", value: Locale.current.regionCode?.nilIfEmpty))
        deviceSection.add(.copyableItem(label: "Currency Code", value: Locale.current.currencyCode?.nilIfEmpty))
        contents.add(deviceSection)

        let otherSection = OWSTableSection(title: "Other")
        otherSection.add(.copyableItem(label: "Storage Service Manifest Version", value: "\(storageServiceManifestVersion)"))
        otherSection.add(.copyableItem(label: "CC?", value: SSKEnvironment.shared.signalServiceRef.isCensorshipCircumventionActive ? "Yes" : "No"))
        otherSection.add(.copyableItem(label: "Audio Category", value: AVAudioSession.sharedInstance().category.rawValue.replacingOccurrences(of: "AVAudioSessionCategory", with: "")))
        otherSection.add(.switch(
            withText: "Spinning checkmarks",
            isOn: { SpinningCheckmarks.shouldSpin },
            target: self,
            selector: #selector(spinCheckmarks(_:))))
        contents.add(otherSection)

        if mode != .registration {
            let paymentsSection = OWSTableSection(title: "Payments")
            paymentsSection.add(.copyableItem(label: "MobileCoin Environment", value: MobileCoinAPI.Environment.current.description))
            paymentsSection.add(.copyableItem(label: "Enabled?", value: SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled ? "Yes" : "No"))
            if SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled, let paymentsEntropy = SUIEnvironment.shared.paymentsSwiftRef.paymentsEntropy {
                paymentsSection.add(.copyableItem(label: "Entropy", value: paymentsEntropy.hexadecimalString))
                if let passphrase = SUIEnvironment.shared.paymentsSwiftRef.passphrase {
                    paymentsSection.add(.copyableItem(label: "Mnemonic", value: passphrase.asPassphrase))
                }
                if let walletAddressBase58 = SUIEnvironment.shared.paymentsSwiftRef.walletAddressBase58() {
                    paymentsSection.add(.copyableItem(label: "B58", value: walletAddressBase58))
                }
            }
            contents.add(paymentsSection)
        }

        self.contents = contents
    }
}

// MARK: -

public enum SpinningCheckmarks {
    static var shouldSpin = false
}

private extension InternalSettingsViewController {

    @objc
    func spinCheckmarks(_ sender: Any) {
        let wasSpinning = SpinningCheckmarks.shouldSpin
        if let view = sender as? UIView {
            if wasSpinning {
                view.layer.removeAnimation(forKey: "spin")
            } else {
                let animation = CABasicAnimation(keyPath: "transform.rotation.z")
                animation.toValue = NSNumber(value: Double.pi * 2)
                animation.duration = TimeInterval.second
                animation.isCumulative = true
                animation.repeatCount = .greatestFiniteMagnitude
                view.layer.add(animation, forKey: "spin")
            }
        }
        SpinningCheckmarks.shouldSpin = !wasSpinning
    }

    func exportMessageBackupProto() async {
        let accountKeyStore = DependenciesBridge.shared.accountKeyStore
        let backupArchiveManager = DependenciesBridge.shared.backupArchiveManager
        let db = DependenciesBridge.shared.db
        let errorPresenter = DependenciesBridge.shared.backupArchiveErrorPresenter
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        func presentBackupErrorsAndToast(_ message: String) {
            errorPresenter.presentOverTopmostViewController { [self] in
                presentToast(text: message)
            }
        }

        let backupKey: MessageBackupKey
        let exportMetadata: Upload.EncryptedBackupUploadMetadata
        do {
            (backupKey, exportMetadata) = try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                from: self
            ) {
                let (messageBackupKey, localIdentifiers) = try db.read { tx in
                    let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)!
                    return (
                        try accountKeyStore.getMessageRootBackupKey(aci: localIdentifiers.aci, tx: tx)!,
                        localIdentifiers,
                    )
                }

                let backupKey = try MessageBackupKey(
                    backupKey: messageBackupKey.backupKey,
                    backupId: messageBackupKey.backupId
                )

                let exportMetadata = try await backupArchiveManager.exportEncryptedBackup(
                    localIdentifiers: localIdentifiers,
                    backupPurpose: .remoteExport(key: messageBackupKey, chatAuth: .implicit()),
                    progress: nil
                )

                return (backupKey, exportMetadata)
            }
        } catch {
            owsFailDebug("Failed to export Backup proto! \(error)")
            presentBackupErrorsAndToast("Failed to export Backup proto!")
            return
        }

        let keyString = "AES key: \(backupKey.aesKey.base64EncodedString())"
        + "\nHMAC key: \(backupKey.hmacKey.base64EncodedString())"

        let activityVC = UIActivityViewController(
            activityItems: [exportMetadata.fileUrl],
            applicationActivities: nil
        )
        activityVC.popoverPresentationController?.sourceView = view
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            UIPasteboard.general.setItems(
                [[UIPasteboard.typeAutomatic: keyString]],
                options: [.expirationDate: Date().addingTimeInterval(120)]
            )

            presentBackupErrorsAndToast("Success! Encryption key copied.")
        }

        present(activityVC, animated: true)
    }
}
