//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public extension UIEdgeInsets {

    func inverted() -> UIEdgeInsets {
        return UIEdgeInsets(top: -top, left: -left, bottom: -bottom, right: -right)
    }
}

public extension CGSize {

    var isLandscape: Bool {
        aspectRatio >= 1
    }

    var isPortrait: Bool {
        !isLandscape
    }
}

public extension CGPoint {
    func offsetBy(dx: CGFloat = 0.0, dy: CGFloat = 0.0) -> CGPoint {
        return offsetBy(CGVector(dx: dx, dy: dy))
    }

    func offsetBy(_ vector: CGVector) -> CGPoint {
        return CGPoint(x: x + vector.dx, y: y + vector.dy)
    }
}

public extension CGFloat {

    private static let iPhone5ScreenWidth: CGFloat = 320

    private static let iPhone7PlusScreenWidth: CGFloat = 414

    // A convenience method for doing responsive layout. Scales between two
    // reference values (for iPhone 5 and iPhone 7 Plus) to the current device
    // based on screen width, linearly interpolating.
    static func scaleFromIPhone5To7Plus(_ iPhone5Value: CGFloat, _ iPhone7PlusValue: CGFloat) -> CGFloat {
        let shortDimension = CurrentAppContext().frame.size.smallerAxis
        let alpha = CGFloat.clamp01(CGFloat.inverseLerp(shortDimension, min: iPhone5ScreenWidth, max: iPhone7PlusScreenWidth))
        return CGFloat.lerp(left: iPhone5Value, right: iPhone7PlusValue, alpha: alpha).rounded()
    }

    // A convenience method for doing responsive layout. Scales a reference
    // value (for iPhone 5) to the current device based on screen width,
    // linearly interpolating through the origin.
    static func scaleFromIPhone5(_ iPhone5Value: CGFloat) -> CGFloat {
        let shortDimension = CurrentAppContext().frame.size.smallerAxis
        return (iPhone5Value * shortDimension / iPhone5ScreenWidth).rounded()
    }
}
