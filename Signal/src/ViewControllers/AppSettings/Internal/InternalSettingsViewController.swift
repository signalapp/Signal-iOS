//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging
import UIKit

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
                    Logger.flush()
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
            withText: "Run Database Integrity Checks",
            actionBlock: { [weak self] in
                guard let self = self else {
                    return
                }
                SignalApp.showDatabaseIntegrityCheckUI(from: self)
            }
        ))
        debugSection.add(.actionItem(
            withText: "Clean Orphaned Data",
            actionBlock: { [weak self] in
                guard let self else { return }
                ModalActivityIndicatorViewController.present(
                    fromViewController: self,
                    canCancel: false
                ) { modalActivityIndicator in
                    DispatchQueue.main.async {
                        OWSOrphanDataCleaner.auditAndCleanup(true) {
                            DispatchQueue.main.async { modalActivityIndicator.dismiss() }
                        }
                    }
                }
            }
        ))

        contents.addSection(debugSection)

        let infoSection = OWSTableSection()
        infoSection.add(.label(withText: "Environment: \(TSConstants.isUsingProductionService ? "Production" : "Staging")"))
        infoSection.add(.copyableItem(label: "Build variant", value: FeatureFlags.buildVariantString))
        infoSection.add(.copyableItem(label: "App Release Version", value: AppVersion.shared().currentAppReleaseVersion))
        infoSection.add(.copyableItem(label: "App Build Version", value: AppVersion.shared().currentAppBuildVersion))
        infoSection.add(.copyableItem(label: "App Version 4", value: AppVersion.shared().currentAppVersion4))
        // The first version of the app that was run on this device.
        infoSection.add(.copyableItem(label: "First Version", value: AppVersion.shared().firstAppVersion))

        infoSection.add(.copyableItem(label: "Local Phone Number", value: tsAccountManager.localNumber))

        infoSection.add(.copyableItem(label: "Local ACI", value: tsAccountManager.localUuid?.uuidString))

        infoSection.add(.copyableItem(label: "Local PNI", value: tsAccountManager.localPni?.uuidString))

        infoSection.add(.copyableItem(label: "Device ID", value: "\(tsAccountManager.storedDeviceId())"))
        if let deviceName = tsAccountManager.storedDeviceName() {
            infoSection.add(.label(withText: "Device Name: \(deviceName)"))
        }

        if let buildDetails = Bundle.main.object(forInfoDictionaryKey: "BuildDetails") as? [String: AnyObject] {
            if let signalCommit = (buildDetails["SignalCommit"] as? String)?.strippedOrNil?.prefix(12) {
                infoSection.add(.copyableItem(label: "Signal Commit", value: String(signalCommit)))
            }
            if let webRTCCommit = (buildDetails["WebRTCCommit"] as? String)?.strippedOrNil?.prefix(12) {
                infoSection.add(.copyableItem(label: "WebRTC Commit", value: String(webRTCCommit)))
            }
        }

        infoSection.add(.label(withText: "Memory Usage: \(LocalDevice.memoryUsageString)"))

        let (threadCount, messageCount, attachmentCount, subscriberID) = databaseStorage.read { transaction in
            return (
                TSThread.anyCount(transaction: transaction),
                TSInteraction.anyCount(transaction: transaction),
                TSAttachment.anyCount(transaction: transaction),
                SubscriptionManager.getSubscriberID(transaction: transaction)
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

        infoSection.add(.label(withText: "hasGrdbFile: \(StorageCoordinator.hasGrdbFile)"))
        infoSection.add(.label(withText: "Core count: \(LocalDevice.allCoreCount) (active: \(LocalDevice.activeCoreCount))"))
        infoSection.add(.label(withText: "isCensorshipCircumventionActive: \(self.signalService.isCensorshipCircumventionActive)"))

        infoSection.add(.copyableItem(label: "Push Token", value: preferences.getPushToken()))
        infoSection.add(.copyableItem(label: "VOIP Token", value: preferences.getVoipToken()))

        infoSection.add(.label(withText: "Audio Category: \(AVAudioSession.sharedInstance().category.rawValue.replacingOccurrences(of: "AVAudioSessionCategory", with: ""))"))
        infoSection.add(.label(withText: "Local Profile Key: \(profileManager.localProfileKey().keyData.hexadecimalString)"))

        infoSection.add(.label(withText: "MobileCoin Environment: \(MobileCoinAPI.Environment.current)"))
        infoSection.add(.label(withText: "Payments EnabledKey: \(paymentsHelper.arePaymentsEnabled ? "Yes" : "No")"))
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

        if let subscriberID {
            // This empty label works around a layout bug where the label is unreadable.
            // We should fix that bug but this works for now, as it's just for internal settings.
            infoSection.add(.copyableItem(label: "", value: "Subscriber ID: \(subscriberID.asBase64Url)"))
        }

        contents.addSection(infoSection)

        self.contents = contents
    }
}
