//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

final class DebugUIPrompts: DebugUIPage {
    let name = "Prompts"

    func section(thread: TSThread?) -> OWSTableSection? {
        let db = DependenciesBridge.shared.db
        let inactiveLinkedDeviceFinder = DependenciesBridge.shared.inactiveLinkedDeviceFinder
        let usernameEducationManager = DependenciesBridge.shared.usernameEducationManager

        var items = [OWSTableItem]()

        items += [

            OWSTableItem(title: "Reenable disabled inactive linked device reminder megaphones", actionBlock: {
                db.write { tx in
                    inactiveLinkedDeviceFinder.reenablePermanentlyDisabledFinders(tx: tx)
                }
            }),

            OWSTableItem(title: "Enable username education prompt", actionBlock: {
                db.write { tx in
                    usernameEducationManager.setShouldShowUsernameEducation(true, tx: tx)
                }
            }),
            OWSTableItem(title: "Enable username link tooltip", actionBlock: {
                db.write { tx in
                    usernameEducationManager.setShouldShowUsernameLinkTooltip(true, tx: tx)
                }
            }),

            OWSTableItem(title: "Mark flip cam button tooltip as unread", actionBlock: {
                let flipCamTooltipManager = FlipCameraTooltipManager(db: db)
                flipCamTooltipManager.markTooltipAsUnread()
            }),

            OWSTableItem(title: "Enable DeleteForMeSyncMessage info sheet", actionBlock: {
                db.write { tx in
                    DeleteForMeInfoSheetCoordinator.fromGlobals().forceEnableInfoSheet(tx: tx)
                }
            }),
        ]
        return OWSTableSection(title: name, items: items)
    }
}

#endif
