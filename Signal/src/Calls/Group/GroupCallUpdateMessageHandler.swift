//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalRingRTC

class GroupCallUpdateMessageHandler: CallServiceObserver, CallObserver {

    var didSendJoinMessage: Bool = false

    func sendJoinMessageForCallIfNecessary(_ signalCall: SignalCall) {
        guard !didSendJoinMessage else { return }
        guard signalCall.isGroupCall, let groupCall = signalCall.groupCall else { return }
        guard let eraId = groupCall.peekInfo?.eraId else { return }
        guard let groupThread = signalCall.thread as? TSGroupThread else { return }
        guard groupCall.localDeviceState.joinState == .joined else { return }

        sendUpdateMessageForThread(groupThread, eraId: eraId)
        didSendJoinMessage = true
    }

    func sendLeaveMessageForCallIfNecessary(_ signalCall: SignalCall) {
        guard didSendJoinMessage else { return }
        guard signalCall.isGroupCall, let groupCall = signalCall.groupCall else { return }
        guard let groupThread = signalCall.thread as? TSGroupThread else { return }

        sendUpdateMessageForThread(groupThread, eraId: groupCall.peekInfo?.eraId)
        didSendJoinMessage = false
    }

    func sendUpdateMessageForThread(_ thread: TSGroupThread, eraId: String?) {
        Logger.info("Sending call update message for thread \(thread.uniqueId)")

        let updateMessage = OWSOutgoingGroupCallMessage(thread: thread, eraId: eraId)
        let messagePreparer = updateMessage.asPreparer
        SDSDatabaseStorage.shared.asyncWrite { writeTx in
            SSKEnvironment.shared.messageSenderJobQueue.add(message: messagePreparer, transaction: writeTx)
        }
    }

    func handleUpdateMessage(_ message: SSKProtoDataMessageGroupCallUpdate, for thread: TSGroupThread, serverReceivedTimestamp: UInt64) {
        Logger.info("Received group call update message for thread: \(thread.uniqueId) eraId: \(message.eraID)")
        DispatchQueue.main.async {
            AppEnvironment.shared.callService.peekCallAndUpdateThread(
                thread,
                expectedEraId: message.eraID,
                triggerEventTimestamp: serverReceivedTimestamp)
        }
    }

    // MARK: - CallServiceObserver

    func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?) {
        if let oldValue = oldValue {
            sendLeaveMessageForCallIfNecessary(oldValue)
        }
        didSendJoinMessage = false
        oldValue?.removeObserver(self)
        newValue?.addObserverAndSyncState(observer: self)
    }

    // MARK: - CallObserver

    func groupCallLocalDeviceStateChanged(_ call: SignalCall) {
        owsAssertDebug(call == AppEnvironment.shared.callService.currentCall)
        guard call.isGroupCall, let groupCall = call.groupCall else { return owsFailDebug("Expected a group call") }

        let isJoined = (groupCall.localDeviceState.joinState == .joined)
        if isJoined {
            sendJoinMessageForCallIfNecessary(call)
        } else {
            sendLeaveMessageForCallIfNecessary(call)
        }
    }

    func groupCallPeekChanged(_ call: SignalCall) {
        sendJoinMessageForCallIfNecessary(call)
    }

    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason) {
        didSendJoinMessage = false
    }
}
