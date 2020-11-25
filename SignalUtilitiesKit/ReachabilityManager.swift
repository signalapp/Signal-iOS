//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import Reachability

@objc
public class SSKReachabilityManagerImpl: NSObject, SSKReachabilityManager {

    public let reachability: Reachability
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
    }

    @objc
    public func setup() {
        guard reachability.startNotifier() else {
            owsFailDebug("failed to start notifier")
            return
        }
        Logger.debug("started notifier")
    }
}
