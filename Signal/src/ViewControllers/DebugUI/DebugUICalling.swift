//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

class DebugUICalling: DebugUIPage {

    // MARK: Dependencies

    var messageSender: MessageSender {
        return Environment.current().messageSender
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
            OWSTableItem(title:"Send 'hangup' for old call") {
                let kFakeCallId = UInt64(12345)
                let hangupMessage = OWSCallHangupMessage(callId: kFakeCallId)
                let callMessage = OWSOutgoingCallMessage(thread: thread, hangupMessage: hangupMessage)

                self.messageSender.sendPromise(message: callMessage).then {
                    Logger.debug("\(self.logTag) Successfully sent hangup call message to \(thread.contactIdentifier())")
                }.catch { error in
                    Logger.error("\(self.logTag) failed to send hangup call message to \(thread.contactIdentifier()) with error: \(error)")
                }
            },
            OWSTableItem(title:"Send 'busy' for old call") {
                let kFakeCallId = UInt64(12345)
                let busyMessage = OWSCallBusyMessage(callId: kFakeCallId)
                let callMessage = OWSOutgoingCallMessage(thread: thread, busyMessage: busyMessage)

                self.messageSender.sendPromise(message: callMessage).then {
                    Logger.debug("\(self.logTag) Successfully sent busy call message to \(thread.contactIdentifier())")
                }.catch { error in
                    Logger.error("\(self.logTag) failed to send busy call message to \(thread.contactIdentifier()) with error: \(error)")
                }
            }
        ]

        return OWSTableSection(title: "Call Debug", items: sectionItems)
    }
}
