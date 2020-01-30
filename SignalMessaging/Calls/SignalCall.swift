//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

public enum CallState: String {
    case idle
    case dialing
    case answering
    case remoteRinging
    case localRinging
    case connected
    case reconnecting
    case localFailure // terminal
    case localHangup // terminal
    case remoteHangup // terminal
    case remoteBusy // terminal
}

public enum CallDirection {
    case outgoing, incoming
}

// All Observer methods will be invoked from the main thread.
public protocol CallObserver: class {
    func stateDidChange(call: SignalCall, state: CallState)
    func hasLocalVideoDidChange(call: SignalCall, hasLocalVideo: Bool)
    func muteDidChange(call: SignalCall, isMuted: Bool)
    func holdDidChange(call: SignalCall, isOnHold: Bool)
    func audioSourceDidChange(call: SignalCall, audioSource: AudioSource?)
}

public enum CallError: Error {
    case providerReset
    case assertionError(description: String)
    case disconnected
    case externalError(underlyingError: Error)
    case timeout(description: String)
    case obsoleteCall(description: String)
    case fatalError(description: String)
    case messageSendFailure(underlyingError: Error)
}

/**
 * Data model for a WebRTC backed voice/video call.
 *
 * This class' state should only be accessed on the main queue.
 */
@objc public class SignalCall: NSObject {

    var observers = [Weak<CallObserver>]()

    @objc
    public let remoteAddress: SignalServiceAddress

    public var isTerminated: Bool {
        switch state {
        case .localFailure, .localHangup, .remoteHangup, .remoteBusy:
            return true
        case .idle, .dialing, .answering, .remoteRinging, .localRinging, .connected, .reconnecting:
            return false
        }
    }

    // Signal Service identifier for this Call. Used to coordinate the call across remote clients.
    public let signalingId: UInt64

    public let direction: CallDirection

    // Distinguishes between calls locally, e.g. in CallKit
    @objc
    public let localId: UUID

    public let thread: TSContactThread

    public var callRecord: TSCall? {
        didSet {
            AssertIsOnMainThread()
            assert(oldValue == nil)

            updateCallRecordType()
        }
    }

    public var hasLocalVideo = false {
        didSet {
            AssertIsOnMainThread()

            for observer in observers {
                observer.value?.hasLocalVideoDidChange(call: self, hasLocalVideo: hasLocalVideo)
            }
        }
    }

    public var state: CallState {
        didSet {
            AssertIsOnMainThread()
            Logger.debug("state changed: \(oldValue) -> \(self.state) for call: \(self.identifiersForLogs)")

            // Update connectedDate
            if case .connected = self.state {
                // if it's the first time we've connected (not a reconnect)
                if connectedDate == nil {
                    connectedDate = NSDate()
                }
            }

            updateCallRecordType()

            for observer in observers {
                observer.value?.stateDidChange(call: self, state: state)
            }
        }
    }

    public var isMuted = false {
        didSet {
            AssertIsOnMainThread()

            Logger.debug("muted changed: \(oldValue) -> \(self.isMuted)")

            for observer in observers {
                observer.value?.muteDidChange(call: self, isMuted: isMuted)
            }
        }
    }

    public let audioActivity: AudioActivity

    public var audioSource: AudioSource? = nil {
        didSet {
            AssertIsOnMainThread()
            Logger.debug("audioSource changed: \(String(describing: oldValue)) -> \(String(describing: audioSource))")

            for observer in observers {
                observer.value?.audioSourceDidChange(call: self, audioSource: audioSource)
            }
        }
    }

    public var isSpeakerphoneEnabled: Bool {
        guard let audioSource = self.audioSource else {
            return false
        }

        return audioSource.isBuiltInSpeaker
    }

    public var isOnHold = false {
        didSet {
            AssertIsOnMainThread()
            Logger.debug("isOnHold changed: \(oldValue) -> \(self.isOnHold)")

            for observer in observers {
                observer.value?.holdDidChange(call: self, isOnHold: isOnHold)
            }
        }
    }

    public var connectedDate: NSDate?

    public var error: CallError?

    // MARK: Initializers and Factory Methods

    init(direction: CallDirection, localId: UUID, signalingId: UInt64, state: CallState, remoteAddress: SignalServiceAddress) {
        self.direction = direction
        self.localId = localId
        self.signalingId = signalingId
        self.state = state
        self.remoteAddress = remoteAddress
        self.thread = TSContactThread.getOrCreateThread(contactAddress: remoteAddress)
        self.audioActivity = AudioActivity(audioDescription: "[SignalCall] with \(remoteAddress)", behavior: .call)
    }

    // A string containing the three identifiers for this call.
    public var identifiersForLogs: String {
        return "{\(remoteAddress), \(localId), \(signalingId)}"
    }

    public class func outgoingCall(localId: UUID, remoteAddress: SignalServiceAddress) -> SignalCall {
        return SignalCall(direction: .outgoing, localId: localId, signalingId: newCallSignalingId(), state: .dialing, remoteAddress: remoteAddress)
    }

    public class func incomingCall(localId: UUID, remoteAddress: SignalServiceAddress, signalingId: UInt64) -> SignalCall {
        return SignalCall(direction: .incoming, localId: localId, signalingId: signalingId, state: .answering, remoteAddress: remoteAddress)
    }

    // -

    public func addObserverAndSyncState(observer: CallObserver) {
        AssertIsOnMainThread()

        observers.append(Weak(value: observer))

        // Synchronize observer with current call state
        observer.stateDidChange(call: self, state: state)
    }

    public func removeObserver(_ observer: CallObserver) {
        AssertIsOnMainThread()

        while let index = observers.firstIndex(where: { $0.value === observer }) {
            observers.remove(at: index)
        }
    }

    public func removeAllObservers() {
        AssertIsOnMainThread()

        observers = []
    }

    private func updateCallRecordType() {
        AssertIsOnMainThread()

        guard let callRecord = self.callRecord else {
            return
        }

        // Mark incomplete calls as completed if call has connected.
        if state == .connected &&
            callRecord.callType == .outgoingIncomplete {
            callRecord.updateCallType(.outgoing)
        }
        if state == .connected &&
            callRecord.callType == .incomingIncomplete {
            callRecord.updateCallType(.incoming)
        }
    }

    // MARK: Equatable

    static func == (lhs: SignalCall, rhs: SignalCall) -> Bool {
        return lhs.localId == rhs.localId
    }

    static func newCallSignalingId() -> UInt64 {
        return UInt64.ows_random()
    }

    // This method should only be called when the call state is "connected".
    public func connectionDuration() -> TimeInterval {
        return -connectedDate!.timeIntervalSinceNow
    }
}

fileprivate extension UInt64 {
    static func ows_random() -> UInt64 {
        return Cryptography.randomUInt64()
    }
}
