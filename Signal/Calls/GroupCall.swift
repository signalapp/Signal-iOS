//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalRingRTC
import SignalServiceKit
import SignalUI

class GroupCall: SignalRingRTC.GroupCallDelegate {
    let commonState: CommonCallState
    let ringRtcCall: SignalRingRTC.GroupCall
    private(set) var raisedHands: [RemoteDeviceState] = []
    let videoCaptureController: VideoCaptureController

    init(
        audioDescription: String,
        ringRtcCall: SignalRingRTC.GroupCall,
        videoCaptureController: VideoCaptureController
    ) {
        self.commonState = CommonCallState(
            audioActivity: AudioActivity(audioDescription: audioDescription, behavior: .call)
        )
        self.ringRtcCall = ringRtcCall
        self.videoCaptureController = videoCaptureController
        self.ringRtcCall.delegate = self
    }

    var joinState: JoinState {
        return self.ringRtcCall.localDeviceState.joinState
    }

    // MARK: - GroupCallDelegate

    func groupCall(onLocalDeviceStateChanged groupCall: SignalRingRTC.GroupCall) {
        if groupCall.localDeviceState.joinState == .joined, commonState.setConnectedDateIfNeeded() {
            // make sure we don't terminate audio session during call
            NSObject.audioSession.isRTCAudioEnabled = true
            owsAssertDebug(NSObject.audioSession.startAudioActivity(commonState.audioActivity))
        }
    }

    func groupCall(onRemoteDeviceStatesChanged groupCall: SignalRingRTC.GroupCall) {
    }

    func groupCall(onAudioLevels groupCall: SignalRingRTC.GroupCall) {
        // TODO: Implement audio level handling for group calls.
    }

    func groupCall(onLowBandwidthForVideo groupCall: SignalRingRTC.GroupCall, recovered: Bool) {
        // TODO: Implement handling of the "low outgoing bandwidth for video" notification.
    }

    func groupCall(onReactions groupCall: SignalRingRTC.GroupCall, reactions: [SignalRingRTC.Reaction]) {
    }

    func groupCall(onRaisedHands groupCall: SignalRingRTC.GroupCall, raisedHands: [UInt32]) {
        guard
            FeatureFlags.callRaiseHandReceiveSupport,
            FeatureFlags.useCallMemberComposableViewsForRemoteUsersInGroupCalls
        else { return }

        self.raisedHands = raisedHands.compactMap { groupCall.remoteDeviceStates[$0] }
    }

    func groupCall(onPeekChanged groupCall: SignalRingRTC.GroupCall) {
    }

    func groupCall(requestMembershipProof groupCall: SignalRingRTC.GroupCall) {
    }

    func groupCall(requestGroupMembers groupCall: SignalRingRTC.GroupCall) {
    }

    func groupCall(onEnded groupCall: SignalRingRTC.GroupCall, reason: GroupCallEndReason) {
    }
}
