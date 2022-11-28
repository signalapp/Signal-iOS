//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import os.signpost

/**
 This class defines the monitoring interface of the framework.

 "struct" must be accessible from objc, so we have to use a derived NSObject class
 */
@objc
public class InstrumentsMonitor: NSObject {

    /**
     The interface definition to be implemented for a monitor start.
     - Parameter : category
     - Parameter : group
     - Parameter : name
     */
    public typealias StartSpanInterface = (String, String?, String) -> UInt64?

    /**
     The interface definition to be implemented for a monitor start.
     - Parameter : category
     - Parameter : OSSignPostID
     - Parameter : success
     - Parameter : array of additional result infos
     */
    public typealias StopSpanInterface = (String, UInt64, Bool?, [String]) -> Void

    /**
     Defines the tracker start implementation to be used by the framework.
     */
    public static var start: StartSpanInterface?

    /**
    Defines the tracker end implementation to be used by the framework.
    */
    public static var stop: StopSpanInterface?

    @usableFromInline internal static let SUBSYSTEM = "org.whispersystems.signal"

    @objc
    public static func enable() {
        #if TESTABLE_BUILD
        let environment = ProcessInfo.processInfo.environment["OS_ACTIVITY_MODE"]
        if environment == nil || environment!.lowercased() != "disable" {
            InstrumentsMonitor.start = InstrumentsMonitor.defaultStartImplementation
            InstrumentsMonitor.stop = InstrumentsMonitor.defaultStopImplementation
            InstrumentsMonitor.trackEvent(name: "Start Instrumentation")
        }
        #endif
    }

    public static let defaultStartImplementation: StartSpanInterface? = { (category: String, parent: String?, name: String) -> UInt64? in
        let log = OSLog(subsystem: SUBSYSTEM, category: category)
        let signpostID = OSSignpostID(log: log)
        var thread = Thread.current.debugDescription
        thread += ", Prio \(Thread.current.threadPriority) (qos: "
        switch Thread.current.qualityOfService {
        case .userInteractive:
            thread += "userInteractive"
        case .userInitiated:
            thread += "userInitiated"
        case .utility:
            thread += "utility"
        case .background:
            thread += "background"
        case .default:
            thread += "default"
        default:
            thread += "\(Thread.current.qualityOfService.rawValue)"
        }
        thread += ")"
        var params = [Thread.current.isMainThread ? "Main" : "Background", thread, name]
        if let parent = parent {
            params.append(parent)
        }
        send(.begin, to: log, id: signpostID, params: params)
        return signpostID.rawValue
    }

    public static let defaultStopImplementation: StopSpanInterface? = { (category: String, hash: UInt64, success: Bool?, params: [String]) in
        var params = params
        if let success = success {
            params.insert(success ? "1" : "0", at: 0)
        }
        send(.end, to: OSLog(subsystem: SUBSYSTEM, category: category), id: OSSignpostID(hash), params: params)
    }

    // @inlinable allows the call to be compiled out in non-testable builds where it does nothing.
    @objc
    @inlinable
    public static func trackEvent(name s: String) {
        #if TESTABLE_BUILD
        let log = OSLog(subsystem: SUBSYSTEM, category: OSLog.Category.pointsOfInterest)
        os_signpost(.event, log: log, name: "trackEvent", signpostID: OSSignpostID(log: log), "%{private}s", s)
        #endif
    }

    public static func startSpan(category: String, parent: String? = nil, name: String) -> UInt64? {
        return start?(category, parent, name)
    }

    public static func stopSpan(category: String, hash: UInt64?, success: Bool? = nil, _ values: Any...) {
        if let stop = stop, let hash = hash {
            var params: [String] = []
            for v in values {
                flatAppend(v, to: &params)
            }
            stop(category, hash, success, params)
        }
    }

    // @inlinable allows the call to be compiled out in non-testable builds where it does nothing.
    @inlinable
    public static func measure<T>(category: String, parent: String? = nil, name: String, block: () throws -> T) rethrows -> T {
#if TESTABLE_BUILD
        // swiftlint:disable inert_defer
        let monitorId = startSpan(category: category, parent: parent, name: name)
        defer {
            stopSpan(category: category, hash: monitorId)
        }
        // swiftlint:enable inert_defer
#endif
        return try block()
    }

    @objc
    public static func startSpan(category: String, name: String) -> UInt64 {
        return start?(category, nil, name) ?? 0
    }

    @objc
    public static func startSpan(category: String, parent: String, name: String) -> UInt64 {
        return start?(category, parent, name) ?? 0
    }

    @objc
    public static func stopSpan(category: String, hash: UInt64) {
        stop?(category, hash, nil, [])
    }

    @objc
    public static func stopSpan(category: String, hash: UInt64, param: String) {
        stop?(category, hash, nil, [param])
    }

    @objc
    public static func measure(category: String, parent: String, name: String, block: () -> Void) {
        let monitorId = startSpan(category: category, parent: parent, name: name)
        defer {
            stopSpan(category: category, hash: monitorId)
        }
        block()
    }

    // MARK: - private helper

    fileprivate static func flatAppend(_ v: Any, to params: inout [String]) {
        if let s = v as? String {
            params.append(s)
        } else if let i = v as? Int {
            params.append(String(i))
        } else if let i = v as? Int64 {
            params.append(String(i))
        } else if let d = v as? Double {
            params.append(String(d))
        } else if let a = v as? [Any] {
            for w in a {
                flatAppend(w, to: &params)
            }
        } else {
            owsFailDebug("*** can't convert \(v)")
        }
    }

    fileprivate static func send(_ type: OSSignpostType, to log: OSLog, id: OSSignpostID, params: [String]) {
        let NAME = StaticString("entry")
        let formatString = getStaticFormat(for: type, parameters: params.count)
        switch params.count {
        case 0:
            os_signpost(type, log: log, name: NAME, signpostID: id)
        case 1:
            os_signpost(type, log: log, name: NAME, signpostID: id, formatString, params[0])
        case 2:
            os_signpost(type, log: log, name: NAME, signpostID: id, formatString, params[0], params[1])
        case 3:
            os_signpost(type, log: log, name: NAME, signpostID: id, formatString, params[0], params[1], params[2])
        case 4:
            os_signpost(type, log: log, name: NAME, signpostID: id, formatString, params[0], params[1], params[2], params[3])
        case 5:
            os_signpost(type, log: log, name: NAME, signpostID: id, formatString, params[0], params[1], params[2], params[3], params[4])
        default:
            owsFailDebug("*** did not implement send for \(params.count) parameter")
        }
    }

    fileprivate static func getStaticFormat(for type: OSSignpostType, parameters: Int) -> StaticString {
        if type == .begin {
            switch parameters {
            case 2:
                return "%{private}s-Thread:%{private}s"
            case 3:
                return "%{private}s-Thread:%{private}s|%{private}s"
            case 4:
                return "%{private}s-Thread:%{private}s|%{private}s|%{private}s"
            default:
                return ""
            }
        } else if type == .end {
            switch parameters {
            case 1:
                return "%{private}s"
            case 2:
                return "%{private}s|%{private}s"
            case 3:
                return "%{private}s|%{private}s|%{private}s"
            case 4:
                return "%{private}s|%{private}s|%{private}s|%{private}s"
            case 5:
                return "%{private}s|%{private}s|%{private}s|%{private}s|%{private}s"
            default:
                return ""
            }
        }
        return ""
    }
}
