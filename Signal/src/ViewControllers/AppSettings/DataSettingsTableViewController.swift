//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class DataSettingsTableViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_DATA_TITLE", comment: "The title for the data settings.")

        updateTableContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: OWSAttachmentDownloads.mediaBandwidthPreferencesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: CallService.callServicePreferencesDidChange,
            object: nil
        )
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let autoDownloadSection = OWSTableSection()
        autoDownloadSection.headerTitle = NSLocalizedString("SETTINGS_DATA_MEDIA_AUTO_DOWNLOAD_HEADER",
                                                            comment: "Header for the 'media auto-download' section in the data settings.")
        autoDownloadSection.footerTitle = NSLocalizedString("SETTINGS_DATA_MEDIA_AUTO_DOWNLOAD_FOOTER",
                                                            comment: "Footer for the 'media auto-download' section in the data settings.")

        let mediaDownloadTypes = MediaDownloadType.allCases.sorted { (left, right) in
            left.sortKey < right.sortKey
        }
        databaseStorage.read { transaction in
            var hasNonDefaultValue = false
            for mediaDownloadType in mediaDownloadTypes {
                let name = MediaDownloadSettingsViewController.name(forMediaDownloadType: mediaDownloadType)
                let preference = OWSAttachmentDownloads.mediaBandwidthPreference(forMediaDownloadType: mediaDownloadType,
                                                                                 transaction: transaction)
                let preferenceName = MediaDownloadSettingsViewController.name(forMediaBandwidthPreference: preference)

                if preference != mediaDownloadType.defaultPreference {
                    hasNonDefaultValue = true
                }

                autoDownloadSection.add(OWSTableItem.disclosureItem(withText: name,
                                                                    detailText: preferenceName,
                                                                    accessibilityIdentifier: mediaDownloadType.rawValue) { [weak self] in
                    self?.showMediaDownloadView(forMediaDownloadType: mediaDownloadType)
                })
            }

            let resetCopy = NSLocalizedString("SETTINGS_DATA_MEDIA_AUTO_DOWNLOAD_RESET",
                                              comment: "Label for for the 'reset media auto-download settings' button in the data settings.")
            let resetAccessibilityIdentifier = "reset-auto-download-settings"
            if hasNonDefaultValue {
                autoDownloadSection.add(OWSTableItem.item(name: resetCopy,
                                                          textColor: Theme.accentBlueColor,
                                                          accessibilityIdentifier: resetAccessibilityIdentifier) {
                    Self.databaseStorage.asyncWrite { transaction in
                        OWSAttachmentDownloads.resetMediaBandwidthPreferences(transaction: transaction)
                    }
                })
            } else {
                autoDownloadSection.add(OWSTableItem.item(name: resetCopy,
                                                          textColor: Theme.secondaryTextAndIconColor,
                                                          accessibilityIdentifier: resetAccessibilityIdentifier))
            }

            let callsSection = OWSTableSection()
            callsSection.headerTitle = NSLocalizedString(
                "SETTINGS_DATA_CALL_SECTION_HEADER",
                comment: "Section header for the call section in data settings")
            callsSection.footerTitle = NSLocalizedString(
                "SETTINGS_DATA_CALL_SECTION_FOOTER",
                comment: "Section footer for the call section in data settings")

            let currentPreference = CallService.highBandwidthNetworkInterfaces(readTx: transaction).inverted
            let currentPreferenceString = NetworkInterfacePreferenceViewController.name(forInterfaceSet: currentPreference)

            callsSection.add(
                OWSTableItem.disclosureItem(
                    withText: NSLocalizedString(
                        "SETTINGS_DATA_CALL_LOW_BANDWIDTH_ITEM_TITLE",
                        comment: "Item title for the low bandwidth call setting"),
                    detailText: currentPreferenceString ?? "",
                    actionBlock: { [weak self] in
                        self?.showCallBandwidthPreferences()
                    }
                ))

            contents.addSection(autoDownloadSection)
            contents.addSection(callsSection)
        }

        self.contents = contents
    }

    // MARK: - Events

    private func showCallBandwidthPreferences() {
        let currentLowBandwidthPreference = databaseStorage.read { readTx in
            CallService.highBandwidthNetworkInterfaces(readTx: readTx).inverted
        }

        let vc = NetworkInterfacePreferenceViewController(
            selectedOption: currentLowBandwidthPreference,
            availableOptions: [.none, .cellular, .wifiAndCellular],
            updateHandler: { [weak self] newLowBandwidthPref in
                self?.databaseStorage.write { writeTx in
                    let newHighBandwidthPref = newLowBandwidthPref.inverted
                    CallService.setHighBandwidthInterfaces(newHighBandwidthPref, writeTx: writeTx)
                }
            })

        vc.title = NSLocalizedString(
            "SETTINGS_DATA_CALL_LOW_BANDWIDTH_ITEM_TITLE",
            comment: "Item title for the low bandwidth call setting")
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showMediaDownloadView(forMediaDownloadType value: MediaDownloadType) {
        let view = MediaDownloadSettingsViewController(mediaDownloadType: value)
        navigationController?.pushViewController(view, animated: true)
    }

    @objc
    func preferencesDidChange() {
        AssertIsOnMainThread()

        updateTableContents()
    }
}
