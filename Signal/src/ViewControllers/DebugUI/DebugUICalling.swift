//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUICalling: DebugUIPage, Dependencies {

    let name = "Calling"

    func section(thread: TSThread?) -> OWSTableSection? {
        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Calling is only valid for contact thread, got thread: \(String(describing: thread))")
            return nil
        }

        let sectionItems = [
            OWSTableItem(title: "Send 'hangup' for old call") { [weak self] in
                guard let self else { return }

                let kFakeCallId = UInt64(12345)
                var hangupMessage: SSKProtoCallMessageHangup
                do {
                    let hangupBuilder = SSKProtoCallMessageHangup.builder(id: kFakeCallId)
                    hangupMessage = try hangupBuilder.build()
                } catch {
                    owsFailDebug("could not build proto")
                    return
                }
                let callMessage = Self.databaseStorage.read {
                    OWSOutgoingCallMessage(
                        thread: contactThread,
                        hangupMessage: hangupMessage,
                        destinationDeviceId: nil,
                        transaction: $0
                    )
                }

                Task {
                    do {
                        try await self.messageSender.sendMessage(callMessage.asPreparer)
                        Logger.debug("Successfully sent hangup call message to \(contactThread.contactAddress)")
                    } catch {
                        Logger.error("failed to send hangup call message to \(contactThread.contactAddress) with error: \(error)")
                    }
                }
            },
            OWSTableItem(title: "Send 'busy' for old call") { [weak self] in
                guard let self else { return }

                let kFakeCallId = UInt64(12345)
                var busyMessage: SSKProtoCallMessageBusy
                do {
                    let busyBuilder = SSKProtoCallMessageBusy.builder(id: kFakeCallId)
                    busyMessage = try busyBuilder.build()
                } catch {
                    owsFailDebug("Couldn't build proto")
                    return
                }

                let callMessage = Self.databaseStorage.read {
                    OWSOutgoingCallMessage(
                        thread: contactThread,
                        busyMessage: busyMessage,
                        destinationDeviceId: nil,
                        transaction: $0)
                }

                Task {
                    do {
                        try await self.messageSender.sendMessage(callMessage.asPreparer)
                        Logger.debug("Successfully sent busy call message to \(contactThread.contactAddress)")
                    } catch {
                        Logger.error("failed to send busy call message to \(contactThread.contactAddress) with error: \(error)")
                    }
                }
            }
        ]

        return OWSTableSection(title: "Call Debug", items: sectionItems)
    }
}

#endif
