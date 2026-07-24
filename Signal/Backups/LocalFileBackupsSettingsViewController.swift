//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import UIKit

class LocalFileBackupsSettingsViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = OWSLocalizedString(
            "SETTINGS_LOCAL_FILE_BACKUPS",
            comment: "Title for the 'on-device backups' settings page.",
        )

    }
}
