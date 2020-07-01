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
    case remoteHangupNeedPermission // terminal
    case remoteBusy // terminal
    case answeredElsewhere // terminal
    case declinedElsewhere // terminal
    case busyElsewhere // terminal
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
    case disconnected
    case externalError(underlyingError: Error)
    case timeout(description: String)
    case messageSendFailure(underlyingError: Error)
}

/**
 * Data model for a WebRTC backed voice/video call.
 *
 * This class' state should only be accessed on the main queue.
 */
@objc
public class SignalCall: NSObject, SignalCallNotificationInfo {

    // Mark -

    var backgroundTask: OWSBackgroundTask? {
        didSet {
            AssertIsOnMainThread()

            Logger.info("")
        }
    }

    var callId: UInt64? {
        didSet {
            AssertIsOnMainThread()

            Logger.info("")
        }
    }

    weak var localCaptureSession: AVCaptureSession? {
        didSet {
            AssertIsOnMainThread()

            Logger.info("")
        }
    }

    weak var remoteVideoTrack: RTCVideoTrack? {
        didSet {
            AssertIsOnMainThread()

            Logger.info("")
        }
    }

    var isRemoteVideoEnabled = false {
        didSet {
            AssertIsOnMainThread()

            Logger.info("\(isRemoteVideoEnabled)")
        }
    }

    // MARK: -

    // tracking cleanup
    var wasReportedToSystem = false
    var wasRemovedFromSystem = false
    var didCallTerminate = false

    public func terminate() {
        AssertIsOnMainThread()

        Logger.debug("")
        assert(!didCallTerminate)
        didCallTerminate = true

        removeAllObservers()
    }

    var observers: WeakArray<CallObserver> = []

    @objc
    public let remoteAddress: SignalServiceAddress

    public var isEnded: Bool {
        switch state {
        case .localFailure, .localHangup, .remoteHangup, .remoteHangupNeedPermission, .remoteBusy, .answeredElsewhere, .declinedElsewhere, .busyElsewhere:
            return true
        case .idle, .dialing, .answering, .remoteRinging, .localRinging, .connected, .reconnecting:
            return false
        }
    }

    public let direction: CallDirection

    // Distinguishes between calls locally, e.g. in CallKit
    @objc
    public let localId: UUID

    public let thread: TSContactThread

    public let sentAtTimestamp: UInt64

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

            for observer in observers.elements {
                observer.hasLocalVideoDidChange(call: self, hasLocalVideo: hasLocalVideo)
            }
        }
    }

    public var state: CallState {
        didSet {
            AssertIsOnMainThread()
            Logger.debug("state changed: \(oldValue) -> \(self.state) for call: \(self)")

            // Update connectedDate
            if case .connected = self.state {
                // if it's the first time we've connected (not a reconnect)
                if connectedDate == nil {
                    connectedDate = NSDate()
                }
            }

            updateCallRecordType()

            for observer in observers.elements {
                observer.stateDidChange(call: self, state: state)
            }
        }
    }

    public var isMuted = false {
        didSet {
            AssertIsOnMainThread()

            Logger.debug("muted changed: \(oldValue) -> \(self.isMuted)")

            for observer in observers.elements {
                observer.muteDidChange(call: self, isMuted: isMuted)
            }
        }
    }

    public let audioActivity: AudioActivity

    public var audioSource: AudioSource? = nil {
        didSet {
            AssertIsOnMainThread()
            Logger.debug("audioSource changed: \(String(describing: oldValue)) -> \(String(describing: audioSource))")

            for observer in observers.elements {
                observer.audioSourceDidChange(call: self, audioSource: audioSource)
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

            for observer in observers.elements {
                observer.holdDidChange(call: self, isOnHold: isOnHold)
            }
        }
    }

    public var connectedDate: NSDate?

    public var error: CallError?

    // MARK: Initializers and Factory Methods

    init(direction: CallDirection, localId: UUID, state: CallState, remoteAddress: SignalServiceAddress, sentAtTimestamp: UInt64) {
        self.direction = direction
        self.localId = localId
        self.state = state
        self.remoteAddress = remoteAddress
        self.thread = TSContactThread.getOrCreateThread(contactAddress: remoteAddress)
        self.audioActivity = AudioActivity(audioDescription: "[SignalCall] with \(remoteAddress)", behavior: .call)
        self.sentAtTimestamp = sentAtTimestamp
    }

    deinit {
        Logger.debug("")
        if !isEnded {
            owsFailDebug("isEnded was unexpectedly false")
        }
        if !didCallTerminate {
            owsFailDebug("didCallTerminate was unexpectedly false")
        }
        if wasReportedToSystem {
            if !wasRemovedFromSystem {
                owsFailDebug("wasRemovedFromSystem was unexpectedly false")
            }
        } else {
            if wasRemovedFromSystem {
                owsFailDebug("wasRemovedFromSystem was unexpectedly true")
            }
        }
    }

    override public var description: String {
        return "SignalCall: {\(remoteAddress), localId: \(localId), signalingId: \(callId as Optional)))}"
    }

    public class func outgoingCall(localId: UUID, remoteAddress: SignalServiceAddress) -> SignalCall {
        return SignalCall(direction: .outgoing, localId: localId, state: .dialing, remoteAddress: remoteAddress, sentAtTimestamp: Date.ows_millisecondTimestamp())
    }

    public class func incomingCall(localId: UUID, remoteAddress: SignalServiceAddress, sentAtTimestamp: UInt64) -> SignalCall {
        return SignalCall(direction: .incoming, localId: localId, state: .answering, remoteAddress: remoteAddress, sentAtTimestamp: sentAtTimestamp)
    }

    // -

    public func addObserverAndSyncState(observer: CallObserver) {
        AssertIsOnMainThread()

        observers.append(observer)

        // Synchronize observer with current call state
        observer.stateDidChange(call: self, state: state)
    }

    public func removeObserver(_ observer: CallObserver) {
        AssertIsOnMainThread()

        observers.removeAll { $0 === observer }
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

    // This method should only be called when the call state is "connected".
    public func connectionDuration() -> TimeInterval {
        return -connectedDate!.timeIntervalSinceNow
    }
}
