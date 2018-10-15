//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import RelayServiceKit
import RelayMessaging

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
        guard aThread?.participantIds.count == 2 else {
            owsFail("Calling is only valid for contact thread, got thread: \(String(describing: aThread))")
            return nil
        }
        
        var contactId = ""
        for uid in (aThread?.participantIds)! {
            if contactId != TSAccountManager.localUID() {
                contactId = uid
            }
        }

        let sectionItems = [
            OWSTableItem(title: "Send 'hangup' for old call") { [weak self] in
                guard let strongSelf = self else { return }

                let kFakeCallId = "12345"
                let hangupMessage = OWSCallHangupMessage(peerId: kFakeCallId)
                let callMessage = OWSOutgoingCallMessage(thread: aThread!, hangupMessage: hangupMessage)

                strongSelf.messageSender.sendPromise(message: callMessage).then {
                    Logger.debug("\(strongSelf.logTag) Successfully sent hangup call message to \(contactId)")
                }.catch { error in
                    Logger.error("\(strongSelf.logTag) failed to send hangup call message to \(contactId) with error: \(error)")
                }
            },
            OWSTableItem(title: "Send 'busy' for old call") { [weak self] in
                guard let strongSelf = self else { return }

                let kFakeCallId = "12345"
                let busyMessage = OWSCallBusyMessage(peerId: kFakeCallId)
                let callMessage = OWSOutgoingCallMessage(thread: aThread!, busyMessage: busyMessage)

                strongSelf.messageSender.sendPromise(message: callMessage).then {
                    Logger.debug("\(strongSelf.logTag) Successfully sent busy call message to \(contactId)")
                }.catch { error in
                    Logger.error("\(strongSelf.logTag) failed to send busy call message to \(contactId) with error: \(error)")
                }
            }
        ]

        return OWSTableSection(title: "Call Debug", items: sectionItems)
    }
}
