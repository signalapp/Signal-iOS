//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI

// TODO[ADE] Localize the strings in this file

class RequestAccountDataViewController: OWSTableViewController2 {
    public override init() {
        owsAssert(FeatureFlags.canRequestAccountData)

        super.init()
    }

    // MARK: - Callbacks

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = "Request Account Data"

        updateTableContents()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        // TODO[ADE] Handle theme changes
    }

    // MARK: - Rendering

    private func updateTableContents() {
        self.contents = OWSTableContents(sections: getTableSections())
    }

    private func getTableSections() -> [OWSTableSection] {
        var result = [OWSTableSection]()

        // TODO[ADE] Add sections

        return result
    }
}
