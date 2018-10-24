//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@objc
public protocol OWSProximityMonitoringManager: class {
    func add(lifetime: AnyObject)
    func remove(lifetime: AnyObject)
}

@objc
public class OWSProximityMonitoringManagerImpl: NSObject, OWSProximityMonitoringManager {
    var lifetimes: [Weak<AnyObject>] = []
    let serialQueue = DispatchQueue(label: "ProximityMonitoringManagerImpl")

    // MARK: 

    var device: UIDevice {
        return UIDevice.current
    }

    // MARK: 

    @objc
    public func add(lifetime: AnyObject) {
        serialQueue.sync {
            if !lifetimes.contains { $0.value === lifetime } {
                lifetimes.append(Weak(value: lifetime))
            }
            reconcile()
        }
    }

    @objc
    public func remove(lifetime: AnyObject) {
        serialQueue.sync {
            lifetimes = lifetimes.filter { $0.value !== lifetime }
            reconcile()
        }
    }

    func reconcile() {
        if _isDebugAssertConfiguration() {
            assertOnQueue(serialQueue)
        }
        lifetimes = lifetimes.filter { $0.value != nil }
        if lifetimes.isEmpty {
            Logger.debug("disabling proximity monitoring")
            device.isProximityMonitoringEnabled = false
        } else {
            Logger.debug("enabling proximity monitoring for lifetimes: \(lifetimes)")
            device.isProximityMonitoringEnabled = true
        }
    }
}
