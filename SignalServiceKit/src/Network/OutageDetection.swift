//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import os

@objc
public class OutageDetection: NSObject {
    @objc(sharedManager)
    public static let shared = OutageDetection()

    // These properties should only be accessed on the main thread.
    private var hasOutage = false {
        didSet {
            SwiftAssertIsOnMainThread(#function)
        }
    }
    private var mayHaveOutage = false {
        didSet {
            SwiftAssertIsOnMainThread(#function)

            ensureCheckTimer()
        }
    }

    private func checkForOutageSync() -> Bool {
        let host = CFHostCreateWithName(nil, "uptime.signal.org" as CFString).takeRetainedValue()
        CFHostStartInfoResolution(host, .addresses, nil)
        var success: DarwinBoolean = false
        guard let addresses = CFHostGetAddressing(host, &success)?.takeUnretainedValue() as NSArray? else {
            Logger.error("\(logTag) CFHostGetAddressing failed: no addresses.")
            return false
        }
        guard success.boolValue else {
            Logger.error("\(logTag) CFHostGetAddressing failed.")
            return false
        }
        var isOutageDetected = false
        for case let address as NSData in addresses {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address.bytes.assumingMemoryBound(to: sockaddr.self), socklen_t(address.length),
                           &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                let addressString = String(cString: hostname)
                if addressString != "127.0.0.1" {
                    Logger.verbose("\(logTag) addressString: \(addressString)")
                    isOutageDetected = true
                }
            }
        }
        return isOutageDetected
    }

    private func checkForOutageAsync() {
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

        if mayHaveOutage {
            if checkTimer != nil {
                // Already has timer.
                return
            }

            // The TTL of the DNS record is 60 seconds.
            checkTimer = WeakTimer.scheduledTimer(timeInterval: 60, target: self, userInfo: nil, repeats: true) { [weak self] _ in
                SwiftAssertIsOnMainThread(#function)

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
    public func reportNetworkSuccess() {
        SwiftAssertIsOnMainThread(#function)

        mayHaveOutage = true
        hasOutage = false
    }

    @objc
    public func reportNetworkFailure() {
        SwiftAssertIsOnMainThread(#function)

        mayHaveOutage = false
    }
}
