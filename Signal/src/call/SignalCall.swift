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

// All Observer methods will be invoked from the main thread.
protocol CallObserver: class {
    func stateDidChange(call: SignalCall, state: CallState)
    func hasLocalVideoDidChange(call: SignalCall, hasLocalVideo: Bool)
    func muteDidChange(call: SignalCall, isMuted: Bool)
    func speakerphoneDidChange(call: SignalCall, isEnabled: Bool)
}

/**
 * Data model for a WebRTC backed voice/video call.
 *
 * This class' state should only be accessed on the signaling queue.
 */
@objc class SignalCall: NSObject {

    let TAG = "[SignalCall]"

    var observers = [Weak<CallObserver>]()
    let remotePhoneNumber: String

    // Signal Service identifier for this Call. Used to coordinate the call across remote clients.
    let signalingId: UInt64

    // Distinguishes between calls locally, e.g. in CallKit
    let localId: UUID

    var hasLocalVideo = false {
        didSet {
            // This should only occur on the signaling queue.
            objc_sync_enter(self)

            let observers = self.observers
            let call = self
            let hasLocalVideo = self.hasLocalVideo

            objc_sync_exit(self)

            DispatchQueue.main.async {
                for observer in observers {
                    observer.value?.hasLocalVideoDidChange(call: call, hasLocalVideo: hasLocalVideo)
                }
            }
        }
    }

    var state: CallState {
        didSet {
            // This should only occur on the signaling queue.
            objc_sync_enter(self)
            Logger.debug("\(TAG) state changed: \(oldValue) -> \(self.state)")

            // Update connectedDate
            if self.state == .connected {
                if connectedDate == nil {
                    connectedDate = NSDate()
                }
            } else {
                connectedDate = nil
            }

            let observers = self.observers
            let call = self
            let state = self.state

            objc_sync_exit(self)

            DispatchQueue.main.async {
                for observer in observers {
                    observer.value?.stateDidChange(call: call, state: state)
                }
            }
        }
    }

    var isMuted = false {
        didSet {
            // This should only occur on the signaling queue.
            objc_sync_enter(self)

            Logger.debug("\(TAG) muted changed: \(oldValue) -> \(self.isMuted)")

            let observers = self.observers
            let call = self
            let isMuted = self.isMuted

            objc_sync_exit(self)

            DispatchQueue.main.async {
                for observer in observers {
                    observer.value?.muteDidChange(call: call, isMuted: isMuted)
                }
            }
        }
    }

    var isSpeakerphoneEnabled = false {
        didSet {
            // This should only occur on the signaling queue.
            objc_sync_enter(self)

            Logger.debug("\(TAG) isSpeakerphoneEnabled changed: \(oldValue) -> \(self.isSpeakerphoneEnabled)")

            let observers = self.observers
            let call = self
            let isSpeakerphoneEnabled = self.isSpeakerphoneEnabled

            objc_sync_exit(self)

            DispatchQueue.main.async {
                for observer in observers {
                    observer.value?.speakerphoneDidChange(call: call, isEnabled: isSpeakerphoneEnabled)
                }
            }
        }
    }

    var connectedDate: NSDate?

    var error: CallError?

    // MARK: Initializers and Factory Methods

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

    // -

    func addObserverAndSyncState(observer: CallObserver) {
        objc_sync_enter(self)

        observers.append(Weak(value: observer))

        let call = self
        let state = self.state

        objc_sync_exit(self)

        DispatchQueue.main.async {
            // Synchronize observer with current call state
            observer.stateDidChange(call: call, state: state)
        }
    }

    func removeObserver(_ observer: CallObserver) {
        objc_sync_enter(self)

        while let index = observers.index(where: { $0.value === observer }) {
            observers.remove(at: index)
        }

        objc_sync_exit(self)
    }

    func removeAllObservers() {
        objc_sync_enter(self)

        observers = []

        objc_sync_exit(self)
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
