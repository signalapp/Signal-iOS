//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

class MediaDownloadSettingsViewController: OWSTableViewController {

    private let mediaDownloadType: MediaDownloadType

    public required init(mediaDownloadType: MediaDownloadType) {
        self.mediaDownloadType = mediaDownloadType

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = Self.name(forMediaDownloadType: mediaDownloadType)

        self.useThemeBackgroundColors = true

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()

        let mediaDownloadType = self.mediaDownloadType
        let currentCondition = databaseStorage.read { transaction in
            OWSAttachmentDownloads.mediaDownloadCondition(forMediaDownloadType: mediaDownloadType,
                                                          transaction: transaction)
        }
        let mediaDownloadConditions = MediaDownloadCondition.allCases.sorted { (left, right) in
            left.sortKey < right.sortKey
        }
        for condition in mediaDownloadConditions {
            let conditionName = Self.name(forMediaDownloadCondition: condition)
            section.add(OWSTableItem(text: conditionName,
                        actionBlock: { [weak self] in
                            Self.databaseStorage.write { transaction in
                                OWSAttachmentDownloads.set(mediaDownloadCondition: condition,
                                                           forMediaDownloadType: mediaDownloadType,
                                                           transaction: transaction)
                            }
                            self?.navigationController?.popViewController(animated: true)
                        },
                        accessoryType: condition == currentCondition ? .checkmark : .none))
        }

        contents.addSection(section)

        self.contents = contents
    }

    public static func name(forMediaDownloadType value: MediaDownloadType) -> String {
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

    public static func name(forMediaDownloadCondition value: MediaDownloadCondition) -> String {
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
}
