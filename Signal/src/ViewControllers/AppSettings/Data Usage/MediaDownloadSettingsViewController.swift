//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class MediaDownloadSettingsViewController: OWSTableViewController2 {

    private let mediaDownloadType: MediaBandwidthPreferences.MediaType

    public init(mediaDownloadType: MediaBandwidthPreferences.MediaType) {
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
        let currentPreference = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            DependenciesBridge.shared.mediaBandwidthPreferenceStore.preference(
                for: mediaDownloadType,
                tx: transaction
            )
        }
        let mediaBandwidthPreferences = MediaBandwidthPreferences.Preference.allCases.sorted {
            $0.sortKey < $1.sortKey
        }
        for preference in mediaBandwidthPreferences {
            let preferenceName = Self.name(forMediaBandwidthPreference: preference)
            section.add(OWSTableItem(text: preferenceName,
                        actionBlock: { [weak self] in
                            SSKEnvironment.shared.databaseStorageRef.write { transaction in
                                DependenciesBridge.shared.mediaBandwidthPreferenceStore.set(
                                    preference,
                                    for: mediaDownloadType,
                                    tx: transaction
                                )
                            }
                            self?.navigationController?.popViewController(animated: true)
                        },
                        accessoryType: preference == currentPreference ? .checkmark : .none))
        }

        contents.add(section)

        self.contents = contents
    }

    public static func name(forMediaDownloadType value: MediaBandwidthPreferences.MediaType) -> String {
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

    public static func name(forMediaBandwidthPreference value: MediaBandwidthPreferences.Preference) -> String {
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
