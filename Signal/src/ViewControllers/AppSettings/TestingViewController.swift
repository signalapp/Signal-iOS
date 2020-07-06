//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class TestingViewController: OWSTableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Testing"

        self.useThemeBackgroundColors = true

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        do {
            let section = OWSTableSection()
            section.footerTitle = "These values are temporary and will reset on next launch of the app."
            contents.addSection(section)
        }

        do {
            let section = OWSTableSection()
            section.footerTitle = "Members added to a v2 group will always be invited instead of added."
            section.add(OWSTableItem.switch(withText: "Groups v2: Always Invite",
                                            isOn: { DebugFlags.groupsV2forceInvites },
                                            target: self,
                                            selector: #selector(didToggleGroupsV2forceInvites(_:))))
            contents.addSection(section)
        }

        do {
            let section = OWSTableSection()
            section.footerTitle = "The app will not send 'group update' messages for v2 groups. " +
                "Other group members will only learn of group changes from normal group messages."
            section.add(OWSTableItem.switch(withText: "Groups v2: Don't Send Updates",
                                            isOn: { DebugFlags.groupsV2dontSendUpdates },
                                            target: self,
                                            selector: #selector(didToggleGroupsV2dontSendUpdates(_:))))
            contents.addSection(section)
        }

        self.contents = contents
    }

    @objc
    func didToggleGroupsV2forceInvites(_ sender: UISwitch) {
        DebugFlags.groupsV2forceInvites = sender.isOn
    }

    @objc
    func didToggleGroupsV2dontSendUpdates(_ sender: UISwitch) {
        DebugFlags.groupsV2dontSendUpdates = sender.isOn
    }
}
