//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SystemConfiguration

public enum ReachabilityType {
    case any
    case wifi
    case cellular
}

// MARK: -

public class SSKReachability {
    // This notification is only fired if the app is ready.
    public static let owsReachabilityDidChange = Notification.Name("owsReachabilityDidChange")
}

// MARK: -

public protocol SSKReachabilityManager {
    var isReachable: Bool { get }
    func isReachable(via reachabilityType: ReachabilityType) -> Bool
}

public extension SSKReachabilityManager {
    var currentReachabilityString: String {
        guard isReachable else { return "No Connection" }
        if isReachable(via: .wifi) { return "WiFi" }
        if isReachable(via: .cellular) { return "Cellular" }
        return "Unknown (but online)"
    }

    func isReachable(with configuration: NetworkInterfaceSet) -> Bool {
        NetworkInterface.allCases.contains { interface in
            configuration.isSuperset(of: interface.singleItemSet) && isReachable(via: interface.reachabilityType)
        }
    }
}

// MARK: -

public class SSKReachabilityManagerImpl: SSKReachabilityManager {

    private struct Token {
        let isReachable: Bool
        let isReachableViaWiFi: Bool
        let isReachableViaWWAN: Bool

        static var empty: Token {
            Token(isReachable: false, isReachableViaWiFi: false, isReachableViaWWAN: false)
        }
    }

    private let backgroundSession = OWSURLSession(
        securityPolicy: OWSURLSession.signalServiceSecurityPolicy,
        configuration: .background(withIdentifier: "SSKReachabilityManagerImpl"),
        canUseSignalProxy: false,
    )

    private let reachability: SCNetworkReachability
    private let token = AtomicValue<Token>(.empty, lock: .sharedGlobal)

    public init(appReadiness: AppReadiness) {
        AssertIsOnMainThread()

        // Set up a check for connecting to IPv4 0.0.0.0, meaning "the IPv4 internet in general".
        var sockAddrRepresentingIPv4InGeneral = sockaddr_in()
        sockAddrRepresentingIPv4InGeneral.sin_len = numericCast(MemoryLayout<sockaddr_in>.size)
        sockAddrRepresentingIPv4InGeneral.sin_family = numericCast(AF_INET)
        self.reachability = withUnsafePointer(to: sockAddrRepresentingIPv4InGeneral) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)!
            }
        }

        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.configure()
        }
    }

    // MARK: -

    public var isReachable: Bool {
        isReachable(via: .any)
    }

    public func isReachable(via reachabilityType: ReachabilityType) -> Bool {
        switch reachabilityType {
        case .any:
            return token.get().isReachable
        case .wifi:
            return token.get().isReachableViaWiFi
        case .cellular:
            return token.get().isReachableViaWWAN
        }
    }

    // MARK: -

    func reachabilityChanged(newState: SCNetworkReachabilityFlags) {
        AssertIsOnMainThread()

        updateToken(newState)

        Logger.info("New preferred network: \(currentReachabilityString)")

        NotificationCenter.default.post(name: SSKReachability.owsReachabilityDidChange, object: self)

        scheduleWakeupRequestIfNecessary()
    }

    private func updateToken(_ rawFlags: SCNetworkReachabilityFlags) {
        AssertIsOnMainThread()

        // This logic was originally taken from the Reachability pod.
        // Credit to Tony Million.
        token.set(Token(
            // Don't count [.connectionRequired, .transientConnection] because (historically, according to the Reachability pod) it can happen when you toggle airplane mode on and off.
            isReachable: rawFlags.contains(.reachable) && !(rawFlags.contains(.connectionRequired) && rawFlags.contains(.transientConnection)),
            isReachableViaWiFi: rawFlags.contains(.reachable) && !rawFlags.contains(.isWWAN),
            isReachableViaWWAN: rawFlags.contains(.reachable) && rawFlags.contains(.isWWAN),
        ))
    }

    private func configure() {
        AssertIsOnMainThread()

        /// A retain-cycle breaker we can pass to `SCNetworkReachabilitySetCallback`.
        class WeakWrapper {
            weak var manager: SSKReachabilityManagerImpl?
            init(manager: SSKReachabilityManagerImpl) {
                self.manager = manager
            }
        }

        let weakWrapper = WeakWrapper(manager: self)
        var weakWrapperContext = SCNetworkReachabilityContext(
            version: 0,
            info: Unmanaged.passRetained(weakWrapper).toOpaque(),
            retain: { UnsafeRawPointer(Unmanaged<WeakWrapper>.fromOpaque($0).retain().toOpaque()) },
            release: { Unmanaged<WeakWrapper>.fromOpaque($0).release() },
            copyDescription: nil,
        )

        guard
            SCNetworkReachabilitySetDispatchQueue(reachability, .main),
            SCNetworkReachabilitySetCallback(reachability, { reachability, currentState, weakWrapperPointer in
                let weakWrapper = Unmanaged<WeakWrapper>.fromOpaque(weakWrapperPointer!).takeUnretainedValue()
                guard let manager = weakWrapper.manager else { return }
                manager.reachabilityChanged(newState: currentState)
            }, &weakWrapperContext)
        else {
            owsFailDebug("failed to start notifier")
            return
        }

        var initialState = SCNetworkReachabilityFlags()
        if SCNetworkReachabilityGetFlags(reachability, &initialState) {
            // Send an initial notification to anyone who may have registered *before* the app was ready.
            reachabilityChanged(newState: initialState)
        }

        scheduleWakeupRequestIfNecessary()
    }

    private func scheduleWakeupRequestIfNecessary() {
        AssertIsOnMainThread()

        // Start a background session to wake the app when the network
        // becomes available. We start this immediately when we lose
        // connectivity rather than waiting until the app is backgrounded,
        // because if started while backgrounded when the app is woken up
        // will be at the OSes discretion.
        guard !isReachable else { return }

        Logger.info("Scheduling wakeup request for pending message sends.")

        Task { [backgroundSession] in
            do {
                _ = try await backgroundSession.performDownload(TSConstants.mainServiceURL, method: .get, maxResponseSize: .max)
                Logger.info("Finished wakeup request.")
            } catch {
                Logger.warn("Failed wakeup request \(error)")
            }
        }
    }
}

// MARK: -

private extension NetworkInterface {
    var reachabilityType: ReachabilityType {
        switch self {
        case .cellular: return .cellular
        case .wifi: return .wifi
        }
    }
}

// MARK: -

#if TESTABLE_BUILD

public class MockSSKReachabilityManager: SSKReachabilityManager {
    public var isReachableViaWifi: Bool = false
    public var isReachableViaCellular: Bool = false

    public var isReachable: Bool {
        return isReachableViaCellular || isReachableViaWifi
    }

    public func isReachable(via reachabilityType: ReachabilityType) -> Bool {
        switch reachabilityType {
        case .wifi: return isReachableViaWifi
        case .cellular: return isReachableViaCellular
        case .any: return isReachable
        }
    }
}

#endif
