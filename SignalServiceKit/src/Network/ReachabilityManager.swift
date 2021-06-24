//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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

    var observationContext: AnyObject { get }

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
        configuration: .background(withIdentifier: "backgroundSession")
    )
    private let reachability: Reachability

    public var observationContext: AnyObject {
        return self.reachability
    }

    public var isReachable: Bool {
        return isReachable(via: .any)
    }

    public func isReachable(via reachabilityType: ReachabilityType) -> Bool {
        switch reachabilityType {
        case .any:
            return reachability.isReachable()
        case .wifi:
            return reachability.isReachableViaWiFi()
        case .cellular:
            return reachability.isReachableViaWWAN()
        }
    }

    @objc
    override public init() {
        self.reachability = Reachability.forInternetConnection()

        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.configure()
        }
    }

    private func configure() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reachabilityChanged),
                                               name: .reachabilityChanged,
                                               object: self.observationContext)

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

        NotificationCenter.default.post(name: SSKReachability.owsReachabilityDidChange, object: self.observationContext)

        scheduleWakeupRequestIfNecessary()
    }

    private func startNotifier() {
        guard AppReadiness.isAppReady else {
            owsFailDebug("App is unexpectedly not ready.")
            return
        }
        guard reachability.startNotifier() else {
            owsFailDebug("failed to start notifier")
            return
        }
        Logger.debug("started notifier")

        scheduleWakeupRequestIfNecessary()
    }

    private func scheduleWakeupRequestIfNecessary() {
        // Start a background session to wake the app when the network
        // becomes available. We start this immediately when we lose
        // connectivity rather than waiting until the app is backgrounded,
        // because if started while backgrounded when the app is woken up
        // will be at the OSes discretion.
        guard !isReachable else { return }

        Logger.info("Scheduling wakeup request for pending message sends.")

        backgroundSession.urlDownloadTaskPromise(TSConstants.textSecureServerURL, method: .get).done { _ in
            Logger.info("Finished wakeup request.")
        }.catch { error in
            Logger.info("Failed wakeup request \(error)")
        }
    }
}

private extension NetworkInterface {
    var reachabilityType: ReachabilityType {
        switch self {
        case .cellular: return .cellular
        case .wifi: return .wifi
        }
    }
}
