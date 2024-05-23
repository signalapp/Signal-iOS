//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUINotifications: DebugUIPage, Dependencies {

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
                    self?.notifyForEverythingInSequence(contactThread: contactThread)
                },
                OWSTableItem(title: "Call Rejected: New Safety Number") { [weak self] in
                    self?.notifyForMissedCallBecauseOfNewIdentity(thread: contactThread)
                },
                OWSTableItem(title: "Call Rejected: No Longer Verified") { [weak self] in
                    self?.notifyForMissedCallBecauseOfNoLongerVerifiedIdentity(thread: contactThread)
                }
            ]
        }

        sectionItems += [
            OWSTableItem(title: "Last Incoming Message") { [weak self] in
                self?.notifyForIncomingMessage(thread: thread)
            },
        ]

        return OWSTableSection(title: "Notifications have delay: \(kNotificationDelay)s", items: sectionItems)
    }

    // MARK: Helpers

    // After enqueuing the notification you may want to background the app or lock the screen before it triggers, so
    // we give a little delay.
    let kNotificationDelay: TimeInterval = 5

    func delayedNotificationDispatch(block: @escaping () -> Void) -> Guarantee<Void> {
        Logger.info("⚠️ will present notification after \(kNotificationDelay) second delay")

        // Notifications won't sound if the app is suspended.
        let taskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)

        return Guarantee.after(seconds: kNotificationDelay).done {
            block()
        }.then {
            Guarantee.after(seconds: 2.0)
        }.done {
            // We don't want to endBackgroundTask until *after* the notifications manager is done,
            // but it dispatches async without a completion handler, so we just wait a while extra.
            // This is fragile, but it's only for debug UI.
            UIApplication.shared.endBackgroundTask(taskIdentifier)
        }
    }

    func delayedNotificationDispatchWithFakeCall(thread: TSContactThread, callBlock: @escaping (SignalCall) -> Void) -> Guarantee<Void> {
        let individualCall = IndividualCall.incomingIndividualCall(
            thread: thread,
            sentAtTimestamp: Date.ows_millisecondTimestamp(),
            offerMediaType: .audio
        )

        let call = SignalCall(individualCall: individualCall)

        return delayedNotificationDispatch {
            callBlock(call)
        }
    }

    // MARK: Notification Methods

    @discardableResult
    func notifyForEverythingInSequence(contactThread: TSContactThread) -> Guarantee<Void> {
        let taskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)

        return self.notifyForMissedCallBecauseOfNewIdentity(thread: contactThread).then {
            self.notifyForMissedCallBecauseOfNoLongerVerifiedIdentity(thread: contactThread)
        }.then {
            self.notifyForIncomingMessage(thread: contactThread)
        }.done {
            UIApplication.shared.endBackgroundTask(taskIdentifier)
        }
    }

    @discardableResult
    func notifyForMissedCallBecauseOfNewIdentity(thread: TSContactThread) -> Guarantee<Void> {
        return delayedNotificationDispatchWithFakeCall(thread: thread) { call in
            self.notificationPresenterImpl.presentMissedCallBecauseOfNewIdentity(call: call, caller: thread.contactAddress)
        }
    }

    @discardableResult
    func notifyForMissedCallBecauseOfNoLongerVerifiedIdentity(thread: TSContactThread) -> Guarantee<Void> {
        return delayedNotificationDispatchWithFakeCall(thread: thread) { call in
            self.notificationPresenterImpl.presentMissedCallBecauseOfNoLongerVerifiedIdentity(
                call: call,
                caller: thread.contactAddress
            )
        }
    }

    @discardableResult
    func notifyForIncomingMessage(thread: TSThread) -> Guarantee<Void> {
        return delayedNotificationDispatch {
            self.databaseStorage.write { transaction in
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
