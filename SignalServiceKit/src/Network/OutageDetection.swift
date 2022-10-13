//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import os
import SignalCoreKit

@objc
public class OutageDetection: NSObject {
    @objc(shared)
    public static let shared = OutageDetection()

    @objc
    public static let outageStateDidChange = Notification.Name("OutageStateDidChange")

    private let _hasOutage = AtomicBool(false)
    @objc
    public private(set) var hasOutage: Bool {
        get {
            _hasOutage.get()
        }
        set {
            let oldValue = _hasOutage.swap(newValue)

            if oldValue != newValue {
                Logger.info("hasOutage: \(oldValue) -> \(newValue).")

                NotificationCenter.default.postNotificationNameAsync(OutageDetection.outageStateDidChange, object: nil)
            }
        }
    }
    private let _shouldCheckForOutage = AtomicBool(false)
    private var shouldCheckForOutage: Bool {
        get {
            _shouldCheckForOutage.get()
        }
        set {
            let oldValue = _shouldCheckForOutage.swap(newValue)

            if oldValue != newValue {
                Logger.info("shouldCheckForOutage: \(oldValue) -> \(newValue).")

                DispatchQueue.main.async {
                    self.ensureCheckTimer()
                }
            }
        }
    }

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
            if getnameinfo(address.bytes.assumingMemoryBound(to: sockaddr.self), socklen_t(address.length),
                           &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                let addressString = String(cString: hostname)
                let kHealthyAddress = "127.0.0.1"
                let kOutageAddress = "127.0.0.2"
                if addressString == kHealthyAddress {
                    // Do nothing.
                } else if addressString == kOutageAddress {
                    isOutageDetected = true
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
            self.hasOutage = self.checkForOutageSync()
        }
    }

    private var checkTimer: Timer?
    private func ensureCheckTimer() {
        AssertIsOnMainThread()

        // Only monitor for outages in the main app.
        guard CurrentAppContext().isMainApp else {
            return
        }

        if shouldCheckForOutage {
            if checkTimer != nil {
                // Already has timer.
                return
            }

            // The TTL of the DNS record is 60 seconds.
            checkTimer?.invalidate()
            checkTimer = WeakTimer.scheduledTimer(timeInterval: 60, target: self, userInfo: nil, repeats: true) { [weak self] _ in
                AssertIsOnMainThread()

                guard CurrentAppContext().isMainAppAndActive else {
                    return
                }

                self?.checkForOutageAsync()
            }
        } else {
            checkTimer?.invalidate()
            checkTimer = nil
            self.hasOutage = false
        }
    }

    @objc
    public func reportConnectionSuccess() {
        self.shouldCheckForOutage = false
        self.hasOutage = false
    }

    @objc
    public func reportConnectionFailure() {
        self.shouldCheckForOutage = true
    }
}
