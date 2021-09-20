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

        infoSection.add(.copyableItem(label: "App Release Version", value: AppVersion.shared().currentAppReleaseVersion))
        infoSection.add(.copyableItem(label: "App Build Version", value: AppVersion.shared().currentAppBuildVersion))
        infoSection.add(.copyableItem(label: "App Version 4", value: AppVersion.shared().currentAppVersion4))
        // The first version of the app that was run on this device.
        infoSection.add(.copyableItem(label: "First Version", value: AppVersion.shared().firstAppVersion))

        infoSection.add(.copyableItem(label: "Local Phone Number", value: tsAccountManager.localNumber))

        infoSection.add(.copyableItem(label: "Local UUID", value: tsAccountManager.localUuid?.uuidString))

        infoSection.add(.copyableItem(label: "Device ID", value: "\(tsAccountManager.storedDeviceId())"))
        if let deviceName = tsAccountManager.storedDeviceName() {
            infoSection.add(.label(withText: "Device Name: \(deviceName)"))
        }

        if let buildDetails = Bundle.main.object(forInfoDictionaryKey: "BuildDetails") as? [String: AnyObject] {
            if let signalCommit = (buildDetails["SignalCommit"] as? String)?.strippedOrNil {
                infoSection.add(.copyableItem(label: "Signal Commit", value: signalCommit))
            }
            if let signalCommit = (buildDetails["WebRTCCommit"] as? String)?.strippedOrNil {
                infoSection.add(.copyableItem(label: "WebRTC Commit", value: signalCommit))
            }
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
        infoSection.add(.label(withText: "isCensorshipCircumventionActive: \(OWSSignalService.shared().isCensorshipCircumventionActive)"))

        infoSection.add(.copyableItem(label: "Push Token", value: preferences.getPushToken()))
        infoSection.add(.copyableItem(label: "VOIP Token", value: preferences.getVoipToken()))

        infoSection.add(.label(withText: "Audio Category: \(AVAudioSession.sharedInstance().category.rawValue.replacingOccurrences(of: "AVAudioSessionCategory", with: ""))"))
        infoSection.add(.label(withText: "Local Profile Key: \(profileManager.localProfileKey().keyData.hexadecimalString)"))

        infoSection.add(.label(withText: "MobileCoin Environment: \(MobileCoinAPI.Environment.current)"))
        infoSection.add(.label(withText: "Payments EnabledKey: \(payments.arePaymentsEnabled ? "Yes" : "No")"))
        if let paymentsEntropy = paymentsSwift.paymentsEntropy {
            infoSection.add(.copyableItem(label: "Payments Entropy", value: paymentsEntropy.hexadecimalString))
            if let passphrase = paymentsSwift.passphrase {
                infoSection.add(.copyableItem(label: "Payments mnemonic", value: passphrase.asPassphrase))
            }
            if let walletAddressBase58 = paymentsSwift.walletAddressBase58() {
                infoSection.add(.copyableItem(label: "Payments Address b58", value: walletAddressBase58))
            }
        }

        infoSection.add(.copyableItem(label: "iOS Version", value: AppVersion.iOSVersionString))
        infoSection.add(.copyableItem(label: "Device Model", value: AppVersion.hardwareInfoString))

        infoSection.add(.copyableItem(label: "Locale Identifier", value: Locale.current.identifier.nilIfEmpty))
        let countryCode = (Locale.current as NSLocale).object(forKey: .countryCode) as? String
        infoSection.add(.copyableItem(label: "Country Code", value: countryCode?.nilIfEmpty))
        infoSection.add(.copyableItem(label: "Language Code", value: Locale.current.languageCode?.nilIfEmpty))
        infoSection.add(.copyableItem(label: "Region Code", value: Locale.current.regionCode?.nilIfEmpty))
        infoSection.add(.copyableItem(label: "Currency Code", value: Locale.current.currencyCode?.nilIfEmpty))

        contents.addSection(infoSection)

        if DebugFlags.groupsV2memberStatusIndicators, let localAddress = tsAccountManager.localAddress {

            let (hasGroupsV2Capability, hasGroupMigrationCapability, hasSenderKeyCapability) = databaseStorage.read {
                (
                    GroupManager.doesUserHaveGroupsV2Capability(address: localAddress, transaction: $0),
                    GroupManager.doesUserHaveGroupsV2MigrationCapability(address: localAddress, transaction: $0),
                    GroupManager.doesUserHaveSenderKeyCapability(address: localAddress, transaction: $0)
                )
            }

            let memberStatusSection = OWSTableSection()
            memberStatusSection.add(.label(withText: "Has Groups v2 capability: \(hasGroupsV2Capability)"))
            memberStatusSection.add(.label(withText: "Has Group Migration capability: \(hasGroupMigrationCapability)"))
            memberStatusSection.add(.label(withText: "Has SenderKey capability: \(hasSenderKeyCapability)"))
            contents.addSection(memberStatusSection)
        }

        self.contents = contents
    }
}
