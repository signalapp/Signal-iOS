//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging
import PromiseKit

class DebugUINotifications: DebugUIPage {

    // MARK: Dependencies

    var notificationsAdapter: NotificationsAdapter {
        return AppEnvironment.shared.notificationsAdapter
    }
    var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }
    var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    // MARK: Overrides

    override func name() -> String {
        return "Notifications"
    }

    override func section(thread: TSThread?) -> OWSTableSection? {
        guard let thread = thread else {
            owsFailDebug("Notifications must specify thread.")
            return nil
        }

        var sectionItems: [OWSTableItem] = []

        if let contactThread = thread as? TSContactThread {
            sectionItems += [
                OWSTableItem(title: "All Notifications in Sequence") { [weak self] in
                    self?.notifyForEverythingInSequence(contactThread: contactThread).retainUntilComplete()
                },
                OWSTableItem(title: "Incoming Call") { [weak self] in
                    self?.notifyForIncomingCall(thread: contactThread).retainUntilComplete()
                },
                OWSTableItem(title: "Call Missed") { [weak self] in
                    self?.notifyForMissedCall(thread: contactThread).retainUntilComplete()
                },
                OWSTableItem(title: "Call Rejected: New Safety Number") { [weak self] in
                    self?.notifyForMissedCallBecauseOfNewIdentity(thread: contactThread).retainUntilComplete()
                },
                OWSTableItem(title: "Call Rejected: No Longer Verified") { [weak self] in
                    self?.notifyForMissedCallBecauseOfNoLongerVerifiedIdentity(thread: contactThread).retainUntilComplete()
                }
            ]
        }

        sectionItems += [
            OWSTableItem(title: "Last Incoming Message") { [weak self] in
                self?.notifyForIncomingMessage(thread: thread).retainUntilComplete()
            },

            OWSTableItem(title: "Notify For Error Message") { [weak self] in
                self?.notifyForErrorMessage(thread: thread).retainUntilComplete()
            },

            OWSTableItem(title: "Notify For Threadless Error Message") { [weak self] in
                self?.notifyUserForThreadlessErrorMessage().retainUntilComplete()
            }
        ]

        return OWSTableSection(title: "Notifications have delay: \(kNotificationDelay)s", items: sectionItems)
    }

    // MARK: Helpers

    func readWrite(_ block: @escaping (YapDatabaseReadWriteTransaction) -> Void) {
        OWSPrimaryStorage.shared().dbReadWriteConnection.readWrite(block)
    }

    // After enqueing the notification you may want to background the app or lock the screen before it triggers, so
    // we give a little delay.
    let kNotificationDelay: TimeInterval = 5

    func delayedNotificationDispatch(block: @escaping () -> Void) -> Guarantee<Void> {
        Logger.info("delaying for \(kNotificationDelay) seconds")

        // Notifications won't sound if the app is suspended.
        let taskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)

        return after(seconds: kNotificationDelay).done {
            block()
        }.then {
            after(seconds: 2.0)
        }.done {
            // We don't want to endBackgroundTask until *after* the notifications manager is done,
            // but it dispatches async without a completion handler, so we just wait a while extra.
            // This is fragile, but it's only for debug UI.
            UIApplication.shared.endBackgroundTask(taskIdentifier)
        }
    }

    func delayedNotificationDispatchWithFakeCall(thread: TSContactThread, callBlock: @escaping (SignalCall) -> Void) -> Guarantee<Void> {
        let call = SignalCall.incomingCall(localId: UUID(), remotePhoneNumber: thread.contactIdentifier(), signalingId: 0)

        return delayedNotificationDispatch {
            callBlock(call)
        }
    }

    // MARK: Notification Methods

    func notifyForEverythingInSequence(contactThread: TSContactThread) -> Guarantee<Void> {
        let taskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)

        return firstly {
            self.notifyForIncomingCall(thread: contactThread)
        }.then {
            self.notifyForMissedCall(thread: contactThread)
        }.then {
            self.notifyForMissedCallBecauseOfNewIdentity(thread: contactThread)
        }.then {
            self.notifyForMissedCallBecauseOfNoLongerVerifiedIdentity(thread: contactThread)
        }.then {
            self.notifyForIncomingMessage(thread: contactThread)
        }.then {
            self.notifyForErrorMessage(thread: contactThread)
        }.then {
            self.notifyUserForThreadlessErrorMessage()
        }.done {
            UIApplication.shared.endBackgroundTask(taskIdentifier)
        }
    }

    func notifyForIncomingCall(thread: TSContactThread) -> Guarantee<Void> {
        Logger.info("⚠️ will present notification after delay")
        return delayedNotificationDispatchWithFakeCall(thread: thread) { call in
            self.notificationsAdapter.presentIncomingCall(call, callerName: thread.name())
        }
    }

    func notifyForMissedCall(thread: TSContactThread) -> Guarantee<Void> {
        Logger.info("⚠️ will present notification after delay")
        return delayedNotificationDispatchWithFakeCall(thread: thread) { call in
            self.notificationsAdapter.presentMissedCall(call, callerName: thread.name())
        }
    }

    func notifyForMissedCallBecauseOfNewIdentity(thread: TSContactThread) -> Guarantee<Void> {
        Logger.info("⚠️ will present notification after delay")
        return delayedNotificationDispatchWithFakeCall(thread: thread) { call in
            self.notificationsAdapter.presentMissedCallBecauseOfNewIdentity(call: call, callerName: thread.name())
        }
    }

    func notifyForMissedCallBecauseOfNoLongerVerifiedIdentity(thread: TSContactThread) -> Guarantee<Void> {
        Logger.info("⚠️ will present notification after delay")
        return delayedNotificationDispatchWithFakeCall(thread: thread) { call in
            self.notificationsAdapter.presentMissedCallBecauseOfNoLongerVerifiedIdentity(call: call, callerName: thread.name())
        }
    }

    func notifyForIncomingMessage(thread: TSThread) -> Guarantee<Void> {
        Logger.info("⚠️ will present notification after delay")
        return delayedNotificationDispatch {
            self.readWrite { transaction in
                let factory = IncomingMessageFactory()
                factory.threadCreator = { _ in return thread }
                let incomingMessage = factory.create(transaction: transaction)

                self.notificationsAdapter.notifyUser(for: incomingMessage,
                                                     in: thread,
                                                     contactsManager: self.contactsManager,
                                                     transaction: transaction)
            }
        }
    }

    func notifyForErrorMessage(thread: TSThread) -> Guarantee<Void> {
        Logger.info("⚠️ will present notification after delay")
        return delayedNotificationDispatch {
            let errorMessage = TSErrorMessage(timestamp: NSDate.ows_millisecondTimeStamp(),
                                              in: thread,
                                              failedMessageType: TSErrorMessageType.invalidMessage)

            self.readWrite { transaction in
                self.notificationsAdapter.notifyUser(for: errorMessage, thread: thread, transaction: transaction)
            }
        }
    }

    func notifyUserForThreadlessErrorMessage() -> Guarantee<Void> {
        Logger.info("⚠️ will present notification after delay")
        return delayedNotificationDispatch {
            self.readWrite { transaction in
                let errorMessage = TSErrorMessage.corruptedMessageInUnknownThread()

                self.notificationsAdapter.notifyUser(forThreadlessErrorMessage: errorMessage,
                                                     transaction: transaction)
            }
        }
    }
}
