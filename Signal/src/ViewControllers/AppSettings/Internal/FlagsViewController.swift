//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
class FlagsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Flags"

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        contents.addSection(buildSection(title: "Remote Config", flagMap: RemoteConfig.allFlags()))
        contents.addSection(buildSection(title: "Feature Flags", flagMap: FeatureFlags.allFlags()))
        contents.addSection(buildSection(title: "Debug Flags", flagMap: DebugFlags.allFlags()))

        self.contents = contents
    }

    func buildSection(title: String, flagMap: [String: Any]) -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = title

        for key in flagMap.keys.sorted() {
            if let value = flagMap[key] {
                section.add(OWSTableItem.label(withText: key, accessoryText: String(describing: value)))
            } else {
                section.add(OWSTableItem.label(withText: key, accessoryText: "nil"))
            }
        }

        return section
    }
}
