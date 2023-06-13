//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class SentMediaQualitySettingsViewController: OWSTableViewController2 {
    private lazy var currentQualityLevel = databaseStorage.read { ImageQualityLevel.default(transaction: $0) }
    private let updateHandler: (ImageQualityLevel) -> Void
    init(updateHandler: @escaping (ImageQualityLevel) -> Void) {
        self.updateHandler = updateHandler
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_DATA_SENT_MEDIA_QUALITY_ITEM_TITLE",
            comment: "Item title for the sent media quality setting"
        )

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let section = OWSTableSection()
        section.headerTitle = OWSLocalizedString(
            "SETTINGS_SENT_MEDIA_QUALITY_SECTION_TITLE",
            comment: "The title for the photos and videos section in the sent media quality settings."
        )
        section.footerTitle = OWSLocalizedString(
            "SETTINGS_SENT_MEDIA_QUALITY_SECTION_FOOTER",
            comment: "The footer for the photos and videos section in the sent media quality settings."
        )

        section.add(qualityItem(.standard))
        section.add(qualityItem(.high))

        contents.add(section)

    }

    func qualityItem(_ level: ImageQualityLevel) -> OWSTableItem {
        return OWSTableItem(
            text: level.localizedString,
            actionBlock: { [weak self] in
                self?.changeLevel(level)
            },
            accessoryType: currentQualityLevel == level ? .checkmark : .none
        )
    }

    func changeLevel(_ level: ImageQualityLevel) {
        updateHandler(level)
        navigationController?.popViewController(animated: true)
    }
}
