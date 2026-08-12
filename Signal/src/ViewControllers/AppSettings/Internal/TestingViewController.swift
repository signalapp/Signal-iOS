//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MobileCoin
import SignalServiceKit
import SignalUI

class TestingViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = LocalizationNotNeeded("Testing")

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        do {
            let section = OWSTableSection()
            section.footerTitle = LocalizationNotNeeded("These values are temporary and will reset on next launch of the app.")
            contents.add(section)
        }

        do {
            let section = OWSTableSection()
            section.footerTitle = LocalizationNotNeeded("This will reset all of these flags to their default values.")
            section.add(OWSTableItem.actionItem(withText: LocalizationNotNeeded("Reset all testable flags.")) { [weak self] in
                NotificationCenter.default.post(name: .resetAllTestableFlags, object: nil)
                self?.updateTableContents()
            })
            contents.add(section)
        }

        let callingSection = OWSTableSection(title: "Calling")
        for callingFlag in DebugFlags.callingTestableFlags {
            addTestableFlag(
                callingFlag,
                toSection: callingSection,
            )
        }
        contents.add(callingSection)

        let messagingSection = OWSTableSection(title: "Messaging")
        for messagingFlag in DebugFlags.messagingTestableFlags {
            addTestableFlag(
                messagingFlag,
                toSection: messagingSection,
            )
        }
        contents.add(messagingSection)

        self.contents = contents
    }

    private func addTestableFlag(
        _ testableFlag: AnyTestableFlag,
        toSection section: OWSTableSection,
    ) {
        switch testableFlag {
        case let boolFlag as TestableFlag<Bool>:
            addSwitchItem(
                toSection: section,
                boolFlag: boolFlag,
            )
        case let intFlag as TestableFlag<Int>:
            addAlertControllerItem(
                toSection: section,
                titleText: intFlag.title,
                subtitle: intFlag.details,
                accessoryText: "\(intFlag.get())",
                keyboardType: .numberPad,
                onAlertControllerSubmission: { [weak intFlag] text in
                    guard
                        let intFlag,
                        let intValue = Int(text)
                    else { return }

                    intFlag.set(intValue)
                },
            )
        default:
            owsFail("Unexpected TestableFlag! \(testableFlag)")
        }
    }

    private func addSwitchItem(
        toSection section: OWSTableSection,
        boolFlag: TestableFlag<Bool>,
    ) {
        section.add(OWSTableItem.switch(
            withText: boolFlag.title,
            subtitle: boolFlag.details,
            isOn: { boolFlag.get() },
            actionBlock: { uiSwitch in
                boolFlag.set(uiSwitch.isOn)
            },
        ))
    }

    private func addAlertControllerItem(
        toSection section: OWSTableSection,
        titleText: String,
        subtitle: String,
        accessoryText: String,
        keyboardType: UIKeyboardType,
        onAlertControllerSubmission: @escaping (String) -> Void,
    ) {
        section.add(OWSTableItem.disclosureItem(
            withText: titleText,
            subtitle: subtitle,
            accessoryText: accessoryText,
            actionBlock: { [weak self] in
                guard let self else { return }

                let alert = UIAlertController(
                    title: "Set flag \"\(titleText)\":",
                    message: nil,
                    preferredStyle: .alert,
                )
                alert.addTextField { textField in
                    textField.placeholder = "Value"
                    textField.keyboardType = keyboardType
                }
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(
                    title: "Save",
                    style: .default,
                    handler: { [weak self, weak alert] _ in
                        guard
                            let self,
                            let alert,
                            let text = alert.textFields?.first?.text
                        else { return }

                        onAlertControllerSubmission(text)
                        self.updateTableContents()
                    },
                ))

                self.present(alert, animated: true)
            },
        ))
    }
}
