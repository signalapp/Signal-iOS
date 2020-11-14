//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

class GroupCallUpdateMessageHandler: CallServiceObserver, CallObserver {

    // MARK: - Sending

    var lastJoinStatus: Bool = false
    var currentCall: SignalCall? {
        didSet {
            guard oldValue != currentCall else { return }

            // If the last call was last seen as "Joined" make sure to send an update message for leaving
            // Then reset our join status to false so we'll send an update message when joining the next call
            if lastJoinStatus, let oldThread = oldValue?.thread as? TSGroupThread {
                sendUpdateMessageForThread(oldThread)
            }
            lastJoinStatus = false

            oldValue?.removeObserver(self)
            currentCall?.addObserverAndSyncState(observer: self)
        }
    }

    func sendUpdateMessageForThread(_ thread: TSGroupThread) {
        Logger.info("Sending call update message for thread \(thread)")

        let updateMessage = OWSOutgoingGroupCallMessage(thread: thread)
        let messagePreparer = updateMessage.asPreparer
        SDSDatabaseStorage.shared.asyncWrite { writeTx in
            SSKEnvironment.shared.messageSenderJobQueue.add(message: messagePreparer, transaction: writeTx)
        }
    }

    // MARK: - CallServiceObserver

    func didUpdateCall(call: SignalCall?) {
        currentCall = call
    }

    // MARK: - CallObserver

    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {
        owsAssertDebug(call == currentCall)
        guard call.isGroupCall else { return owsFailDebug("Expected a group call") }
        guard let groupThread = call.thread as? TSGroupThread else { return owsFailDebug("Unexpected thread type") }

        let isJoined = (call.groupCall.localDeviceState.joinState == .joined)
        if isJoined != lastJoinStatus {
            lastJoinStatus = isJoined
            sendUpdateMessageForThread(groupThread)
        }
    }
}
