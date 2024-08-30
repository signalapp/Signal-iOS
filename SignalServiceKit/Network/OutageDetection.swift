//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import os

public class OutageDetection {
    public static let shared = OutageDetection()

    public static let outageStateDidChange = Notification.Name("OutageStateDidChange")

    private enum OutageState {
        /// There's no reason to check for an outage.
        case doNotCheck
        /// There might be an outage, so we need to check.
        case shouldCheck(hasOutage: Bool)

        var hasOutage: Bool {
            switch self {
            case .doNotCheck: return false
            case .shouldCheck(let hasOutage): return hasOutage
            }
        }

        var shouldCheck: Bool {
            switch self {
            case .doNotCheck: return false
            case .shouldCheck: return true
            }
        }
    }

    private let _outageState = AtomicValue<OutageState>(.doNotCheck, lock: .init())

    private func updateOutageState(mutateBlock: (inout OutageState) -> Void) {
        let (oldValue, newValue) = _outageState.update { mutableState in
            let oldValue = mutableState
            mutateBlock(&mutableState)
            return (oldValue, mutableState)
        }

        if oldValue.hasOutage != newValue.hasOutage {
            Logger.info("hasOutage? \(newValue.hasOutage)")
            NotificationCenter.default.postNotificationNameAsync(OutageDetection.outageStateDidChange, object: nil)
        }

        if oldValue.shouldCheck != newValue.shouldCheck {
            DispatchQueue.main.async { self.ensureCheckTimer() }
        }
    }

    public var hasOutage: Bool { _outageState.get().hasOutage }

    // We only show the outage warning when we're certain there's an outage.
    // DNS lookup failures, etc. are not considered an outage.
    private func checkForOutageSync() -> Bool {
        let host = CFHostCreateWithName(nil, "uptime.signal.org" as CFString).takeRetainedValue()
        var resolutionError = CFStreamError()
        guard CFHostStartInfoResolution(host, .addresses, &resolutionError) else {
            Logger.warn("CFHostStartInfoResolution failed: \(resolutionError)")
            return false
        }
        var success: DarwinBoolean = false
        guard let addresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as NSArray? else {
            owsFailDebug("CFHostGetAddressing failed: nil addresses")
            return false
        }
        guard success.boolValue else {
            owsFailDebug("CFHostGetAddressing failed.")
            return false
        }
        owsAssertDebug(addresses.count > 0, "CFHostGetAddressing: empty addresses")

        var isOutageDetected = false
        for case let address as NSData in addresses {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address.bytes.assumingMemoryBound(to: sockaddr.self),
                socklen_t(address.length),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let addressString = String(cString: hostname)
                let kHealthyAddress = "127.0.0.1"
                let kOutageAddress = "127.0.0.2"
                if addressString == kHealthyAddress {
                    // Do nothing.
                } else if addressString == kOutageAddress {
                    isOutageDetected = true
                } else if addressString == "0.0.0.0" {
                    Logger.warn("unexpected address: \(addressString)")
                } else {
                    owsFailDebug("unexpected address: \(addressString)")
                }
            }
        }
        return isOutageDetected
    }

    private func checkForOutageAsync() {
        Logger.info("")

        DispatchQueue.global().async {
            let hasOutage = self.checkForOutageSync()
            self.updateOutageState { outageState in
                switch outageState {
                case .doNotCheck: break
                case .shouldCheck: outageState = .shouldCheck(hasOutage: hasOutage)
                }
            }
        }
    }

    private var checkTimer: Timer?
    private func ensureCheckTimer() {
        AssertIsOnMainThread()

        // Only monitor for outages in the main app.
        guard CurrentAppContext().isMainApp else {
            return
        }

        checkTimer?.invalidate()
        checkTimer = nil

        guard _outageState.get().shouldCheck else {
            return
        }

        // The TTL of the DNS record is 60 seconds.
        checkTimer = WeakTimer.scheduledTimer(timeInterval: 60, target: self, userInfo: nil, repeats: true) { [weak self] _ in
            AssertIsOnMainThread()

            guard CurrentAppContext().isMainAppAndActive else {
                return
            }

            self?.checkForOutageAsync()
        }
    }

    func reportConnectionSuccess() {
        self.updateOutageState { $0 = .doNotCheck }
    }

    func reportConnectionFailure() {
        self.updateOutageState { outageState in
            switch outageState {
            case .doNotCheck: outageState = .shouldCheck(hasOutage: false)
            case .shouldCheck: break
            }
        }
    }
}
