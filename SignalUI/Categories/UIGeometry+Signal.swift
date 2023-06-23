//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit

public extension UIEdgeInsets {

    func inverted() -> UIEdgeInsets {
        return UIEdgeInsets(top: -top, left: -left, bottom: -bottom, right: -right)
    }
}

public extension CGSize {

    func roundedForScreenScale() -> CGSize {
        let screenScale = UIScreen.main.scale
        guard screenScale > 1 else { return self }
        return CGSize(
            width: (width * screenScale).rounded(.up) / screenScale,
            height: (height * screenScale).rounded(.up) / screenScale
        )
    }
}

public extension CGFloat {

    static let hairlineWidth: CGFloat = 1 / UIScreen.main.scale

    static func hairlineWidthFraction(_ fraction: CGFloat) -> CGFloat {
        fraction * .hairlineWidth
    }

    private static let iPhone5ScreenWidth: CGFloat = 320

    private static let iPhone7PlusScreenWidth: CGFloat = 414

    // A convenience method for doing responsive layout. Scales between two
    // reference values (for iPhone 5 and iPhone 7 Plus) to the current device
    // based on screen width, linearly interpolating.
    static func scaleFromIPhone5To7Plus(_ iPhone5Value: CGFloat, _ iPhone7PlusValue: CGFloat) -> CGFloat {
        let shortDimension = CurrentAppContext().frame.size.smallerAxis
        let alpha = CGFloatClamp01(CGFloatInverseLerp(shortDimension, iPhone5ScreenWidth, iPhone7PlusScreenWidth))
        return CGFloatLerp(iPhone5Value, iPhone7PlusValue, alpha).rounded()
    }

    // A convenience method for doing responsive layout. Scales a reference
    // value (for iPhone 5) to the current device based on screen width,
    // linearly interpolating through the origin.
    static func scaleFromIPhone5(_ iPhone5Value: CGFloat) -> CGFloat {
        let shortDimension = CurrentAppContext().frame.size.smallerAxis
        return (iPhone5Value * shortDimension / iPhone5ScreenWidth).rounded()
    }
}
