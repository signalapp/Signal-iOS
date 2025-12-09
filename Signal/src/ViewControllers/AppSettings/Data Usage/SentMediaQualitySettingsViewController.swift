//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class SentMediaQualitySettingsViewController: OWSTableViewController2 {
    private var imageQuality: ImageQuality
    private let updateHandler: (_ imageQuality: ImageQuality) -> Void

    static func loadWithSneakyTransaction(updateHandler: @escaping (_ imageQuality: ImageQuality) -> Void) -> Self {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        return Self(
            imageQuality: databaseStorage.read(block: ImageQuality.fetchValue(tx:)),
            updateHandler: updateHandler,
        )
    }

    init(
        imageQuality: ImageQuality,
        updateHandler: @escaping (_ imageQuality: ImageQuality) -> Void,
    ) {
        self.imageQuality = imageQuality
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

    func qualityItem(_ imageQuality: ImageQuality) -> OWSTableItem {
        return OWSTableItem(
            text: imageQuality.localizedString,
            actionBlock: { [weak self] in
                self?.changeImageQuality(imageQuality)
            },
            accessoryType: self.imageQuality == imageQuality ? .checkmark : .none
        )
    }

    func changeImageQuality(_ imageQuality: ImageQuality) {
        updateHandler(imageQuality)
        navigationController?.popViewController(animated: true)
    }
}
