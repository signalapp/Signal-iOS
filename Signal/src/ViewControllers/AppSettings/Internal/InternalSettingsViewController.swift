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

        let localNumber = tsAccountManager.localNumber ?? "Unknown"
        infoSection.add(.actionItem(
            withText: "Local Phone Number: \(localNumber)",
            actionBlock: {
                if let number = self.tsAccountManager.localNumber {
                    UIPasteboard.general.string = number
                }
            }
        ))

        let localUuid = tsAccountManager.localUuid?.uuidString ?? "Unknown"
        infoSection.add(.actionItem(
            withText: "Local UUID: \(localUuid)",
            actionBlock: {
                if let uuid = self.tsAccountManager.localUuid?.uuidString {
                    UIPasteboard.general.string = uuid
                }
            }
        ))

        infoSection.add(.label(withText: "Device ID: \(tsAccountManager.storedDeviceId())"))
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

        infoSection.add(.label(withText: "hasYdbFile: \(StorageCoordinator.hasYdbFile)"))
        infoSection.add(.label(withText: "hasGrdbFile: \(StorageCoordinator.hasGrdbFile)"))
        infoSection.add(.label(withText: "hasUnmigratedYdbFile: \(StorageCoordinator.hasUnmigratedYdbFile)"))
        infoSection.add(.label(withText: "didEverUseYdb: \(SSKPreferences.didEverUseYdb())"))

        infoSection.add(.actionItem(
            withText: "Push Token: \(preferences.getPushToken() ?? "Unknown")",
            actionBlock: {
                if let pushToken = self.preferences.getPushToken() {
                    UIPasteboard.general.string = pushToken
                }
            }
        ))
        infoSection.add(.actionItem(
            withText: "VOIP Token: \(preferences.getVoipToken() ?? "Unknown")",
            actionBlock: {
                if let voipToken = self.preferences.getVoipToken() {
                    UIPasteboard.general.string = voipToken
                }
            }
        ))

        infoSection.add(.label(withText: "Audio Category: \(AVAudioSession.sharedInstance().category.rawValue.replacingOccurrences(of: "AVAudioSessionCategory", with: ""))"))
        infoSection.add(.label(withText: "Local Profile Key: \(profileManager.localProfileKey().keyData.hexadecimalString)"))

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
