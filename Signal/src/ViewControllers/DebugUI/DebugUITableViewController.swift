//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

#if DEBUG

class DebugUITableViewController: OWSTableViewController {

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Block device from sleeping while in the Debug UI.
        //
        // This is useful if you're using long-running actions in the
        // Debug UI, like "send 1k messages", etc.
        DeviceSleepManager.shared.addBlock(blockObject: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        DeviceSleepManager.shared.removeBlock(blockObject: self)
    }

    // MARK: Public

    static func presentDebugUI(from fromViewController: UIViewController) {
        let viewController = DebugUITableViewController()

        let subsectionItems: [OWSTableItem] = [
            itemForSubsection(DebugUIContacts(), viewController: viewController),
            itemForSubsection(DebugUIDiskUsage(), viewController: viewController),
            itemForSubsection(DebugUISessionState(), viewController: viewController),
            itemForSubsection(DebugUISyncMessages(), viewController: viewController),
            itemForSubsection(DebugUIGroupsV2(), viewController: viewController),
            itemForSubsection(DebugUIPayments(), viewController: viewController),
            itemForSubsection(DebugUIMisc(), viewController: viewController)
        ]
        viewController.contents = OWSTableContents(
            title: "Debug UI",
            sections: [ OWSTableSection(title: "Sections", items: subsectionItems) ]
        )
        viewController.present(fromViewController: fromViewController)
    }

    static func presentDebugUIForThread(_ thread: TSThread, from fromViewController: UIViewController) {
        let viewController = DebugUITableViewController()

        var subsectionItems: [OWSTableItem] = [
            itemForSubsection(DebugUIMessages(), viewController: viewController, thread: thread),
            itemForSubsection(DebugUIContacts(), viewController: viewController, thread: thread),
            itemForSubsection(DebugUIDiskUsage(), viewController: viewController, thread: thread),
            itemForSubsection(DebugUISessionState(), viewController: viewController, thread: thread)
        ]
        if thread is TSContactThread {
            subsectionItems.append(itemForSubsection(DebugUICalling(), viewController: viewController, thread: thread))
        }
        subsectionItems += [
            itemForSubsection(DebugUINotifications(), viewController: viewController, thread: thread),
            itemForSubsection(DebugUIStress(), viewController: viewController, thread: thread),
            itemForSubsection(DebugUISyncMessages(), viewController: viewController, thread: thread),

            OWSTableItem(
                title: "📁 Shared Container", actionBlock: {
                    let baseURL = OWSFileSystem.appSharedDataDirectoryURL()
                    let fileBrowser = DebugUIFileBrowser(fileURL: baseURL)
                    viewController.navigationController?.pushViewController(fileBrowser, animated: true)
                }
            ),

            OWSTableItem(
                title: "📁 App Container", actionBlock: {
                    let libraryPath = OWSFileSystem.appLibraryDirectoryPath()
                    guard let baseURL = NSURL(string: libraryPath)?.deletingLastPathComponent else { return }
                    let fileBrowser = DebugUIFileBrowser(fileURL: baseURL)
                    viewController.navigationController?.pushViewController(fileBrowser, animated: true)
                }
            ),

            OWSTableItem.disclosureItem(
                withText: "Data Store Reports",
                actionBlock: {
                    viewController.navigationController?.pushViewController(DebugUIReportsViewController(), animated: true)
                }
            ),

            itemForSubsection(DebugUIGroupsV2(), viewController: viewController, thread: thread),
            itemForSubsection(DebugUIPayments(), viewController: viewController, thread: thread),
            itemForSubsection(DebugUIMisc(), viewController: viewController, thread: thread)
        ]

        viewController.contents = OWSTableContents(
            title: "Debug: Conversation",
            sections: [OWSTableSection(title: "Sections", items: subsectionItems)]
        )
        viewController.present(fromViewController: fromViewController)
    }

    // MARK: -

    private func pushPageWithSection(_ section: OWSTableSection) {
        let viewController = DebugUITableViewController()
        viewController.contents = OWSTableContents(title: section.headerTitle, sections: [section])
        navigationController?.pushViewController(viewController, animated: true )
    }

    private static func itemForSubsection(
        _ page: DebugUIPage,
        viewController: DebugUITableViewController,
        thread: TSThread? = nil
    ) -> OWSTableItem {
        return OWSTableItem.disclosureItem(
            withText: page.name(),
            actionBlock: { [weak viewController] in
                guard let viewController, let section = page.section(thread: thread) else { return }
                viewController.pushPageWithSection(section)
            }
        )
    }
}

#endif
