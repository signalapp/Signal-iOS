//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalRingRTC

// All Observer methods will be invoked from the main thread.
public protocol CallObserver: class {
    func individualCallStateDidChange(_ call: SignalCall, state: CallState)
    func individualCallLocalVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool)
    func individualCallLocalAudioMuteDidChange(_ call: SignalCall, isAudioMuted: Bool)
    func individualCallRemoteVideoMuteDidChange(_ call: SignalCall, isVideoMuted: Bool)
    func individualCallHoldDidChange(_ call: SignalCall, isOnHold: Bool)

    func groupCallLocalDeviceStateChanged(_ call: SignalCall)
    func groupCallRemoteDeviceStatesChanged(_ call: SignalCall)
    func groupCallJoinedGroupMembersChanged(_ call: SignalCall)
    func groupCallUpdateSfuInfo(_ call: SignalCall)
    func groupCallUpdateGroupMembershipProof(_ call: SignalCall)
    func groupCallUpdateGroupMembers(_ call: SignalCall)
    func groupCallEnded(_ call: SignalCall, reason: GroupCallEndReason)
}

@objc
public class SignalCall: NSObject, CallManagerCallReference {
    public let mode: Mode
    public enum Mode {
        case individual(IndividualCall)
        case group(GroupCall)
    }

    public let audioActivity: AudioActivity

    @objc
    var isGroupCall: Bool {
        switch mode {
        case .group: return true
        case .individual: return false
        }
    }

    var groupCall: GroupCall! {
        owsAssertDebug(isGroupCall)
        guard case .group(let call) = mode else {
            owsFailDebug("Missing group call")
            return nil
        }
        return call
    }

    @objc
    var isIndividualCall: Bool {
        switch mode {
        case .group: return false
        case .individual: return true
        }
    }

    @objc
    var individualCall: IndividualCall! {
        owsAssertDebug(isIndividualCall)
        guard case .individual(let call) = mode else {
            owsFailDebug("Missing individual call")
            return nil
        }
        return call
    }

    let videoCaptureController = VideoCaptureController()

    public var connectedDate: Date?
    public let thread: TSThread?

    public var error: CallError?
    public enum CallError: Error {
        case providerReset
        case disconnected
        case externalError(underlyingError: Error)
        case timeout(description: String)
        case messageSendFailure(underlyingError: Error)
    }

    init(groupCall: GroupCall, groupThread: TSGroupThread) {
        mode = .group(groupCall)
        audioActivity = AudioActivity(
            audioDescription: "[SignalCall] with group \(groupCall.groupId)",
            behavior: .call
        )
        thread = groupThread
        super.init()
        groupCall.delegate = self
    }

    init(individualCall: IndividualCall) {
        mode = .individual(individualCall)
        audioActivity = AudioActivity(
            audioDescription: "[SignalCall] with individual \(individualCall.remoteAddress)",
            behavior: .call
        )
        thread = individualCall.thread
        super.init()
        individualCall.delegate = self
    }

    public class func groupCall(thread: TSGroupThread) -> SignalCall? {
        owsAssertDebug(thread.groupModel.groupsVersion == .V2)

        guard let localUuid = TSAccountManager.shared().localUuid else {
            owsFailDebug("Failed to query local UUID")
            return nil
        }

        let groupCall = AppEnvironment.shared.callService.callManager.createGroupCall(
            groupId: thread.groupModel.groupId,
            userId: localUuid
        )

        return SignalCall(groupCall: groupCall, groupThread: thread)
    }

    public class func outgoingIndividualCall(localId: UUID, remoteAddress: SignalServiceAddress) -> SignalCall {
        let individualCall = IndividualCall(
            direction: .outgoing,
            localId: localId,
            state: .dialing,
            remoteAddress: remoteAddress,
            sentAtTimestamp: Date.ows_millisecondTimestamp(),
            callAdapterType: .default
        )
        return SignalCall(individualCall: individualCall)
    }

    public class func incomingIndividualCall(
        localId: UUID,
        remoteAddress: SignalServiceAddress,
        sentAtTimestamp: UInt64,
        offerMediaType: TSRecentCallOfferType
    ) -> SignalCall {
        // If this is a video call, we want to use in the in app call screen
        // because CallKit has poor support for video calls.
        let callAdapterType: CallAdapterType
        if offerMediaType == .video {
            callAdapterType = .nonCallKit
        } else {
            callAdapterType = .default
        }

        let individualCall = IndividualCall(
            direction: .incoming,
            localId: localId,
            state: .answering,
            remoteAddress: remoteAddress,
            sentAtTimestamp: sentAtTimestamp,
            callAdapterType: callAdapterType
        )
        individualCall.offerMediaType = offerMediaType
        return SignalCall(individualCall: individualCall)
    }

    // MARK: -

    private var observers: WeakArray<CallObserver> = []

    public func addObserverAndSyncState(observer: CallObserver) {
        AssertIsOnMainThread()

        observers.append(observer)

        // Synchronize observer with current call state
        switch mode {
        case .individual(let individualCall):
            observer.individualCallStateDidChange(self, state: individualCall.state)
        case .group:
            observer.groupCallLocalDeviceStateChanged(self)
            observer.groupCallRemoteDeviceStatesChanged(self)
        }
    }

    public func removeObserver(_ observer: CallObserver) {
        AssertIsOnMainThread()

        observers.removeAll { $0 === observer }
    }

    public func removeAllObservers() {
        AssertIsOnMainThread()

        observers = []
    }

    // MARK: -

    // This method should only be called when the call state is "connected".
    public func connectionDuration() -> TimeInterval {
        guard let connectedDate = connectedDate else {
            owsFailDebug("Called connectionDuration before connected.")
            return 0
        }
        return -connectedDate.timeIntervalSinceNow
    }
}

extension SignalCall: GroupCallDelegate {
    public func groupCall(onLocalDeviceStateChanged groupCall: GroupCall) {
        if groupCall.localDevice.joinState == .joined, connectedDate == nil {
            connectedDate = Date()
        }

        observers.elements.forEach { $0.groupCallLocalDeviceStateChanged(self) }
    }

    public func groupCall(onRemoteDeviceStatesChanged groupCall: GroupCall) {
        observers.elements.forEach { $0.groupCallRemoteDeviceStatesChanged(self) }
    }

    public func groupCall(onJoinedGroupMembersChanged groupCall: GroupCall) {
        observers.elements.forEach { $0.groupCallJoinedGroupMembersChanged(self) }
    }

    public func groupCall(updateSfuInfo groupCall: GroupCall) {
        observers.elements.forEach { $0.groupCallUpdateSfuInfo(self) }
    }

    public func groupCall(updateGroupMembershipProof groupCall: GroupCall) {
        observers.elements.forEach { $0.groupCallUpdateGroupMembershipProof(self) }
    }

    public func groupCall(updateGroupMembers groupCall: GroupCall) {
        observers.elements.forEach { $0.groupCallUpdateGroupMembers(self) }
    }

    public func groupCall(onEnded groupCall: GroupCall, reason: GroupCallEndReason) {
        observers.elements.forEach { $0.groupCallEnded(self, reason: reason) }
    }
}

extension SignalCall: IndividualCallDelegate {
    public func individualCallStateDidChange(_ call: IndividualCall, state: CallState) {
        if case .connected = state, connectedDate == nil {
            connectedDate = Date()
        }

        observers.elements.forEach { $0.individualCallStateDidChange(self, state: state) }
    }

    public func individualCallLocalVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool) {
        observers.elements.forEach { $0.individualCallLocalVideoMuteDidChange(self, isVideoMuted: isVideoMuted) }
    }

    public func individualCallLocalAudioMuteDidChange(_ call: IndividualCall, isAudioMuted: Bool) {
        observers.elements.forEach { $0.individualCallLocalAudioMuteDidChange(self, isAudioMuted: isAudioMuted) }
    }

    public func individualCallHoldDidChange(_ call: IndividualCall, isOnHold: Bool) {
        observers.elements.forEach { $0.individualCallHoldDidChange(self, isOnHold: isOnHold) }
    }

    public func individualCallRemoteVideoMuteDidChange(_ call: IndividualCall, isVideoMuted: Bool) {
        observers.elements.forEach { $0.individualCallRemoteVideoMuteDidChange(self, isVideoMuted: isVideoMuted) }
    }
}
