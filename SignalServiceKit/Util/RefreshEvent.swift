//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// This class can be used to coordinate the refresh of a
// value obtained from the network.

@MainActor
final public class RefreshEvent {
    private let block: @MainActor () -> Void

    private let refreshInterval: TimeInterval

    private var refreshTimer: Timer?

    private let appReadiness: AppReadiness

    // The block will be performed with a rough frequency of refreshInterval.
    //
    // It will not be performed if the app isn't ready, the user isn't registered,
    // if the app isn't the main app, if the app isn't active.
    //
    // It will also be performed immediately if any of the conditions change.
    public init(
        appReadiness: AppReadiness,
        refreshInterval: TimeInterval,
        block: @escaping @MainActor () -> Void,
    ) {
        self.appReadiness = appReadiness
        self.refreshInterval = refreshInterval
        self.block = block

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync { [weak self] in
            self?.ensureRefreshTimer()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fireEvent),
            name: SSKReachability.owsReachabilityDidChange,
            object: nil)
    }

    private var canFire: Bool {
        guard
            appReadiness.isAppReady,
            CurrentAppContext().isMainAppAndActive,
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
        else {
            return false
        }
        return true
    }

    @objc
    private func fireEvent() {
        guard canFire else {
            return
        }
        block()
    }

    @objc
    private func didEnterBackground() {
        AssertIsOnMainThread()

        ensureRefreshTimer()
    }

    @objc
    private func didBecomeActive() {
        AssertIsOnMainThread()

        ensureRefreshTimer()
    }

    private func ensureRefreshTimer() {
        guard canFire else {
            stopRefreshTimer()
            return
        }
        startRefreshTimer()
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else {
            return
        }
        refreshTimer = WeakTimer.scheduledTimer(
            timeInterval: refreshInterval,
            target: self,
            userInfo: nil,
            repeats: true,
            action: { [weak self] _ in self?.fireEvent() },
        )
        fireEvent()
    }
}
