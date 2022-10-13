//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalRingRTC

class GroupCallUpdateMessageHandler: CallServiceObserver, CallObserver, Dependencies {

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

        SDSDatabaseStorage.shared.asyncWrite { writeTx in
            let updateMessage = OWSOutgoingGroupCallMessage(thread: thread, eraId: eraId, transaction: writeTx)
            Self.messageSenderJobQueue.add(message: updateMessage.asPreparer, transaction: writeTx)
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
        owsAssertDebug(call == Self.callService.currentCall)
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
