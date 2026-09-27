//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Houses miscellaneous internal-only settings and actions.
class InternalMiscViewController: OWSTableViewController2 {

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Misc."

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

        let releaseNotesSection = OWSTableSection(title: "Release Notes")
        releaseNotesSection.add(
            .actionItem(
                withText: "Sync Remote Release Notes",
                actionBlock: {
                    let remoteReleaseNotesFetchingManager = RemoteReleaseNotesFetchingManager(
                        db: DependenciesBridge.shared.db,
                        attachmentContentValidator: DependenciesBridge.shared.attachmentContentValidator,
                        attachmentManager: DependenciesBridge.shared.attachmentManager,
                        blockingManager: SSKEnvironment.shared.blockingManagerRef,
                        tsAccountManager: DependenciesBridge.shared.tsAccountManager,
                        notificationPresenter: SSKEnvironment.shared.notificationPresenterRef,
                        threadStore: DependenciesBridge.shared.threadStore,
                        interactionStore: DependenciesBridge.shared.interactionStore,
                        appVersion: AppVersionImpl.shared,
                        dateProvider: { Date() },
                        remoteReleaseNotesService: DependenciesBridge.shared.remoteReleaseNotesService,
                        releaseNoteStore: ReleaseNoteStore(),
                    )
                    Task {
                        do {
                            try await remoteReleaseNotesFetchingManager.syncRemoteReleaseNotes()
                        } catch {
                            Logger.error("Unable to fetch remote release notes: \(error)")
                        }
                    }
                },
            ),
        )
        contents.add(releaseNotesSection)

        if ScreenshotBlockingManager.isAvailable {
            let db = DependenciesBridge.shared.db
            let screenshotBlockingManager = AppEnvironment.shared.screenshotBlockingManager!

            let screenshotsSection = OWSTableSection(title: "Screenshots")
            screenshotsSection.add(.switch(
                withText: "Block Screenshots",
                subtitle: "Prevent screenshots and screen recordings from capturing Signal",
                isOn: { db.read { screenshotBlockingManager.isEnabled(tx: $0) } },
                actionBlock: { uiSwitch in
                    db.write { screenshotBlockingManager.setIsEnabled(uiSwitch.isOn, tx: $0) }
                },
            ))
            contents.add(screenshotsSection)
        }

        self.contents = contents
    }
}
