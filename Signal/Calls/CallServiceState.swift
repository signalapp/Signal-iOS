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

            for observer in self.observers.elements {
                observer.didUpdateCall(from: oldValue, to: newValue)
            }
        }
    }

    func setCurrentCall(_ currentCall: SignalCall) {
        self.currentCall = currentCall
    }

    /**
     * Clean up any existing call state and get ready to receive a new call.
     */
    func terminateCall(_ call: SignalCall) {
        AssertIsOnMainThread()
        Logger.info("call: \(call as Optional)")

        // If call is for the current call, clear it out first.
        if call === currentCall {
            currentCall = nil
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
