//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class InternalSettingsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Internal"

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let debugSection = OWSTableSection()

        #if DEBUG
        if DebugUITableViewController.useDebugUI() {
            debugSection.add(.disclosureItem(
                withText: "Debug UI",
                actionBlock: { [weak self] in
                    guard let self = self else { return }
                    DebugUITableViewController.presentDebugUI(from: self)
                }
            ))
        }
        #endif

        if DebugFlags.audibleErrorLogging {
            debugSection.add(.disclosureItem(
                withText: NSLocalizedString("SETTINGS_ADVANCED_VIEW_ERROR_LOG", comment: ""),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "error_logs"),
                actionBlock: { [weak self] in
                    DDLog.flushLog()
                    let vc = LogPickerViewController(logDirUrl: DebugLogger.shared().errorLogsDir)
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            ))
        }

        debugSection.add(.disclosureItem(
            withText: "Flags",
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

        contents.addSection(debugSection)

        let infoSection = OWSTableSection()

        func addCopyableItem(label: String, value: String?) {
            infoSection.add(.item(
                name: label,
                accessoryText: value ?? "None",
                                accessibilityIdentifier: "internal." + label,
                actionBlock: {
                    if let value = value {
                        UIPasteboard.general.string = value
                    }
                }
            ))
        }

        addCopyableItem(label: "Local Phone Number", value: tsAccountManager.localNumber)

        addCopyableItem(label: "Local UUID", value: tsAccountManager.localUuid?.uuidString)

        addCopyableItem(label: "Device ID", value: "\(tsAccountManager.storedDeviceId())")
        if let deviceName = tsAccountManager.storedDeviceName() {
            infoSection.add(.label(withText: "Device Name: \(deviceName)"))
        }

        infoSection.add(.label(withText: "Environment: \(TSConstants.isUsingProductionService ? "Production" : "Staging")"))

        let (threadCount, messageCount, attachmentCount) = databaseStorage.read { transaction in
            return (
                TSThread.anyCount(transaction: transaction),
                TSInteraction.anyCount(transaction: transaction),
                TSAttachment.anyCount(transaction: transaction)
            )
        }

        // format counts with thousands separator
        let numberFormatter = NumberFormatter()
        numberFormatter.formatterBehavior = .behavior10_4
        numberFormatter.numberStyle = .decimal

        infoSection.add(.label(withText: "Threads: \(numberFormatter.string(for: threadCount) ?? "Unknown")"))
        infoSection.add(.label(withText: "Messages: \(numberFormatter.string(for: messageCount) ?? "Unknown")"))
        infoSection.add(.label(withText: "Attachments: \(numberFormatter.string(for: attachmentCount) ?? "Unknown")"))

        let byteCountFormatter = ByteCountFormatter()
        infoSection.add(.label(withText: "Database size: \(byteCountFormatter.string(for: databaseStorage.databaseFileSize) ?? "Unknown")"))
        infoSection.add(.label(withText: "Database WAL size: \(byteCountFormatter.string(for: databaseStorage.databaseWALFileSize) ?? "Unknown")"))
        infoSection.add(.label(withText: "Database SHM size: \(byteCountFormatter.string(for: databaseStorage.databaseSHMFileSize) ?? "Unknown")"))

        infoSection.add(.label(withText: "dataStoreForUI: \(NSStringForDataStore(StorageCoordinator.dataStoreForUI))"))

        infoSection.add(.label(withText: "hasGrdbFile: \(StorageCoordinator.hasGrdbFile)"))
        infoSection.add(.label(withText: "didEverUseYdb: \(SSKPreferences.didEverUseYdb())"))
        infoSection.add(.label(withText: "Core count: \(LocalDevice.allCoreCount) (active: \(LocalDevice.activeCoreCount))"))

        addCopyableItem(label: "Push Token", value: preferences.getPushToken())
        addCopyableItem(label: "VOIP Token", value: preferences.getVoipToken())

        infoSection.add(.label(withText: "Audio Category: \(AVAudioSession.sharedInstance().category.rawValue.replacingOccurrences(of: "AVAudioSessionCategory", with: ""))"))
        infoSection.add(.label(withText: "Local Profile Key: \(profileManager.localProfileKey().keyData.hexadecimalString)"))

        infoSection.add(.label(withText: "MobileCoin Environment: \(MobileCoinAPI.Environment.current)"))
        infoSection.add(.label(withText: "Payments EnabledKey: \(payments.arePaymentsEnabled ? "Yes" : "No")"))
        if let paymentsEntropy = paymentsSwift.paymentsEntropy {
            addCopyableItem(label: "Payments Entropy", value: paymentsEntropy.hexadecimalString)
            if let passphrase = paymentsSwift.passphrase {
                addCopyableItem(label: "Payments mnemonic", value: passphrase.asPassphrase)
            }
            if let walletAddressBase58 = paymentsSwift.walletAddressBase58() {
                addCopyableItem(label: "Payments Address b58", value: walletAddressBase58)
            }
        }

        contents.addSection(infoSection)

        if DebugFlags.groupsV2memberStatusIndicators, let localAddress = tsAccountManager.localAddress {

            let (hasGroupsV2Capability, hasGroupMigrationCapability) = databaseStorage.read {
                (
                    GroupManager.doesUserHaveGroupsV2Capability(address: localAddress, transaction: $0),
                    GroupManager.doesUserHaveGroupsV2MigrationCapability(address: localAddress, transaction: $0)
                )
            }

            let memberStatusSection = OWSTableSection()
            memberStatusSection.add(.label(withText: "Has Groups v2 capability: \(hasGroupsV2Capability)"))
            memberStatusSection.add(.label(withText: "Has Group Migration capability: \(hasGroupMigrationCapability)"))
            contents.addSection(memberStatusSection)
        }

        self.contents = contents
    }
}
