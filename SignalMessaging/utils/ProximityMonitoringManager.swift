//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public protocol OWSProximityMonitoringManager: AnyObject {
    func add(lifetime: AnyObject)
    func remove(lifetime: AnyObject)
}

public class OWSProximityMonitoringManagerImpl: OWSProximityMonitoringManager {

    private struct State {
        var didAddObserver = false
        var lifetimes = [Weak<AnyObject>]()
    }
    private var state = AtomicValue(State(), lock: AtomicLock())

    public func add(lifetime: AnyObject) {
        guard !CurrentAppContext().isNSE else {
            return
        }
        updateState { state in
            if state.lifetimes.contains(where: { $0.value === lifetime }) {
                return
            }
            state.lifetimes.append(Weak(value: lifetime))
        }
    }

    public func remove(lifetime: AnyObject) {
        guard !CurrentAppContext().isNSE else {
            return
        }
        updateState { state in
            state.lifetimes = state.lifetimes.filter { $0.value !== lifetime }
        }
    }

    private func updateState(block: (inout State) -> Void) {
        state.update { mutableState in
            let oldEnabled = !mutableState.lifetimes.isEmpty
            block(&mutableState)
            mutableState.lifetimes = mutableState.lifetimes.filter { $0.value !== nil }
            let newEnabled = !mutableState.lifetimes.isEmpty

            if oldEnabled == newEnabled {
                return
            }
            didChangeEnabled(newValue: newEnabled, state: &mutableState)
        }
    }

    @objc
    private func proximitySensorStateDidChange(notification: Notification) {
        Logger.debug("")
        // This is crazy, but if we disable `device.isProximityMonitoringEnabled`
        // while `device.proximityState` is true (while the device is held to the
        // ear) then `device.proximityState` remains true, even after we bring the
        // phone away from the ear and re-enable monitoring.
        //
        // To resolve this, we wait to disable proximity monitoring until
        // `proximityState` is false.
        if UIDevice.current.proximityState {
            self.add(lifetime: self)
        } else {
            self.remove(lifetime: self)
        }
    }

    private func didChangeEnabled(newValue: Bool, state: inout State) {
        Logger.debug("Proximity monitoring changed to \(newValue)")

        if newValue, !state.didAddObserver {
            state.didAddObserver = true
            DispatchQueue.main.async {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(self.proximitySensorStateDidChange(notification:)),
                    name: UIDevice.proximityStateDidChangeNotification,
                    object: nil
                )
            }
        }

        DispatchQueue.main.async {
            UIDevice.current.isProximityMonitoringEnabled = newValue
        }
    }
}
