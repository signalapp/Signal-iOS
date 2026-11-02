//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// User-configurable preferences for Screenshot Blocking.
enum ScreenshotBlockingPreference: Equatable, CaseIterable {
    /// Screenshot blocking is enabled.
    case blockScreenshots
    /// Screenshot blocking is disabled, permanently.
    case doNotBlockScreenshots
    /// Screenshot blocking is disabled, temporarily.
    /// - Note
    /// We present this case as "disabled for ten minutes"; if that constant
    /// changes, user-facing strings will also need changing.
    case doNotBlockScreenshotsForTenMinutes
}

/// Mirrors ``ScreenshotBlockingPreference``, with associated values.
private enum _ScreenshotBlockingPreference {
    case blockScreenshots
    case doNotBlockScreenshots
    case doNotBlockScreenshotsTemporarily(remainingInterval: TimeInterval)
}

// MARK: -

/// Responsible for app-wide Screenshot Blocking.
///
/// Individual views that must never be captured block screenshots
/// themselves.
@MainActor
class ScreenshotBlockingManager {

    /// Whether blocking screenshots of the app's windows is available at all.
    nonisolated static var isAvailable: Bool {
        guard BuildFlags.screenshotBlocking else {
            return false
        }

        if #available(iOS 27, *) {
            return true
        }
        return false
    }

    private enum StoreKeys {
        static let isScreenshotBlockingEnabled = "isScreenshotBlockingEnabled"
        static let doNotBlockScreenshotsTemporarilyDate = "doNotBlockScreenshotsTemporarilyDate"
    }

    private let dateProvider: DateProvider
    private let db: any DB
    private let disabledTemporarilyInterval: TimeInterval
    private let kvStore: NewKeyValueStore
    private let windowManager: WindowManager

    private var isBlockingScreenshots: Bool = ScreenshotBlockingManager.isAvailable
    private var notificationObservers: [NotificationCenter.Observer] = []

    init(
        dateProvider: @escaping DateProvider,
        db: any DB,
        disabledTemporarilyInterval: TimeInterval = 10 * .minute,
        windowManager: WindowManager,
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.disabledTemporarilyInterval = disabledTemporarilyInterval
        self.kvStore = NewKeyValueStore(collection: "ScreenshotBlockingManager")
        self.windowManager = windowManager
    }

    // MARK: -

    /// Applies the stored preference to the app's windows, and begins
    /// watching for screenshots.
    ///
    /// The windows can exist before the database is readable, so until this
    /// runs they block screenshots, matching the default.
    func start() {
        owsPrecondition(
            notificationObservers.isEmpty,
            "Calling start() twice!",
        )

        reconcileCurrentPreference()

        notificationObservers = [
            NotificationCenter.default.addObserver(
                name: .OWSApplicationDidBecomeActive,
                block: { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.reconcileCurrentPreference()
                    }
                },
            ),
            NotificationCenter.default.addObserver(
                name: UIApplication.userDidTakeScreenshotNotification,
                block: { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.didTakeScreenshot()
                    }
                },
            ),
        ]
    }

    // MARK: -

    /// Gets the user's current Screenshot Blocking preference. Defaults to `.blockScreenshots`.
    func getPreference(tx: DBReadTransaction) -> ScreenshotBlockingPreference {
        return switch _getPreference(tx: tx) {
        case .blockScreenshots: .blockScreenshots
        case .doNotBlockScreenshots: .doNotBlockScreenshots
        case .doNotBlockScreenshotsTemporarily: .doNotBlockScreenshotsForTenMinutes
        }
    }

    private func _getPreference(tx: DBReadTransaction) -> _ScreenshotBlockingPreference {
        if
            let doNotBlockScreenshotsTemporarilyDate = kvStore.fetchValue(
                Date.self,
                forKey: StoreKeys.doNotBlockScreenshotsTemporarilyDate,
                tx: tx,
            )
        {
            let remainingInterval = doNotBlockScreenshotsTemporarilyDate
                .addingTimeInterval(disabledTemporarilyInterval)
                .timeIntervalSince(dateProvider())

            if remainingInterval > 0 {
                return .doNotBlockScreenshotsTemporarily(
                    remainingInterval: remainingInterval,
                )
            }
        }

        let isScreenshotBlockingEnabled = kvStore.fetchValue(
            Bool.self,
            forKey: StoreKeys.isScreenshotBlockingEnabled,
            tx: tx,
        ) ?? true

        if isScreenshotBlockingEnabled {
            return .blockScreenshots
        } else {
            return .doNotBlockScreenshots
        }
    }

    /// Sets the user's current Screenshot Blocking preference, potentially
    /// after confirmations.
    ///
    /// - Important
    /// Actually blocking screenshots requires ``isAvailable`` in addition to an
    /// `.blockScreenshots` preference.
    func setPreferenceWithConfirmation(
        _ preference: ScreenshotBlockingPreference,
        fromViewController: UIViewController,
    ) async {
        switch preference {
        case .blockScreenshots, .doNotBlockScreenshotsForTenMinutes:
            db.write { tx in
                setPreference(preference, tx: tx)
            }
            return
        case .doNotBlockScreenshots:
            break
        }

        let deferredContinuation = DeferredContinuation<Void>()

        let confirmationActionSheet = makeDisableScreenshotBlockingSheet(
            onDisableTapped: { [self] in
                db.write { tx in
                    self.setPreference(.doNotBlockScreenshots, tx: tx)
                }
            },
        )
        confirmationActionSheet.onDismiss = {
            deferredContinuation.resume(with: .success(()))
        }

        fromViewController.presentActionSheet(confirmationActionSheet)
        try? await deferredContinuation.wait()
    }

    private func setPreference(_ preference: ScreenshotBlockingPreference, tx: DBWriteTransaction) {
        let isScreenshotBlockingEnabled: Bool
        let doNotBlockScreenshotsTemporarilyDate: Date?
        switch preference {
        case .blockScreenshots:
            isScreenshotBlockingEnabled = true
            doNotBlockScreenshotsTemporarilyDate = nil
        case .doNotBlockScreenshots:
            isScreenshotBlockingEnabled = false
            doNotBlockScreenshotsTemporarilyDate = nil
        case .doNotBlockScreenshotsForTenMinutes:
            isScreenshotBlockingEnabled = true
            doNotBlockScreenshotsTemporarilyDate = dateProvider()
        }

        kvStore.writeValue(
            isScreenshotBlockingEnabled,
            forKey: StoreKeys.isScreenshotBlockingEnabled,
            tx: tx,
        )
        kvStore.writeValue(
            doNotBlockScreenshotsTemporarilyDate,
            forKey: StoreKeys.doNotBlockScreenshotsTemporarilyDate,
            tx: tx,
        )

        tx.addSyncCompletion { [self] in
            reconcileCurrentPreference()
        }
    }

    // MARK: -

    private let disabledTemporarilyWaitingTask: AtomicValue<Task<Void, Never>?> = AtomicValue(nil, lock: .init())

    private func reconcileCurrentPreference() {
        let _preference: _ScreenshotBlockingPreference = db.read { tx in
            return _getPreference(tx: tx)
        }

        defer {
            applyToWindows(_preference: _preference)
        }

        var intervalUntilNoLongerDisabled: TimeInterval
        switch _preference {
        case .blockScreenshots, .doNotBlockScreenshots:
            disabledTemporarilyWaitingTask.get()?.cancel()
            return
        case .doNotBlockScreenshotsTemporarily(let remainingInterval):
            intervalUntilNoLongerDisabled = remainingInterval
        }

        // Add a little fudge to hedge against the task wakeup racing with date
        // comparisons.
        intervalUntilNoLongerDisabled += .second

        disabledTemporarilyWaitingTask.update {
            $0?.cancel()
            $0 = Task {
                do {
                    try await Task.sleep(nanoseconds: intervalUntilNoLongerDisabled.clampedNanoseconds)
                } catch {
                    return
                }

                // It should now be past the disabledTemporarilyUntil; call
                // recursively so we set the preference to enabled.
                reconcileCurrentPreference()
            }
        }
    }

    private func applyToWindows(_preference: _ScreenshotBlockingPreference) {
        let shouldBlockScreenshots = switch _preference {
        case .blockScreenshots: true
        case .doNotBlockScreenshots: false
        case .doNotBlockScreenshotsTemporarily: false
        }

        isBlockingScreenshots = Self.isAvailable && shouldBlockScreenshots
        windowManager.setBlocksScreenshots(isBlockingScreenshots)
    }

    // MARK: -

    private func didTakeScreenshot() {
        guard isBlockingScreenshots else { return }

        guard let frontmostViewController = CurrentAppContext().frontmostViewController() else {
            owsFailDebug("Missing frontmostViewController!")
            return
        }

        showScreenshotBlockedToast(fromViewController: frontmostViewController)
    }

    private func showScreenshotBlockedToast(fromViewController: UIViewController) {
        fromViewController.presentToast(
            text: OWSLocalizedString(
                "SCREENSHOT_BLOCKING_BLOCKED_TOAST_TEXT",
                comment: "Text for a toast shown when a screenshot is blocked.",
            ),
            image: .lock,
            button: ToastController.Button(
                title: OWSLocalizedString(
                    "SCREENSHOT_BLOCKING_BLOCKED_TOAST_OPTIONS_BUTTON_TITLE",
                    comment: "Title for a button in a toast shown when a screenshot is blocked.",
                ),
                onPrimaryAction: { [self] in
                    showDisableFromToastSheet(
                        fromViewController: fromViewController,
                    )
                },
            ),
            // Extra long duration, since it'll be hidden by the blank screenshot.
            duration: .seconds(8),
        )
    }

    private func showDisableFromToastSheet(fromViewController: UIViewController) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SCREENSHOT_BLOCKING_OPTIONS_SHEET_TITLE",
                comment: "Title for a sheet shown from a toast shown when a screenshot is blocked.",
            ),
            message: OWSLocalizedString(
                "SCREENSHOT_BLOCKING_OPTIONS_SHEET_MESSAGE",
                comment: "Message for a sheet shown from a toast shown when a screenshot is blocked.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SCREENSHOT_BLOCKING_OPTIONS_SHEET_DISABLE_TEN_MINUTES_BUTTON_TITLE",
                comment: "Title for a button that temporarily disables screenshot blocking, in a sheet shown from a toast shown when a screenshot is blocked.",
            ),
            handler: { [self] _ in
                db.write { tx in
                    self.setPreference(.doNotBlockScreenshotsForTenMinutes, tx: tx)
                }

                fromViewController.presentToast(
                    text: OWSLocalizedString(
                        "SCREENSHOT_BLOCKING_DISABLED_TEN_MINUTES_TOAST_TEXT",
                        comment: "Text for a toast shown after disabling screenshot blocking for ten minutes.",
                    ),
                    image: .unlockedLock,
                )
            },
        ))
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SCREENSHOT_BLOCKING_OPTIONS_SHEET_DISABLE_BUTTON_TITLE",
                comment: "Title for a button that disables screenshot blocking, in a sheet shown from a toast shown when a screenshot is blocked.",
            ),
            style: .destructive,
            handler: { [self] _ in
                let doubleConfirmActionSheet = makeDisableScreenshotBlockingSheet(
                    onDisableTapped: { [self] in
                        db.write { tx in
                            self.setPreference(.doNotBlockScreenshots, tx: tx)
                        }

                        fromViewController.presentToast(
                            text: OWSLocalizedString(
                                "SCREENSHOT_BLOCKING_DISABLED_TOAST_TEXT",
                                comment: "Text for a toast shown after disabling screenshot blocking.",
                            ),
                            image: .unlockedLock,
                        )
                    },
                )

                fromViewController.presentActionSheet(doubleConfirmActionSheet)
            },
        ))
        actionSheet.addAction(.cancel)

        fromViewController.presentActionSheet(actionSheet)
    }

    private func makeDisableScreenshotBlockingSheet(
        onDisableTapped: @escaping () -> Void,
    ) -> ActionSheetController {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "SCREENSHOT_BLOCKING_DISABLE_CONFIRM_SHEET_TITLE",
                comment: "Title for a sheet shown to confirm disabling screenshot blocking.",
            ),
            message: OWSLocalizedString(
                "SCREENSHOT_BLOCKING_DISABLE_CONFIRM_SHEET_MESSAGE",
                comment: "Message for a sheet shown to confirm disabling screenshot blocking.",
            ),
        )
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "SCREENSHOT_BLOCKING_DISABLE_CONFIRM_SHEET_ALLOW_BUTTON_TITLE",
                comment: "Title for a button in a sheet shown to confirm disabling screenshot blocking.",
            ),
            style: .destructive,
            handler: { _ in
                onDisableTapped()
            },
        ))
        actionSheet.addAction(.cancel)

        return actionSheet
    }
}
