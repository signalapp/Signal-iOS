//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

class DebugUICalling: DebugUIPage {

    let TAG = "[DebugUICalling]"

    // MARK: Dependencies

    var notificationsAdapter: CallNotificationsAdapter {
        return Environment.getCurrent().callService.notificationsAdapter
    }
    var messageSender: MessageSender {
        return Environment.getCurrent().messageSender
    }

    // MARK: Overrides 

    override func name() -> String {
        return "Calling"
    }

    override func section(thread aThread: TSThread?) -> OWSTableSection? {
        guard let thread = aThread as? TSContactThread else {
            owsFail("Calling is only valid for contact thread, got thread: \(String(describing: aThread))")
            return nil
        }

        let sectionItems = [
            OWSTableItem(title:"⚠️ Missed Call") {
                self.delayedDispatchWithFakeCall(thread: thread) { call in
                    self.notificationsAdapter.presentMissedCall(call, callerName: thread.name())
                }
            },
            OWSTableItem(title:"⚠️ New Safety Number (rejected)") {
                self.delayedDispatchWithFakeCall(thread: thread) { call in
                    self.notificationsAdapter.presentMissedCallBecauseOfNewIdentity(call: call, callerName: thread.name())
                }
            },
            OWSTableItem(title:"⚠️ No Longer Verified (rejected)") {
                self.delayedDispatchWithFakeCall(thread: thread) { call in
                    self.notificationsAdapter.presentMissedCallBecauseOfNoLongerVerifiedIdentity(call: call, callerName: thread.name())
                }
            },
            OWSTableItem(title:"Send 'hangup' for old call") {
                let kFakeCallId = UInt64(12345)
                let hangupMessage = OWSCallHangupMessage(callId: kFakeCallId)
                let callMessage = OWSOutgoingCallMessage(thread: thread, hangupMessage: hangupMessage)

                self.messageSender.sendPromise(message: callMessage).then {
                    Logger.debug("\(self.TAG) Successfully sent hangup call message to \(thread.contactIdentifier())")
                }.catch { error in
                    Logger.error("\(self.TAG) failed to send hangup call message to \(thread.contactIdentifier()) with error: \(error)")
                }
            },
            OWSTableItem(title:"Send 'busy' for old call") {
                let kFakeCallId = UInt64(12345)
                let busyMessage = OWSCallBusyMessage(callId: kFakeCallId)
                let callMessage = OWSOutgoingCallMessage(thread: thread, busyMessage: busyMessage)

                self.messageSender.sendPromise(message: callMessage).then {
                    Logger.debug("\(self.TAG) Successfully sent busy call message to \(thread.contactIdentifier())")
                }.catch { error in
                    Logger.error("\(self.TAG) failed to send busy call message to \(thread.contactIdentifier()) with error: \(error)")
                }
            }
        ]

        return OWSTableSection(title: "Call Notifications (⚠️) have delay: \(kNotificationDelay)s", items: sectionItems)
    }

    // MARK: Helpers

    // After enqueing the notification you may want to background the app or lock the screen before it triggers, so
    // we give a little delay.
    let kNotificationDelay: TimeInterval = 5

    func delayedDispatchWithFakeCall(thread: TSContactThread, callBlock: @escaping (SignalCall) -> Void) {
        let call = SignalCall.incomingCall(localId: UUID(), remotePhoneNumber: thread.contactIdentifier(), signalingId: 0)

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + kNotificationDelay) {
            callBlock(call)
        }
    }
}
