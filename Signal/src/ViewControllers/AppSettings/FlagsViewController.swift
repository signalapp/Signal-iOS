//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class FlagsViewController: OWSTableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Flags"

        self.useThemeBackgroundColors = true

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        contents.addSection(buildSection(title: "Remote Config", flagMap: RemoteConfig.buildFlagMap()))
        contents.addSection(buildSection(title: "Feature Flags", flagMap: FeatureFlags.buildFlagMap()))
        contents.addSection(buildSection(title: "Debug Flags", flagMap: DebugFlags.buildFlagMap()))

        self.contents = contents
    }

    func buildSection(title: String, flagMap: [String: Any]) -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = title

        for key in Array(flagMap.keys).sorted() {
            if let value = flagMap[key] {
                section.add(OWSTableItem.label(withText: key, accessoryText: String(describing: value)))
            } else {
                section.add(OWSTableItem.label(withText: key, accessoryText: "nil"))
            }
        }

        return section
    }
}
