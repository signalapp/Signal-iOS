//  Created by Michael Kirk on 12/7/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

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

/**
 * Data model for a WebRTC backed voice/video call.
 */
@objc class SignalCall: NSObject {

    let TAG = "[SignalCall]"

    var state: CallState {
        didSet {
            Logger.debug("\(TAG) state changed: \(oldValue) -> \(state)")
            stateDidChange?(state)
        }
    }

    let signalingId: UInt64
    let remotePhoneNumber: String
    let localId: UUID
    var hasVideo = false
    var error: CallError?

    var stateDidChange: ((_ newState: CallState) -> Void)?

    init(localId: UUID, signalingId: UInt64, state: CallState, remotePhoneNumber: String) {
        self.localId = localId
        self.signalingId = signalingId
        self.state = state
        self.remotePhoneNumber = remotePhoneNumber
    }

    class func outgoingCall(localId: UUID, remotePhoneNumber: String) -> SignalCall {
        return SignalCall(localId: localId, signalingId: UInt64.ows_random(), state: .dialing, remotePhoneNumber: remotePhoneNumber)
    }

    class func incomingCall(localId: UUID, remotePhoneNumber: String, signalingId: UInt64) -> SignalCall {
        return SignalCall(localId: localId, signalingId: signalingId, state: .answering, remotePhoneNumber: remotePhoneNumber)
    }

    // MARK: Equatable
    static func == (lhs: SignalCall, rhs: SignalCall) -> Bool {
        return lhs.localId == rhs.localId
    }

}

fileprivate extension UInt64 {
    static func ows_random() -> UInt64 {
        var random: UInt64 = 0
        arc4random_buf(&random, MemoryLayout.size(ofValue: random))
        return random
    }
}
