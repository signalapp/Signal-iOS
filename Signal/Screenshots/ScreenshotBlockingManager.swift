//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// Responsible for app-wide Screenshot Blocking.
///
/// Individual views that must never be captured block screenshots
/// themselves.
class ScreenshotBlockingManager {

    /// Whether blocking screenshots of the app's windows is available at all.
    static var isAvailable: Bool {
        if #available(iOS 27, *) {
            return true
        }
        return false
    }

    private let db: any DB
    private let store: Store
    private let windowManager: WindowManager

    private var isBlockingScreenshots: Bool = ScreenshotBlockingManager.isAvailable

    init(
        db: any DB,
        windowManager: WindowManager,
    ) {
        self.db = db
        self.store = Store()
        self.windowManager = windowManager
    }

    /// Applies the stored preference to the app's windows, and begins
    /// watching for screenshots.
    ///
    /// The windows can exist before the database is readable, so until this
    /// runs they block screenshots, matching the default.
    func start() {
        AssertIsOnMainThread()

        applyToWindows(isEnabled: db.read { isEnabled(tx: $0) })

        NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didTakeScreenshot() }
        }
    }

    /// Whether the user wants the app's windows blocked from screenshots.
    ///
    /// Note that actually blocking screenshots requires ``isAvailable`` as
    /// well as this preference.
    func isEnabled(tx: DBReadTransaction) -> Bool {
        return store.isEnabled(tx: tx)
    }

    func setIsEnabled(_ isEnabled: Bool, tx: DBWriteTransaction) {
        store.setIsEnabled(isEnabled, tx: tx)

        tx.addSyncCompletion { [self] in
            applyToWindows(isEnabled: isEnabled)
        }
    }

    private func applyToWindows(isEnabled: Bool) {
        isBlockingScreenshots = Self.isAvailable && isEnabled
        windowManager.setBlocksScreenshots(isBlockingScreenshots)
    }

    @MainActor
    private func didTakeScreenshot() {
        guard isBlockingScreenshots else { return }

        guard let frontmostViewController = CurrentAppContext().frontmostViewController() else {
            owsFailDebug("Missing frontmostViewController!")
            return
        }

        // Screenshotting the sheet shouldn't stack another one on top of it.
        guard !(frontmostViewController is ScreenshotBlockedSheet) else { return }

        frontmostViewController.present(ScreenshotBlockedSheet(), animated: true)
    }

    // MARK: -

    private struct Store {
        private let kvStore = NewKeyValueStore(collection: "ScreenshotBlocking")

        private let isEnabledKey = "isEnabled"

        func isEnabled(tx: DBReadTransaction) -> Bool {
            return kvStore.fetchValue(Bool.self, forKey: isEnabledKey, tx: tx) ?? false
        }

        func setIsEnabled(_ isEnabled: Bool, tx: DBWriteTransaction) {
            kvStore.writeValue(isEnabled, forKey: isEnabledKey, tx: tx)
        }
    }
}

// MARK: -

private class ScreenshotBlockedSheet: HeroSheetViewController {
    init() {
        super.init(
            hero: .circleIcon(
                icon: .lock,
                iconSize: 40,
                tintColor: .Signal.label,
                backgroundColor: .Signal.secondaryFill,
            ),
            title: "Screenshot Blocked",
            body: "Screenshots are blocked for Signal. You can control this in Settings > Internal > Misc.",
            primaryButton: HeroSheetViewController.Button(
                title: CommonStrings.okButton,
                action: .dismiss,
            ),
        )
    }
}
