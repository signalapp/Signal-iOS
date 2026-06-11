//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Houses one-off internal actions that are normally performed automatically
/// (e.g. on a schedule), so they can be triggered manually for testing.
class InternalMiscActionsViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Misc. Actions"

        updateTableContents()
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let keyTransparencySection = OWSTableSection(title: "Key Transparency")
        keyTransparencySection.add(.actionItem(
            withText: "Perform self-check",
            actionBlock: { [weak self] in
                guard let self else { return }
                let keyTransparencyManager = DependenciesBridge.shared.keyTransparencyManager
                Task { @MainActor in
                    do {
                        try await keyTransparencyManager.performSelfCheckOnDemand()
                        self.presentToast(text: "Self-check succeeded!")
                    } catch {
                        self.presentToast(text: "Self-check failed!")
                    }
                }
            },
        ))
        contents.add(keyTransparencySection)

        self.contents = contents
    }
}
