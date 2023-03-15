//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MobileCoin
import SignalMessaging
import SignalServiceKit

@objc
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
            contents.addSection(section)
        }

        do {
            let section = OWSTableSection()
            section.footerTitle = LocalizationNotNeeded("This will reset all of these flags to their default values.")
            section.add(OWSTableItem.actionItem(withText: LocalizationNotNeeded("Reset all testable flags.")) { [weak self] in
                NotificationCenter.default.post(name: TestableFlag.ResetAllTestableFlagsNotification, object: nil)
                self?.updateTableContents()
            })
            contents.addSection(section)
        }

        func buildSwitchItem(title: String, testableFlag: TestableFlag) -> OWSTableItem {
            OWSTableItem.switch(withText: title,
                                isOn: { testableFlag.get() },
                                target: testableFlag,
                                selector: testableFlag.switchSelector)
        }

        var testableFlags = FeatureFlags.allTestableFlags() + DebugFlags.allTestableFlags()
        testableFlags.sort { (lhs, rhs) -> Bool in
            lhs.title < rhs.title
        }

        for testableFlag in testableFlags {
            let section = OWSTableSection()
            section.footerTitle = testableFlag.details
            section.add(buildSwitchItem(title: testableFlag.title, testableFlag: testableFlag))
            contents.addSection(section)
        }

        // MARK: - Other

        do {
            if !TSConstants.isUsingProductionService {
                let subscriberIDSection = OWSTableSection()
                subscriberIDSection.footerTitle = LocalizationNotNeeded("Resets subscriberID, which clears current subscription state. Do not do this in prod environment")
                subscriberIDSection.add(OWSTableItem.actionItem(withText: LocalizationNotNeeded("Clear subscriberID State")) {
                    SDSDatabaseStorage.shared.write { transaction in
                        SubscriptionManagerImpl.setSubscriberID(nil, transaction: transaction)
                        SubscriptionManagerImpl.setSubscriberCurrencyCode(nil, transaction: transaction)
                    }
                })
                contents.addSection(subscriberIDSection)
            }
        }

        self.contents = contents
    }
}
