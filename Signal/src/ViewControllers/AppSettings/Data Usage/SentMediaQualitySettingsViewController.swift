//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class SentMediaQualitySettingsViewController: OWSTableViewController2 {
    private let updateHandler: (_ isHighQuality: Bool) -> Void
    init(updateHandler: @escaping (_ isHighQuality: Bool) -> Void) {
        self.updateHandler = updateHandler
        super.init()
    }

    private var remoteDefaultLevel: ImageQualityLevel!
    private var currentQualityLevel: ImageQualityLevel!

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_DATA_SENT_MEDIA_QUALITY_ITEM_TITLE",
            comment: "Item title for the sent media quality setting"
        )

        databaseStorage.read { tx in
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            let localPhoneNumber = tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.phoneNumber
            remoteDefaultLevel = ImageQualityLevel.remoteDefault(localPhoneNumber: localPhoneNumber)
            currentQualityLevel = ImageQualityLevel.resolvedQuality(tx: tx)
        }

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

        section.add(qualityItem(remoteDefaultLevel))
        section.add(qualityItem(.high))

        contents.add(section)
    }

    func qualityItem(_ level: ImageQualityLevel) -> OWSTableItem {
        return OWSTableItem(
            text: level.localizedString,
            actionBlock: { [weak self] in
                self?.changeLevel(isHighQuality: level == .high)
            },
            accessoryType: currentQualityLevel == level ? .checkmark : .none
        )
    }

    func changeLevel(isHighQuality: Bool) {
        updateHandler(isHighQuality)
        navigationController?.popViewController(animated: true)
    }
}
