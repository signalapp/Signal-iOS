//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging

#if DEBUG

class DebugUICalling: DebugUIPage {

    // MARK: Overrides 

    override func name() -> String {
        return "Calling"
    }

    override func section(thread aThread: TSThread?) -> OWSTableSection? {
        guard let thread = aThread as? TSContactThread else {
            owsFailDebug("Calling is only valid for contact thread, got thread: \(String(describing: aThread))")
            return nil
        }

        let sectionItems = [
            OWSTableItem(title: "Send 'hangup' for old call") { [weak self] in
                guard let strongSelf = self else { return }

                let kFakeCallId = UInt64(12345)
                var hangupMessage: SSKProtoCallMessageHangup
                do {
                    let hangupBuilder = SSKProtoCallMessageHangup.builder(id: kFakeCallId)
                    hangupMessage = try hangupBuilder.build()
                } catch {
                    owsFailDebug("could not build proto")
                    return
                }
                let callMessage = Self.databaseStorage.read { OWSOutgoingCallMessage(thread: thread, hangupMessage: hangupMessage, destinationDeviceId: nil, transaction: $0) }

                strongSelf.messageSender.sendMessage(.promise, callMessage.asPreparer).done {
                    Logger.debug("Successfully sent hangup call message to \(thread.contactAddress)")
                }.catch { error in
                    Logger.error("failed to send hangup call message to \(thread.contactAddress) with error: \(error)")
                }
            },
            OWSTableItem(title: "Send 'busy' for old call") { [weak self] in
                guard let strongSelf = self else { return }

                let kFakeCallId = UInt64(12345)
                var busyMessage: SSKProtoCallMessageBusy
                do {
                    let busyBuilder = SSKProtoCallMessageBusy.builder(id: kFakeCallId)
                    busyMessage = try busyBuilder.build()
                } catch {
                    owsFailDebug("Couldn't build proto")
                    return
                }

                let callMessage = Self.databaseStorage.read { OWSOutgoingCallMessage(thread: thread, busyMessage: busyMessage, destinationDeviceId: nil, transaction: $0) }

                strongSelf.messageSender.sendMessage(.promise, callMessage.asPreparer).done {
                    Logger.debug("Successfully sent busy call message to \(thread.contactAddress)")
                }.catch { error in
                    Logger.error("failed to send busy call message to \(thread.contactAddress) with error: \(error)")
                }
            }
        ]

        return OWSTableSection(title: "Call Debug", items: sectionItems)
    }
}

#endif
