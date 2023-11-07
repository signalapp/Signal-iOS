//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MobileCoin
import SignalMessaging
import SignalServiceKit
import SignalUI

class TestingViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = LocalizationNotNeeded("Testing")

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        do {
            let section = OWSTableSection()
            section.footerTitle = LocalizationNotNeeded("These values are temporary and will reset on next launch of the app.")
            contents.add(section)
        }

        do {
            let section = OWSTableSection()
            section.footerTitle = LocalizationNotNeeded("This will reset all of these flags to their default values.")
            section.add(OWSTableItem.actionItem(withText: LocalizationNotNeeded("Reset all testable flags.")) { [weak self] in
                NotificationCenter.default.post(name: TestableFlag.ResetAllTestableFlagsNotification, object: nil)
                self?.updateTableContents()
            })
            contents.add(section)
        }

        func buildSwitchItem(title: String, testableFlag: TestableFlag) -> OWSTableItem {
            OWSTableItem.switch(withText: title,
                                isOn: { testableFlag.get() },
                                target: testableFlag,
                                selector: testableFlag.switchSelector)
        }

        var testableFlags = FeatureFlags.allTestableFlags() + DebugFlags.allTestableFlags()
        testableFlags.sort { (lhs, rhs) -> Bool in
            lhs.title < rhs.title
        }

        for testableFlag in testableFlags {
            let section = OWSTableSection()
            section.footerTitle = testableFlag.details
            section.add(buildSwitchItem(title: testableFlag.title, testableFlag: testableFlag))
            contents.add(section)
        }

        // MARK: - Other

        do {
            if !TSConstants.isUsingProductionService {
                let subscriberIDSection = OWSTableSection()
                subscriberIDSection.footerTitle = LocalizationNotNeeded("Resets subscriberID, which clears current subscription state. Do not do this in prod environment")
                subscriberIDSection.add(OWSTableItem.actionItem(withText: LocalizationNotNeeded("Clear subscriberID State")) {
                    SDSDatabaseStorage.shared.write { transaction in
                        SubscriptionManagerImpl.setSubscriberID(nil, transaction: transaction)
                        SubscriptionManagerImpl.setSubscriberCurrencyCode(nil, transaction: transaction)
                    }
                })
                contents.add(subscriberIDSection)
            }
        }

        if FeatureFlags.cloudBackupFileAlpha {
            let section = OWSTableSection()
            section.footerTitle = "Backup File (pre-pre-pre-alpha)"
            section.add(OWSTableItem.actionItem(withText: LocalizationNotNeeded("Create backup file")) {
                Self.createCloudBackupProto()
            })
            section.add(OWSTableItem.actionItem(withText: LocalizationNotNeeded("Import backup file")) { [weak self] in
                self?.importCloudBackupProto()
            })
            contents.add(section)
        }

        self.contents = contents
    }
}

extension TestingViewController {

    private static func createCloudBackupProto() {
        let vc = UIApplication.shared.frontmostViewController!
        ModalActivityIndicatorViewController.present(fromViewController: vc, canCancel: false, backgroundBlock: { modal in
            Task {
                do {
                    let fileUrl = try await DependenciesBridge.shared.cloudBackupManager.createBackup()
                    await MainActor.run {
                        let activityVC = UIActivityViewController(
                            activityItems: [fileUrl],
                            applicationActivities: nil
                        )
                        let vc = UIApplication.shared.frontmostViewController!
                        activityVC.popoverPresentationController?.sourceView = vc.view
                        activityVC.completionWithItemsHandler = { _, _, _, _ in
                            modal.dismiss()
                        }
                        vc.present(activityVC, animated: true)
                    }
                } catch {
                    // Do nothing
                    modal.dismiss()
                }
            }
        })
    }

    private func importCloudBackupProto() {
        let vc = UIApplication.shared.frontmostViewController!
        guard #available(iOS 14.0, *) else {
            return
        }
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        vc.present(documentPicker, animated: true)
    }
}

extension TestingViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let fileUrl = urls.first else {
            return
        }
        let vc = UIApplication.shared.frontmostViewController!
        ModalActivityIndicatorViewController.present(fromViewController: vc, canCancel: false, backgroundBlock: { modal in
            Task {
                do {
                    try await DependenciesBridge.shared.cloudBackupManager.importBackup(fileUrl: fileUrl)
                    await MainActor.run {
                        modal.dismiss {
                            let vc = UIApplication.shared.frontmostViewController!
                            vc.presentToast(text: "Done!")
                        }
                    }
                } catch {
                    await MainActor.run {
                        modal.dismiss {
                            let vc = UIApplication.shared.frontmostViewController!
                            vc.presentToast(text: "Failed!")
                        }
                    }
                }
            }
        })
    }
}
