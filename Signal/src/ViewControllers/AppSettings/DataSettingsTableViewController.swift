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
            selector: #selector(mediaDownloadConditionsDidChange),
            name: OWSAttachmentDownloads.mediaDownloadConditionsDidChange,
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
                let name = Self.name(forMediaDownloadType: mediaDownloadType)
                let condition = OWSAttachmentDownloads.mediaDownloadCondition(forMediaDownloadType: mediaDownloadType,
                                                                                           transaction: transaction)
                let conditionName = Self.name(forMediaDownloadCondition: condition)

                if condition != MediaDownloadCondition.defaultValue {
                    hasNonDefaultValue = true
                }

                autoDownloadSection.add(OWSTableItem.disclosureItem(withText: name,
                                                                    detailText: conditionName,
                                                                    accessibilityIdentifier: mediaDownloadType.rawValue) { [weak self] in
                    self?.showMediaDownloadView(forMediaDownloadType: mediaDownloadType)
                })
            }

            let resetCopy = NSLocalizedString("SETTINGS_DATA_MEDIA_AUTO_DOWNLOAD_RESET",
                                              comment: "Label for for the 'reset media auto-download settings' button in the data settings.")
            let resetAccessibilityIdentifier = "reset-auto-download-settings"
            if hasNonDefaultValue {
                autoDownloadSection.add(OWSTableItem.actionItem(withText: resetCopy,
                                                                accessibilityIdentifier: resetAccessibilityIdentifier) { [weak self] in
                    Self.databaseStorage.asyncWrite { transaction in
                        OWSAttachmentDownloads.resetMediaDownloadConditions(transaction: transaction)
                    }
                })
            } else {
                autoDownloadSection.add(OWSTableItem.label(withText: resetCopy))
            }
        }

        contents.addSection(autoDownloadSection)

        self.contents = contents
    }

    private static func name(forMediaDownloadType value: MediaDownloadType) -> String {
        switch value {
        case .photo:
            return NSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_TYPE_PHOTO",
                                     comment: "Label for the 'photo' attachment type in the media download settings.")
        case .video:
            return NSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_TYPE_VIDEO",
                                     comment: "Label for the 'video' attachment type in the media download settings.")
        case .audio:
            return NSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_TYPE_AUDIO",
                                     comment: "Label for the 'audio' attachment type in the media download settings.")
        case .document:
            return NSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_TYPE_DOCUMENT",
                                     comment: "Label for the 'document' attachment type in the media download settings.")
        }
    }

    private static func name(forMediaDownloadCondition value: MediaDownloadCondition) -> String {
        switch value {
        case .never:
            return NSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_CONDITION_NEVER",
                                     comment: "Label for the 'never' media attachment download behavior in the media download settings.")
        case .wifiOnly:
            return NSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_CONDITION_WIFI_ONLY",
                                     comment: "Label for the 'wifi-only' media attachment download behavior in the media download settings.")
        case .wifiAndCellular:
            return NSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_CONDITION_WIFI_AND_CELLULAR",
                                     comment: "Label for the 'wifi and cellular' media attachment download behavior in the media download settings.")
        }
    }

    // MARK: - Events

    private func showMediaDownloadView(forMediaDownloadType value: MediaDownloadType) {
    }

    @objc
    func mediaDownloadConditionsDidChange() {
        AssertIsOnMainThread()

        updateTableContents()
    }
}
