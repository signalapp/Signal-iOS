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
            name: MediaBandwidthPreferences.mediaBandwidthPreferencesDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: .callServicePreferencesDidChange,
            object: nil,
        )
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let autoDownloadSection = OWSTableSection()
        autoDownloadSection.headerTitle = OWSLocalizedString(
            "SETTINGS_DATA_MEDIA_AUTO_DOWNLOAD_HEADER",
            comment: "Header for the 'media auto-download' section in the data settings.",
        )
        autoDownloadSection.footerTitle = OWSLocalizedString(
            "SETTINGS_DATA_MEDIA_AUTO_DOWNLOAD_FOOTER",
            comment: "Footer for the 'media auto-download' section in the data settings.",
        )

        let mediaDownloadTypes = MediaBandwidthPreferences.MediaType.allCases.sorted {
            $0.sortKey < $1.sortKey
        }
        var hasNonDefaultValue = false
        for mediaDownloadType in mediaDownloadTypes {
            let name = MediaDownloadSettingsViewController.name(forMediaDownloadType: mediaDownloadType)
            let bandwidthPreference = SSKEnvironment.shared.databaseStorageRef.read { transaction in
                DependenciesBridge.shared.mediaBandwidthPreferenceStore.preference(
                    for: mediaDownloadType,
                    tx: transaction,
                )
            }
            let preferenceName = MediaDownloadSettingsViewController.name(forMediaBandwidthPreference: bandwidthPreference)

            if bandwidthPreference != mediaDownloadType.defaultPreference {
                hasNonDefaultValue = true
            }

            autoDownloadSection.add(OWSTableItem.disclosureItem(
                withText: name,
                accessoryText: preferenceName,
            ) { [weak self] in
                self?.showMediaDownloadView(forMediaDownloadType: mediaDownloadType)
            })
        }

        let resetCopy = OWSLocalizedString(
            "SETTINGS_DATA_MEDIA_AUTO_DOWNLOAD_RESET",
            comment: "Label for for the 'reset media auto-download settings' button in the data settings.",
        )
        let resetAccessibilityIdentifier = "reset-auto-download-settings"
        if hasNonDefaultValue {
            autoDownloadSection.add(OWSTableItem.item(
                name: resetCopy,
                textColor: Theme.accentBlueColor,
                accessibilityIdentifier: resetAccessibilityIdentifier,
            ) {
                SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
                    DependenciesBridge.shared.mediaBandwidthPreferenceStore.resetPreferences(tx: transaction)
                }
            })
        } else {
            autoDownloadSection.add(OWSTableItem.item(
                name: resetCopy,
                textColor: Theme.secondaryTextAndIconColor,
                accessibilityIdentifier: resetAccessibilityIdentifier,
            ))
        }
        contents.add(autoDownloadSection)

        let sentMediaSection = OWSTableSection()
        sentMediaSection.headerTitle = OWSLocalizedString(
            "SETTINGS_DATA_SENT_MEDIA_SECTION_HEADER",
            comment: "Section header for the sent media section in data settings",
        )
        sentMediaSection.footerTitle = OWSLocalizedString(
            "SETTINGS_DATA_SENT_MEDIA_SECTION_FOOTER",
            comment: "Section footer for the sent media section in data settings",
        )
        sentMediaSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_DATA_SENT_MEDIA_QUALITY_ITEM_TITLE",
                comment: "Item title for the sent media quality setting",
            ),
            accessoryText: SSKEnvironment.shared.databaseStorageRef.read(block: ImageQuality.fetchValue(tx:)).localizedString,
            actionBlock: { [weak self] in
                self?.showSentMediaQualityPreferences()
            },
        ))
        contents.add(sentMediaSection)

        let callsSection = OWSTableSection()
        callsSection.headerTitle = OWSLocalizedString(
            "SETTINGS_DATA_CALL_SECTION_HEADER",
            comment: "Section header for the call section in data settings",
        )
        callsSection.footerTitle = OWSLocalizedString(
            "SETTINGS_DATA_CALL_SECTION_FOOTER",
            comment: "Section footer for the call section in data settings",
        )

        let currentCallDataPreference = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            CallServiceSettingsStore().highDataNetworkInterfaces(tx: transaction).inverted
        }
        let currentCallDataPreferenceString = NetworkInterfacePreferenceViewController.name(
            forInterfaceSet: currentCallDataPreference,
        )

        callsSection.add(.disclosureItem(
            withText: OWSLocalizedString(
                "SETTINGS_DATA_CALL_LOW_BANDWIDTH_ITEM_TITLE",
                comment: "Item title for the low bandwidth call setting",
            ),
            accessoryText: currentCallDataPreferenceString ?? "",
            actionBlock: { [weak self] in
                self?.showCallDataPreferences()
            },
        ))

        contents.add(callsSection)
    }

    // MARK: - Events

    private func showCallDataPreferences() {
        let callServiceSettingsStore = CallServiceSettingsStore()
        let currentLowDataPreference = SSKEnvironment.shared.databaseStorageRef.read { readTx in
            callServiceSettingsStore.highDataNetworkInterfaces(tx: readTx).inverted
        }

        let vc = NetworkInterfacePreferenceViewController(
            selectedOption: currentLowDataPreference,
            availableOptions: [.none, .cellular, .wifiAndCellular],
            updateHandler: { [weak self] newLowDataPref in
                if self != nil {
                    SSKEnvironment.shared.databaseStorageRef.write { writeTx in
                        let newHighDataPref = newLowDataPref.inverted
                        callServiceSettingsStore.setHighDataInterfaces(newHighDataPref, tx: writeTx)
                    }
                }
            },
        )

        vc.title = OWSLocalizedString(
            "SETTINGS_DATA_CALL_LOW_BANDWIDTH_ITEM_TITLE",
            comment: "Item title for the low bandwidth call setting",
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showSentMediaQualityPreferences() {
        let vc = SentMediaQualitySettingsViewController.loadWithSneakyTransaction { [weak self] imageQuality in
            guard let self else { return }
            let databaseStorage = SSKEnvironment.shared.databaseStorageRef
            databaseStorage.write { tx in ImageQuality.setValue(imageQuality, tx: tx) }
            self.updateTableContents()
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showMediaDownloadView(forMediaDownloadType value: MediaBandwidthPreferences.MediaType) {
        let view = MediaDownloadSettingsViewController(mediaDownloadType: value)
        navigationController?.pushViewController(view, animated: true)
    }

    @objc
    private func preferencesDidChange() {
        AssertIsOnMainThread()

        updateTableContents()
    }
}
