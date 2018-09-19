//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension UIDevice {
    var supportsCallKit: Bool {
        return ProcessInfo().isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 10, minorVersion: 0, patchVersion: 0))
    }

    @objc
    public var hasIPhoneXNotch: Bool {
        switch UIScreen.main.nativeBounds.height {
        case 960:
            //  iPad in iPhone compatibility mode (using old iPhone 4 screen size)
            return false
        case 1136:
            // iPhone 5 or 5S or 5C
            return false
        case 1334:
            // iPhone 6/6S/7/8
            return false
        case 1792:
            // iPhone XR
            return true
        case 1920, 2208:
            // iPhone 6+/6S+/7+/8+//
            return false
        case 2436:
            // iPhone X, iPhone XS
            return true
        case 2688:
            // iPhone X Max
            return true
        default:
            // Verify all our IOS_DEVICE_CONSTANT tags make sense when adding a new device size.
            owsFailDebug("unknown device format")
            return false
        }
    }

    @objc
    public var isShorterThanIPhone5: Bool {
        return UIScreen.main.bounds.height < 568
    }

    @objc
    public var isIPad: Bool {
        let isNativeIPad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.pad
        let isCompatabilityModeIPad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.phone && self.model.hasPrefix("iPad")

        return isNativeIPad || isCompatabilityModeIPad
    }
}
