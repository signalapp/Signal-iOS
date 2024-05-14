//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

protocol CallServiceStateObserver: AnyObject {
    /// Fired on the main thread when the current call changes.
    func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?)
}

protocol CallServiceStateDelegate: AnyObject {
    func callServiceState(_ callServiceState: CallServiceState, didTerminateCall call: SignalCall)
}

class CallServiceState {
    weak var delegate: CallServiceStateDelegate?

    init(currentCall: AtomicValue<SignalCall?>) {
        self._currentCall = currentCall
    }

    /// Current call *must* be set on the main thread. It may be read off the
    /// main thread if the current call state must be consulted, but other call
    /// state may race (observer state, sleep state, etc.)
    private let _currentCall: AtomicValue<SignalCall?>

    /// Represents the call currently occuring on this device.
    private(set) var currentCall: SignalCall? {
        get { _currentCall.get() }
        set {
            AssertIsOnMainThread()

            let oldValue = _currentCall.swap(newValue)

            guard newValue !== oldValue else {
                return
            }

            if let newValue {
                assert(activeOrPendingCalls.contains(where: { $0 === newValue }))
            }

            for observer in self.observers.elements {
                observer.didUpdateCall(from: oldValue, to: newValue)
            }
        }
    }

    func setCurrentCall(_ currentCall: SignalCall) {
        self.currentCall = currentCall
    }

    /// True whenever CallService has any call in progress.
    /// The call may not yet be visible to the user if we are still in the middle of signaling.
    public var hasActiveOrPendingCall: Bool {
        return !activeOrPendingCalls.isEmpty
    }

    /// Track all calls that are currently "in play". Usually this is 1 or 0, but when dealing
    /// with a rapid succession of calls, it's possible to have multiple.
    ///
    /// For example, if the client receives two call offers, we hand them both off to RingRTC,
    /// which will let us know which one, if any, should become the "current call". But in the
    /// meanwhile, we still want to track that calls are in-play so we can prevent the user from
    /// placing an outgoing call.
    private let _activeOrPendingCalls = AtomicValue<[SignalCall]>([], lock: .init())
    var activeOrPendingCalls: [SignalCall] { _activeOrPendingCalls.get() }

    func addCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        _activeOrPendingCalls.update { $0.append(call) }
        postActiveCallsDidChange()
    }

    func removeCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        _activeOrPendingCalls.update { $0.removeAll(where: { $0 === call }) }
        postActiveCallsDidChange()
    }

    public static let activeCallsDidChange = Notification.Name("activeCallsDidChange")

    private func postActiveCallsDidChange() {
        NotificationCenter.default.postNotificationNameAsync(Self.activeCallsDidChange, object: self)
    }

    /**
     * Clean up any existing call state and get ready to receive a new call.
     */
    func terminateCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call as Optional)")

        // If call is for the current call, clear it out first.
        if call === currentCall { currentCall = nil }

        removeCall(call)

        switch call.mode {
        case .individual:
            break
        case .group(let groupCall):
            groupCall.leave()
            groupCall.disconnect()
        }

        delegate?.callServiceState(self, didTerminateCall: call)
    }

    // MARK: - Observers

    private var observers = WeakArray<any CallServiceStateObserver>()

    func addObserver(_ observer: any CallServiceStateObserver, syncStateImmediately: Bool = false) {
        AssertIsOnMainThread()

        observers.append(observer)

        if syncStateImmediately {
            // Synchronize observer with current call state
            observer.didUpdateCall(from: nil, to: currentCall)
        }
    }

    // The observer-related methods should be invoked on the main thread.
    func removeObserver(_ observer: any CallServiceStateObserver) {
        AssertIsOnMainThread()
        observers.removeAll { $0 === observer }
    }
}
