//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

class DebugUINotifications: DebugUIPage {

    // MARK: Dependencies

    var notificationsManager: NotificationsManager {
        return SignalApp.shared().notificationsManager
    }
    var notificationsAdapter: CallNotificationsAdapter {
        return SignalApp.shared().callService.notificationsAdapter
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

    override func section(thread aThread: TSThread?) -> OWSTableSection? {
        guard let thread = aThread else {
            owsFailDebug("Notifications must specify thread.")
            return nil
        }

        var sectionItems = [
            OWSTableItem(title: "Last Incoming Message") { [weak self] in
                guard let strongSelf = self else {
                    return
                }

                Logger.info("scheduling notification for incoming message.")
                strongSelf.delayedNotificationDispatch {
                    Logger.info("dispatching")
                    OWSPrimaryStorage.shared().newDatabaseConnection().read { (transaction) in
                        guard let viewTransaction = transaction.ext(TSMessageDatabaseViewExtensionName) as? YapDatabaseViewTransaction  else {
                            owsFailDebug("unable to build view transaction")
                            return
                        }

                        guard let threadId = thread.uniqueId else {
                            owsFailDebug("thread had no uniqueId")
                            return
                        }

                        guard let incomingMessage = viewTransaction.lastObject(inGroup: threadId) as? TSIncomingMessage else {
                            owsFailDebug("last message was not an incoming message.")
                            return
                        }
                        Logger.info("notifying user of incoming message")
                        strongSelf.notificationsManager.notifyUser(for: incomingMessage, in: thread, contactsManager: strongSelf.contactsManager, transaction: transaction)
                    }
                }
            }
        ]

        if let contactThread = thread as? TSContactThread {
            sectionItems += [
                OWSTableItem(title: "Call Missed") { [weak self] in
                    guard let strongSelf = self else {
                        return
                    }

                    strongSelf.delayedNotificationDispatchWithFakeCall(thread: contactThread) { call in
                        strongSelf.notificationsAdapter.presentMissedCall(call, callerName: thread.name())
                    }
                },
                OWSTableItem(title: "Call Rejected: New Safety Number") { [weak self] in
                    guard let strongSelf = self else {
                        return
                    }

                    strongSelf.delayedNotificationDispatchWithFakeCall(thread: contactThread) { call in
                        strongSelf.notificationsAdapter.presentMissedCallBecauseOfNewIdentity(call: call, callerName: thread.name())
                    }
                },
                OWSTableItem(title: "Call Rejected: No Longer Verified") { [weak self] in
                    guard let strongSelf = self else {
                        return
                    }

                    strongSelf.delayedNotificationDispatchWithFakeCall(thread: contactThread) { call in
                        strongSelf.notificationsAdapter.presentMissedCallBecauseOfNoLongerVerifiedIdentity(call: call, callerName: thread.name())
                    }
                }
            ]
        }

        return OWSTableSection(title: "Notifications have delay: \(kNotificationDelay)s", items: sectionItems)
    }

    // MARK: Helpers

    // After enqueing the notification you may want to background the app or lock the screen before it triggers, so
    // we give a little delay.
    let kNotificationDelay: TimeInterval = 5

    func delayedNotificationDispatch(block: @escaping () -> Void) {

        // Notifications won't sound if the app is suspended.
        let taskIdentifier = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + kNotificationDelay) {
            block()

            // We don't want to endBackgroundTask until *after* the notifications manager is done,
            // but it dispatches async without a completion handler, so we just wait a while extra.
            // This is fragile, but it's only for debug UI.
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2.0) {
                UIApplication.shared.endBackgroundTask(taskIdentifier)
            }
        }
    }

    func delayedNotificationDispatchWithFakeCall(thread: TSContactThread, callBlock: @escaping (SignalCall) -> Void) {
        let call = SignalCall.incomingCall(localId: UUID(), remotePhoneNumber: thread.contactIdentifier(), signalingId: 0)

        delayedNotificationDispatch {
            callBlock(call)
        }
    }
}
