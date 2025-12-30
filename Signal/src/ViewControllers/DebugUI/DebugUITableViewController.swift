//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUITableViewController: OWSTableViewController2 {

    // MARK: Public

    static func presentDebugUI(
        fromViewController: UIViewController,
        thread: TSThread?,
    ) {
        let viewController = DebugUITableViewController()

        let subsectionItems: [OWSTableItem] = [
            itemForSubsection(DebugUIMisc(), viewController: viewController, thread: thread),
            itemForSubsection(DebugUIBackups(), viewController: viewController, thread: thread),
            itemForSubsection(DebugUIPrompts(), viewController: viewController, thread: thread),
            itemForSubsection(DebugUISessionState(), viewController: viewController, thread: thread),
            itemForSubsection(DebugUIDiskUsage(), viewController: viewController, thread: thread),
        ]
        viewController.setContents(OWSTableContents(
            title: "Debug UI",
            sections: [OWSTableSection(items: subsectionItems)],
        ))
        viewController.present(fromViewController: fromViewController)
    }

    // MARK: -

    private func pushPageWithSection(_ section: OWSTableSection, title: String) {
        let viewController = DebugUITableViewController()
        viewController.setContents(
            OWSTableContents(title: title, sections: [section]),
        )
        navigationController?.pushViewController(viewController, animated: true)
    }

    private static func itemForSubsection(
        _ page: DebugUIPage,
        viewController: DebugUITableViewController,
        thread: TSThread? = nil,
    ) -> OWSTableItem {
        return OWSTableItem.disclosureItem(
            withText: page.name,
            actionBlock: { [weak viewController] in
                guard let viewController, let section = page.section(thread: thread) else { return }
                section.headerTitle = nil // Updated the style. Too lazy to go through and change all of these to not set their own titles
                viewController.pushPageWithSection(section, title: page.name)
            },
        )
    }
}

#endif
