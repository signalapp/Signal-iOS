//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class DataSettingsTableViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_DATA_TITLE", comment: "The title for the data settings.")

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
        defer { self.contents = contents }

        let autoDownloadSection = OWSTableSection()
        autoDownloadSection.headerTitle = OWSLocalizedString(
            "SETTINGS_DATA_MEDIA_AUTO_DOWNLOAD_HEADER",
            comment: "Header for the 'media auto-download' section in the data settings."
        )
        autoDownloadSection.footerTitle = OWSLocalizedString(
            "SETTINGS_DATA_MEDIA_AUTO_DOWNLOAD_FOOTER",
            comment: "Footer for the 'media auto-download' section in the data settings."
        )

        let mediaDownloadTypes = MediaDownloadType.allCases.sorted {
            $0.sortKey < $1.sortKey
        }
        var hasNonDefaultValue = false
        for mediaDownloadType in mediaDownloadTypes {
            let name = MediaDownloadSettingsViewController.name(forMediaDownloadType: mediaDownloadType)
            let bandwidthPreference = databaseStorage.read { transaction in
                OWSAttachmentDownloads.mediaBandwidthPreference(
                    forMediaDownloadType: mediaDownloadType,
                    transaction: transaction
                )
            }
            let preferenceName = MediaDownloadSettingsViewController.name(forMediaBandwidthPreference: bandwidthPreference)

            if bandwidthPreference != mediaDownloadType.defaultPreference {
                hasNonDefaultValue = true
            }

            autoDownloadSection.add(OWSTableItem.disclosureItem(
                withText: name,
                detailText: preferenceName,
                accessibilityIdentifier: mediaDownloadType.rawValue
            ) { [weak self] in
                self?.showMediaDownloadView(forMediaDownloadType: mediaDownloadType)
            })
        }

        let resetCopy = OWSLocalizedString(
            "SETTINGS_DATA_MEDIA_AUTO_DOWNLOAD_RESET",
            comment: "Label for for the 'reset media auto-download settings' button in the data settings."
        )
        let resetAccessibilityIdentifier = "reset-auto-download-settings"
        if hasNonDefaultValue {
            autoDownloadSection.add(OWSTableItem.item(
                name: resetCopy,
                textColor: Theme.accentBlueColor,
                accessibilityIdentifier: resetAccessibilityIdentifier
            ) {
                Self.databaseStorage.asyncWrite { transaction in
                    OWSAttachmentDownloads.resetMediaBandwidthPreferences(transaction: transaction)
                }
            })
        } else {
            autoDownloadSection.add(OWSTableItem.item(
                name: resetCopy,
                textColor: Theme.secondaryTextAndIconColor,
                accessibilityIdentifier: resetAccessibilityIdentifier
            ))
        }
        contents.add(autoDownloadSection)

        let sentMediaSection = OWSTableSection()
        sentMediaSection.headerTitle = OWSLocalizedString(
            "SETTINGS_DATA_SENT_MEDIA_SECTION_HEADER",
            comment: "Section header for the sent media section in data settings"
        )
        sentMediaSection.footerTitle = OWSLocalizedString(
            "SETTINGS_DATA_SENT_MEDIA_SECTION_FOOTER",
            comment: "Section footer for the sent media section in data settings"
        )
        sentMediaSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_DATA_SENT_MEDIA_QUALITY_ITEM_TITLE",
                comment: "Item title for the sent media quality setting"
            ),
            detailText: databaseStorage.read(block: ImageQualityLevel.resolvedQuality(tx:)).localizedString,
            actionBlock: { [weak self] in
                self?.showSentMediaQualityPreferences()
            }
        ))
        contents.add(sentMediaSection)

        let callsSection = OWSTableSection()
        callsSection.headerTitle = OWSLocalizedString(
            "SETTINGS_DATA_CALL_SECTION_HEADER",
            comment: "Section header for the call section in data settings"
        )
        callsSection.footerTitle = OWSLocalizedString(
            "SETTINGS_DATA_CALL_SECTION_FOOTER",
            comment: "Section footer for the call section in data settings"
        )

        let currentCallDataPreference = databaseStorage.read { transaction in
            CallService.highDataNetworkInterfaces(readTx: transaction).inverted
        }
        let currentCallDataPreferenceString = NetworkInterfacePreferenceViewController.name(
            forInterfaceSet: currentCallDataPreference
        )

        callsSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_DATA_CALL_LOW_BANDWIDTH_ITEM_TITLE",
                comment: "Item title for the low bandwidth call setting"),
            detailText: currentCallDataPreferenceString ?? "",
            actionBlock: { [weak self] in
                self?.showCallDataPreferences()
            }
        ))

        contents.add(callsSection)
    }

    // MARK: - Events

    private func showCallDataPreferences() {
        let currentLowDataPreference = databaseStorage.read { readTx in
            CallService.highDataNetworkInterfaces(readTx: readTx).inverted
        }

        let vc = NetworkInterfacePreferenceViewController(
            selectedOption: currentLowDataPreference,
            availableOptions: [.none, .cellular, .wifiAndCellular],
            updateHandler: { [weak self] newLowDataPref in
                self?.databaseStorage.write { writeTx in
                    let newHighDataPref = newLowDataPref.inverted
                    CallService.setHighDataInterfaces(newHighDataPref, writeTx: writeTx)
                }
            })

        vc.title = OWSLocalizedString(
            "SETTINGS_DATA_CALL_LOW_BANDWIDTH_ITEM_TITLE",
            comment: "Item title for the low bandwidth call setting")
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showSentMediaQualityPreferences() {
        let vc = SentMediaQualitySettingsViewController { [weak self] isHighQuality in
            guard let self else { return }
            self.databaseStorage.write { tx in
                ImageQualityLevel.setUserSelectedHighQuality(isHighQuality, tx: tx)
            }
            self.updateTableContents()
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showMediaDownloadView(forMediaDownloadType value: MediaDownloadType) {
        let view = MediaDownloadSettingsViewController(mediaDownloadType: value)
        navigationController?.pushViewController(view, animated: true)
    }

    @objc
    private func preferencesDidChange() {
        AssertIsOnMainThread()

        updateTableContents()
    }
}
