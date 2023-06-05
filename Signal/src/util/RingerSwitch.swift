//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

protocol RingerSwitchObserver: AnyObject {
    func didToggleRingerSwitch(_ isSilenced: Bool)
}

class RingerSwitch {
    static let shared = RingerSwitch()

    private init() {}

    deinit {
        stopObserving()
    }

    private var observers: [Weak<RingerSwitchObserver>] = []

    // MARK: API

    /// Begins observing and immediately returns the current ringer state value.
    @discardableResult
    func addObserver(observer: RingerSwitchObserver) -> Bool {
        AssertIsOnMainThread()

        if !observers.contains(where: { $0.value === observer }) {
            observers.append(Weak(value: observer))
        } else {
            owsFailDebug("Adding a ringer switch observer more than once.")
        }

        return startObserving()
    }

    func removeObserver(_ observer: RingerSwitchObserver) {
        AssertIsOnMainThread()

        observers = observers.filter { $0.value != nil && $0.value !== observer }

        guard observers.isEmpty else { return }
        stopObserving()
    }

    // MARK: Notifying

    private func notifyObservers(isSilenced: Bool) {
        observers.forEach { observer in
            observer.value?.didToggleRingerSwitch(isSilenced)
        }

        // Clear out released observers and stop observing if empty.
        observers = observers.filter { $0.value != nil }
        guard observers.isEmpty else { return }
        stopObserving()
    }

    // MARK: Listening

    // let encodedDarwinNotificationName = "com.apple.springboard.ringerstate".encodedForSelector
    private static let ringerStateNotificationName = DarwinNotificationName("dAF+P3ICAn12PwUCBHoAeHMBcgR1PwR6AHh2BAUGcgZ2".decodedForSelector!)

    private var ringerStateToken: Int32?

    private var isSilenced: Bool? {
        guard let ringerStateToken = ringerStateToken else {
            return nil
        }
        return isRingerStateSilenced(token: ringerStateToken)
    }

    private func startObserving() -> Bool {
        if let ringerStateToken = ringerStateToken {
            // Already observing.
            return isRingerStateSilenced(token: ringerStateToken)
        }
        let token = DarwinNotificationCenter.addObserver(
            for: Self.ringerStateNotificationName,
            queue: .main
        ) { [weak self] token in
            guard let strongSelf = self else {
                return
            }
            strongSelf.notifyObservers(isSilenced: strongSelf.isRingerStateSilenced(token: token))

        }
        ringerStateToken = token
        return isRingerStateSilenced(token: token)
    }

    private func stopObserving() {
        guard let ringerStateToken = ringerStateToken else { return }
        DarwinNotificationCenter.removeObserver(ringerStateToken)
        self.ringerStateToken = nil
    }

    private func isRingerStateSilenced(token: Int32) -> Bool {
        return DarwinNotificationCenter.getStateForObserver(token) > 0 ? false : true
    }
}
