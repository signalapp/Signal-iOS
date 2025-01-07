//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalRingRTC
import SignalServiceKit
import SignalUI

enum CallMode {
    case individual(IndividualCall)
    case groupThread(GroupThreadCall)
    case callLink(CallLinkCall)

    init(groupCall: GroupCall) {
        switch groupCall.concreteType {
        case .groupThread(let call): self = .groupThread(call)
        case .callLink(let call): self = .callLink(call)
        }
    }

    var commonState: CommonCallState {
        switch self {
        case .individual(let call):
            return call.commonState
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            return call.commonState
        }
    }

    @MainActor
    var hasTerminated: Bool {
        switch self {
        case .individual(let call): return call.hasTerminated
        case .groupThread(let call): return call.hasTerminated
        case .callLink: return false
        }
    }

    @MainActor
    var isOutgoingAudioMuted: Bool {
        switch self {
        case .individual(let call):
            return call.isMuted
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            return call.ringRtcCall.isOutgoingAudioMuted
        }
    }

    @MainActor
    var isOutgoingVideoMuted: Bool {
        switch self {
        case .individual(let call):
            return !call.hasLocalVideo
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            return call.ringRtcCall.isOutgoingVideoMuted
        }
    }

    @MainActor
    var joinState: JoinState {
        switch self {
        case .individual(let call):
            /// `JoinState` is a group call concept, but we want to bridge
            /// between the two call types.
            /// TODO: Continue to tweak this as we unify the individual and
            /// group call UIs.
            switch call.state {
            case .idle,
                 .remoteHangup,
                 .remoteHangupNeedPermission,
                 .localHangup,
                 .remoteRinging,
                 .localRinging_Anticipatory,
                 .localRinging_ReadyToAnswer,
                 .remoteBusy,
                 .localFailure,
                 .busyElsewhere,
                 .answeredElsewhere,
                 .declinedElsewhere:
                return .notJoined
            case .connected,
                 .accepting,
                 .answering,
                 .reconnecting,
                 .dialing:
                return .joined
            }
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            return call.joinState
        }
    }

    var isFull: Bool {
        switch self {
        case .individual:
            return false
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            return call.ringRtcCall.isFull
        }
    }

    /// Returns the remote party for an incoming 1:1 call, or the ringer for a group call ring.
    ///
    /// Returns `nil` for an outgoing 1:1 call, a manually-entered group call,
    /// or a group call that has already been joined.
    var caller: SignalServiceAddress? {
        switch self {
        case .individual(let call):
            guard call.direction == .incoming else {
                return nil
            }
            return call.remoteAddress
        case .groupThread(let call):
            guard case .incomingRing(let caller, _) = call.groupCallRingState else {
                return nil
            }
            return caller
        case .callLink:
            return nil
        }
    }

    var videoCaptureController: VideoCaptureController {
        switch self {
        case .individual(let call):
            return call.videoCaptureController
        case .groupThread(let call as GroupCall), .callLink(let call as GroupCall):
            return call.videoCaptureController
        }
    }

    func matches(_ callTarget: CallTarget) -> Bool {
        switch (self, callTarget) {
        case (.individual(let call), .individual(let thread)) where call.thread.uniqueId == thread.uniqueId:
            return true
        case (.groupThread(let call), .groupThread(let groupId)) where call.groupId.serialize() == groupId.serialize():
            return true
        case (.callLink(let call), .callLink(let callLink)) where call.callLink.rootKey.bytes == callLink.rootKey.bytes:
            return true
        case (.individual, _), (.groupThread, _), (.callLink, _):
            return false
        }
    }
}

enum CallError: Error {
    case providerReset
    case disconnected
    case externalError(underlyingError: Error)
    case timeout(description: String)
    case signaling
    case doNotDisturbEnabled
    case contactIsBlocked

    func shouldSilentlyDropCall() -> Bool {
        switch self {
        case .providerReset, .disconnected, .externalError, .timeout, .signaling:
            return false
        case .doNotDisturbEnabled, .contactIsBlocked:
            return true
        }
    }

    static func wrapErrorIfNeeded(_ error: any Error) -> CallError {
        switch error {
        case let callError as CallError:
            return callError
        default:
            return .externalError(underlyingError: error)
        }
    }
}

/// Represents a call happening on this device.
class SignalCall: CallManagerCallReference {
    let mode: CallMode

    var commonState: CommonCallState { mode.commonState }
    @MainActor var hasTerminated: Bool { mode.hasTerminated }
    @MainActor var isOutgoingAudioMuted: Bool { mode.isOutgoingAudioMuted }
    @MainActor var isOutgoingVideoMuted: Bool { mode.isOutgoingVideoMuted }
    @MainActor var joinState: JoinState { mode.joinState }
    var isFull: Bool { mode.isFull }
    var caller: SignalServiceAddress? { mode.caller }
    var videoCaptureController: VideoCaptureController { mode.videoCaptureController }

    init(groupThreadCall: GroupThreadCall) {
        self.mode = .groupThread(groupThreadCall)
    }

    init(callLinkCall: CallLinkCall) {
        self.mode = .callLink(callLinkCall)
    }

    init(individualCall: IndividualCall) {
        self.mode = .individual(individualCall)
    }

    var localId: UUID {
        return self.mode.commonState.localId
    }

    var offerMediaType: TSRecentCallOfferType {
        switch mode {
        case .individual(let call): return call.offerMediaType
        case .groupThread: return .video
        case .callLink: return .video
        }
    }
}
