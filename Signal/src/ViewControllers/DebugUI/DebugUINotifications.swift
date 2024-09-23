//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUINotifications: DebugUIPage {

    private let databaseStorage: SDSDatabaseStorage
    private let notificationPresenterImpl: NotificationPresenterImpl

    init(databaseStorage: SDSDatabaseStorage, notificationPresenterImpl: NotificationPresenterImpl) {
        self.databaseStorage = databaseStorage
        self.notificationPresenterImpl = notificationPresenterImpl
    }

    let name = "Notifications"

    func section(thread: TSThread?) -> OWSTableSection? {
        guard let thread = thread else {
            owsFailDebug("Notifications must specify thread.")
            return nil
        }

        var sectionItems: [OWSTableItem] = []

        if let contactThread = thread as? TSContactThread {
            sectionItems += [
                OWSTableItem(title: "All Notifications in Sequence") { [weak self] in
                    Task { await self?.notifyForEverythingInSequence(contactThread: contactThread) }
                },
                OWSTableItem(title: "Call Rejected: New Safety Number") { [weak self] in
                    Task { await self?.notifyForMissedCallBecauseOfNewIdentity(thread: contactThread) }
                },
                OWSTableItem(title: "Call Rejected: No Longer Verified") { [weak self] in
                    Task { await self?.notifyForMissedCallBecauseOfNoLongerVerifiedIdentity(thread: contactThread) }
                }
            ]
        }

        sectionItems += [
            OWSTableItem(title: "Last Incoming Message") { [weak self] in
                Task { await self?.notifyForIncomingMessage(thread: thread) }
            },
        ]

        return OWSTableSection(title: "Notifications have delay: \(kNotificationDelay)s", items: sectionItems)
    }

    // MARK: Helpers

    // After enqueuing the notification you may want to background the app or lock the screen before it triggers, so
    // we give a little delay.
    private let kNotificationDelay: TimeInterval = 5

    @MainActor
    private func delayedNotificationDispatch(block: @escaping () async -> Void) async {
        Logger.info("⚠️ will present notification after \(kNotificationDelay) second delay")

        // Notifications won't sound if the app is suspended.
        let taskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        do {
            try await Task.sleep(nanoseconds: UInt64(kNotificationDelay * TimeInterval(NSEC_PER_SEC)))
        } catch {
            return
        }
        await block()
        do {
            try await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
        } catch {
            return
        }
        // We don't want to endBackgroundTask until *after* the notifications manager is done,
        // but it dispatches async without a completion handler, so we just wait a while extra.
        // This is fragile, but it's only for debug UI.
        UIApplication.shared.endBackgroundTask(taskIdentifier)
    }

    private func delayedNotificationDispatchWithFakeCallNotificationInfo(thread: TSContactThread, callBlock: @escaping (NotificationPresenterImpl.CallNotificationInfo) -> Void) async {
        let notificationInfo = NotificationPresenterImpl.CallNotificationInfo(
            groupingId: UUID(),
            thread: thread,
            caller: thread.contactAddress.aci!
        )

        return await delayedNotificationDispatch {
            callBlock(notificationInfo)
        }
    }

    // MARK: Notification Methods

    @MainActor
    private func notifyForEverythingInSequence(contactThread: TSContactThread) async {
        let taskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        await self.notifyForMissedCallBecauseOfNewIdentity(thread: contactThread)
        await self.notifyForMissedCallBecauseOfNoLongerVerifiedIdentity(thread: contactThread)
        await self.notifyForIncomingMessage(thread: contactThread)
        UIApplication.shared.endBackgroundTask(taskIdentifier)
    }

    private func notifyForMissedCallBecauseOfNewIdentity(thread: TSContactThread) async {
        return await delayedNotificationDispatchWithFakeCallNotificationInfo(thread: thread) { notificationInfo in
            self.databaseStorage.read { tx in
                self.notificationPresenterImpl.presentMissedCallBecauseOfNewIdentity(notificationInfo: notificationInfo, tx: tx)
            }
        }
    }

    private func notifyForMissedCallBecauseOfNoLongerVerifiedIdentity(thread: TSContactThread) async {
        return await delayedNotificationDispatchWithFakeCallNotificationInfo(thread: thread) { notificationInfo in
            self.databaseStorage.read { tx in
                self.notificationPresenterImpl.presentMissedCallBecauseOfNoLongerVerifiedIdentity(notificationInfo: notificationInfo, tx: tx)
            }
        }
    }

    private func notifyForIncomingMessage(thread: TSThread) async {
        return await delayedNotificationDispatch {
            await self.databaseStorage.awaitableWrite { transaction in
                let factory = IncomingMessageFactory()
                factory.threadCreator = { _ in return thread }
                let incomingMessage = factory.create(transaction: transaction)

                self.notificationPresenterImpl.notifyUser(
                    forIncomingMessage: incomingMessage,
                    thread: thread,
                    transaction: transaction
                )
            }
        }
    }
}

#endif
