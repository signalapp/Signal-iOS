//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

extension DispatchQueue {

    public static let sharedUserInteractive: DispatchQueue = {
        return DispatchQueue(label: OWSDispatch.createLabel("sharedUserInteractive"),
                             qos: .userInteractive,
                             autoreleaseFrequency: .workItem)
    }()

    public static let sharedUserInitiated: DispatchQueue = {
        return DispatchQueue(label: OWSDispatch.createLabel("sharedUserInitiated"),
                             qos: .userInitiated,
                             autoreleaseFrequency: .workItem)
    }()

    public static let sharedUtility: DispatchQueue = {
        return DispatchQueue(label: OWSDispatch.createLabel("sharedUtility"),
                             qos: .utility,
                             autoreleaseFrequency: .workItem)
    }()

    public static let sharedBackground: DispatchQueue = {
        return DispatchQueue(label: OWSDispatch.createLabel("sharedBackground"),
                             qos: .background,
                             autoreleaseFrequency: .workItem)
    }()

    /// Returns the shared serial queue appropriate for the provided QoS
    public static func sharedQueue(at qos: DispatchQoS) -> DispatchQueue {
        switch qos {
        case .userInteractive:
            return DispatchQueue.sharedUserInteractive

        case .userInitiated:
            return DispatchQueue.sharedUserInitiated

        case .default, .utility:
            return DispatchQueue.sharedUtility

        case .background, .unspecified:
            return DispatchQueue.sharedBackground

        default:
            return DispatchQueue.sharedBackground

        }
    }
}

internal extension DispatchQoS.QoSClass {

    /// Floors a UInt32-backed qos_class_t to a valid QoSClass enum.
    init(flooring rawQoS: qos_class_t) {
        switch rawQoS.rawValue {

        case QOS_CLASS_BACKGROUND.rawValue..<QOS_CLASS_UTILITY.rawValue:
            self = .background

        case QOS_CLASS_UTILITY.rawValue..<QOS_CLASS_USER_INITIATED.rawValue:
            self = .utility

        case QOS_CLASS_USER_INITIATED.rawValue..<QOS_CLASS_USER_INTERACTIVE.rawValue:
            self = .userInitiated

        case QOS_CLASS_USER_INTERACTIVE.rawValue:
            self = .userInteractive

        default:
            // The provided QoS value is either greater than UserInteractive or less than Background
            // Fail safely to background QoS and assert.
            owsFailDebug("Invalid qos_class: \(rawQoS.rawValue). Defaulting background QoS.")
            self = .background
        }
    }
}

@objc
extension OWSDispatch {
    /// Returns the shared serial queue appropriate for the provided QoS
    public static func sharedQueue(at rawQoS: qos_class_t) -> DispatchQueue {
        let qosClass = DispatchQoS.QoSClass(flooring: rawQoS)
        let qos = DispatchQoS(qosClass: qosClass, relativePriority: 0)
        return DispatchQueue.sharedQueue(at: qos)
    }

    /// Returns a reverse-DNS queue label namespaced by appending the `suffix` to the current executable's bundleId
    public static func createLabel(_ suffix: String) -> String {
        guard let prefix = Bundle.main.bundleIdentifier else {
            owsFail("Missing bundleID")
        }
        return "\(prefix).\(suffix)"
    }
}
