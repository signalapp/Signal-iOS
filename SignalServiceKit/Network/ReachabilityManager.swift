//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Reachability

public enum ReachabilityType {
    case any, wifi, cellular
}

// MARK: -

final public class SSKReachability {
    // Unlike reachabilityChanged, this notification is only fired:
    //
    // * If the app is ready.
    // * If the app is not in the background.
    public static let owsReachabilityDidChange = Notification.Name("owsReachabilityDidChange")
}

// MARK: -

public protocol SSKReachabilityManager {

    var isReachable: Bool { get }

    func isReachable(via reachabilityType: ReachabilityType) -> Bool
}

public extension SSKReachabilityManager {
    func isReachable(with configuration: NetworkInterfaceSet) -> Bool {
        NetworkInterface.allCases.contains { interface in
            configuration.isSuperset(of: interface.singleItemSet) && isReachable(via: interface.reachabilityType)
        }
    }
}

// MARK: -

final public class SSKReachabilityManagerImpl: SSKReachabilityManager {

    private let backgroundSession = OWSURLSession(
        securityPolicy: OWSURLSession.signalServiceSecurityPolicy,
        configuration: .background(withIdentifier: "SSKReachabilityManagerImpl"),
        canUseSignalProxy: false
    )

    // This property should only be accessed on the main thread.
    private let reachability: Reachability

    private struct Token {
        let isReachable: Bool
        let isReachableViaWiFi: Bool
        let isReachableViaWWAN: Bool

        static var empty: Token {
            Token(isReachable: false, isReachableViaWiFi: false, isReachableViaWWAN: false)
        }
    }
    private let token = AtomicValue<Token>(.empty, lock: .sharedGlobal)

    // This property can be safely accessed from any thread.
    public var isReachable: Bool {
        isReachable(via: .any)
    }

    // This method can be safely called from any thread.
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

    private let appReadiness: AppReadiness

    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        AssertIsOnMainThread()

        self.reachability = Reachability.forInternetConnection()

        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.configure()
        }
    }

    private func updateToken() {
        AssertIsOnMainThread()

        token.set(Token(isReachable: reachability.isReachable(),
                        isReachableViaWiFi: reachability.isReachableViaWiFi(),
                        isReachableViaWWAN: reachability.isReachableViaWWAN()))
    }

    private func configure() {
        AssertIsOnMainThread()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reachabilityChanged),
                                               name: .reachabilityChanged,
                                               object: nil)

        startNotifier()
    }

    @objc
    func reachabilityChanged() {
        AssertIsOnMainThread()

        guard appReadiness.isAppReady else {
            owsFailDebug("App is unexpectedly not ready.")
            return
        }

        updateToken()

        NotificationCenter.default.post(name: SSKReachability.owsReachabilityDidChange, object: self)

        scheduleWakeupRequestIfNecessary()
    }

    private func startNotifier() {
        AssertIsOnMainThread()

        guard appReadiness.isAppReady else {
            owsFailDebug("App is unexpectedly not ready.")
            return
        }
        guard reachability.startNotifier() else {
            owsFailDebug("failed to start notifier")
            return
        }

        updateToken()

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
                _ = try await backgroundSession.performDownload(TSConstants.mainServiceIdentifiedURL, method: .get)
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

final public class MockSSKReachabilityManager: SSKReachabilityManager {
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
