//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class DataSettingsTableViewController: OWSTableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_DATA_TITLE", comment: "The title for the data settings.")

        self.useThemeBackgroundColors = true

        updateTableContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mediaBandwidthPreferencesDidChange),
            name: OWSAttachmentDownloads.mediaBandwidthPreferencesDidChange,
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
        }

        contents.addSection(autoDownloadSection)

        self.contents = contents
    }

    // MARK: - Events

    private func showMediaDownloadView(forMediaDownloadType value: MediaDownloadType) {
        let view = MediaDownloadSettingsViewController(mediaDownloadType: value)
        navigationController?.pushViewController(view, animated: true)
    }

    @objc
    func mediaBandwidthPreferencesDidChange() {
        AssertIsOnMainThread()

        updateTableContents()
    }
}
