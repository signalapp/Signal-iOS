//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class MediaDownloadSettingsViewController: OWSTableViewController2 {

    private let mediaDownloadType: MediaDownloadType

    public required init(mediaDownloadType: MediaDownloadType) {
        self.mediaDownloadType = mediaDownloadType

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = Self.name(forMediaDownloadType: mediaDownloadType)

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()

        let mediaDownloadType = self.mediaDownloadType
        let currentPreference = databaseStorage.read { transaction in
            OWSAttachmentDownloads.mediaBandwidthPreference(forMediaDownloadType: mediaDownloadType,
                                                          transaction: transaction)
        }
        let mediaBandwidthPreferences = MediaBandwidthPreference.allCases.sorted {
            $0.sortKey < $1.sortKey
        }
        for preference in mediaBandwidthPreferences {
            let preferenceName = Self.name(forMediaBandwidthPreference: preference)
            section.add(OWSTableItem(text: preferenceName,
                        actionBlock: { [weak self] in
                            Self.databaseStorage.write { transaction in
                                OWSAttachmentDownloads.set(mediaBandwidthPreference: preference,
                                                           forMediaDownloadType: mediaDownloadType,
                                                           transaction: transaction)
                            }
                            self?.navigationController?.popViewController(animated: true)
                        },
                        accessoryType: preference == currentPreference ? .checkmark : .none))
        }

        contents.add(section)

        self.contents = contents
    }

    public static func name(forMediaDownloadType value: MediaDownloadType) -> String {
        switch value {
        case .photo:
            return OWSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_TYPE_PHOTO",
                                     comment: "Label for the 'photo' attachment type in the media download settings.")
        case .video:
            return OWSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_TYPE_VIDEO",
                                     comment: "Label for the 'video' attachment type in the media download settings.")
        case .audio:
            return OWSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_TYPE_AUDIO",
                                     comment: "Label for the 'audio' attachment type in the media download settings.")
        case .document:
            return OWSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_TYPE_DOCUMENT",
                                     comment: "Label for the 'document' attachment type in the media download settings.")
        }
    }

    public static func name(forMediaBandwidthPreference value: MediaBandwidthPreference) -> String {
        switch value {
        case .never:
            return OWSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_CONDITION_NEVER",
                                     comment: "Label for the 'never' media attachment download behavior in the media download settings.")
        case .wifiOnly:
            return OWSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_CONDITION_WIFI_ONLY",
                                     comment: "Label for the 'wifi-only' media attachment download behavior in the media download settings.")
        case .wifiAndCellular:
            return OWSLocalizedString("SETTINGS_MEDIA_DOWNLOAD_CONDITION_WIFI_AND_CELLULAR",
                                     comment: "Label for the 'wifi and cellular' media attachment download behavior in the media download settings.")
        }
    }
}
