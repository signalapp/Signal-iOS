//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

enum CallState: String {
    case idle
    case dialing
    case answering
    case remoteRinging
    case localRinging
    case connected
    case localFailure // terminal
    case localHangup // terminal
    case remoteHangup // terminal
    case remoteBusy // terminal
}

protocol CallDelegate: class {
    func stateDidChange(call: SignalCall, state: CallState)
    func hasVideoDidChange(call: SignalCall, hasVideo: Bool)
    func muteDidChange(call: SignalCall, isMuted: Bool)
}

/**
 * Data model for a WebRTC backed voice/video call.
 */
@objc class SignalCall: NSObject {

    let TAG = "[SignalCall]"

    weak var delegate: CallDelegate?
    let remotePhoneNumber: String

    // Signal Service identifier for this Call. Used to coordinate the call across remote clients.
    let signalingId: UInt64

    // Distinguishes between calls locally, e.g. in CallKit
    let localId: UUID
    var hasVideo = false {
        didSet {
            Logger.debug("\(TAG) hasVideo changed: \(oldValue) -> \(hasVideo)")
            delegate?.hasVideoDidChange(call: self, hasVideo: hasVideo)
        }
    }
    var state: CallState {
        didSet {
            Logger.debug("\(TAG) state changed: \(oldValue) -> \(state)")

            // Update connectedDate
            if state == .connected {
                if connectedDate == nil {
                    connectedDate = NSDate()
                }
            } else {
                connectedDate = nil
            }

            delegate?.stateDidChange(call: self, state: state)
        }
    }
    var isMuted = false {
        didSet {
            Logger.debug("\(TAG) muted changed: \(oldValue) -> \(isMuted)")
            delegate?.muteDidChange(call: self, isMuted: isMuted)
        }
    }
    var connectedDate: NSDate?

    var error: CallError?

    init(localId: UUID, signalingId: UInt64, state: CallState, remotePhoneNumber: String) {
        self.localId = localId
        self.signalingId = signalingId
        self.state = state
        self.remotePhoneNumber = remotePhoneNumber
    }

    class func outgoingCall(localId: UUID, remotePhoneNumber: String) -> SignalCall {
        return SignalCall(localId: localId, signalingId: newCallSignalingId(), state: .dialing, remotePhoneNumber: remotePhoneNumber)
    }

    class func incomingCall(localId: UUID, remotePhoneNumber: String, signalingId: UInt64) -> SignalCall {
        return SignalCall(localId: localId, signalingId: signalingId, state: .answering, remotePhoneNumber: remotePhoneNumber)
    }

    // MARK: Equatable
    static func == (lhs: SignalCall, rhs: SignalCall) -> Bool {
        return lhs.localId == rhs.localId
    }

    static func newCallSignalingId() -> UInt64 {
        return UInt64.ows_random()
    }

    // This method should only be called when the call state is "connected".
    func connectionDuration() -> TimeInterval {
        return -connectedDate!.timeIntervalSinceNow
    }
}

fileprivate extension UInt64 {
    static func ows_random() -> UInt64 {
        var random: UInt64 = 0
        arc4random_buf(&random, MemoryLayout.size(ofValue: random))
        return random
    }
}
