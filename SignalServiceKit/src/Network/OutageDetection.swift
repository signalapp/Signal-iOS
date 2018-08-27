//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import os

@objc
public class OutageDetection: NSObject {
    @objc(sharedManager)
    public static let shared = OutageDetection()

    @objc public static let outageStateDidChange = Notification.Name("OutageStateDidChange")

    // These properties should only be accessed on the main thread.
    @objc
    public var hasOutage = false {
        didSet {
            AssertIsOnMainThread()

            if hasOutage != oldValue {
                Logger.info("hasOutage: \(hasOutage).")

                NotificationCenter.default.postNotificationNameAsync(OutageDetection.outageStateDidChange, object: nil)
            }
        }
    }
    private var shouldCheckForOutage = false {
        didSet {
            AssertIsOnMainThread()

            ensureCheckTimer()
        }
    }

    // We only show the outage warning when we're certain there's an outage.
    // DNS lookup failures, etc. are not considered an outage.
    private func checkForOutageSync() -> Bool {
        let host = CFHostCreateWithName(nil, "uptime.signal.org" as CFString).takeRetainedValue()
        CFHostStartInfoResolution(host, .addresses, nil)
        var success: DarwinBoolean = false
        guard let addresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as NSArray? else {
            Logger.error("CFHostGetAddressing failed: no addresses.")
            return false
        }
        guard success.boolValue else {
            Logger.error("CFHostGetAddressing failed.")
            return false
        }
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
            let isOutageDetected = self.checkForOutageSync()
            DispatchQueue.main.async {
                self.hasOutage = isOutageDetected
            }
        }
    }

    private var checkTimer: Timer?
    private func ensureCheckTimer() {
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
            checkTimer = WeakTimer.scheduledTimer(timeInterval: 60, target: self, userInfo: nil, repeats: true) { [weak self] _ in
                AssertIsOnMainThread()

                guard CurrentAppContext().isMainAppAndActive else {
                    return
                }

                guard let strongSelf = self else {
                    return
                }

                strongSelf.checkForOutageAsync()
            }
        } else {
            checkTimer?.invalidate()
            checkTimer = nil
        }
    }

    @objc
    public func reportConnectionSuccess() {
        DispatchMainThreadSafe {
            self.shouldCheckForOutage = false
            self.hasOutage = false
        }
    }

    @objc
    public func reportConnectionFailure() {
        DispatchMainThreadSafe {
            self.shouldCheckForOutage = true
        }
    }
}
