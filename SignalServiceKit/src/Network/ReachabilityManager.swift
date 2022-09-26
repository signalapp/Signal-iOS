//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import Reachability

@objc(SSKReachabilityType)
public enum ReachabilityType: Int {
    case any, wifi, cellular
}

// MARK: -

@objc
public class SSKReachability: NSObject {
    // Unlike reachabilityChanged, this notification is only fired:
    //
    // * If the app is ready.
    // * If the app is not in the background.
    @objc
    public static let owsReachabilityDidChange = Notification.Name("owsReachabilityDidChange")
}

// MARK: -

@objc
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

@objc
public class SSKReachabilityManagerImpl: NSObject, SSKReachabilityManager {

    private let backgroundSession = OWSURLSession(
        securityPolicy: OWSURLSession.signalServiceSecurityPolicy,
        configuration: .background(withIdentifier: "SSKReachabilityManagerImpl"),
        canUseSignalProxy: true
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
    private let token = AtomicValue<Token>(.empty)

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

    @objc
    override public init() {
        AssertIsOnMainThread()

        self.reachability = Reachability.forInternetConnection()

        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
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

        guard AppReadiness.isAppReady else {
            owsFailDebug("App is unexpectedly not ready.")
            return
        }

        Logger.verbose("isReachable: \(isReachable)")

        updateToken()

        NotificationCenter.default.post(name: SSKReachability.owsReachabilityDidChange, object: nil)

        scheduleWakeupRequestIfNecessary()
    }

    private func startNotifier() {
        AssertIsOnMainThread()

        guard AppReadiness.isAppReady else {
            owsFailDebug("App is unexpectedly not ready.")
            return
        }
        guard reachability.startNotifier() else {
            owsFailDebug("failed to start notifier")
            return
        }
        Logger.debug("started notifier")

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

        firstly {
            backgroundSession.downloadTaskPromise(TSConstants.mainServiceURL, method: .get)
        }.done(on: .global()) { _ in
            Logger.info("Finished wakeup request.")
        }.catch(on: .global()) { error in
            Logger.info("Failed wakeup request \(error)")
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

@objc
public class MockSSKReachabilityManager: NSObject, SSKReachabilityManager {
    public var isReachable: Bool = false
    public func isReachable(via reachabilityType: ReachabilityType) -> Bool { isReachable }
}

#endif
