//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public extension UIColor {
    @objc(colorWithRGBHex:)
    class func color(rgbHex: UInt32) -> UIColor {
        return UIColor(rgbHex: rgbHex)
    }

    convenience init(rgbHex value: UInt32) {
        let red = CGFloat(((value >> 16) & 0xff)) / 255.0
        let green = CGFloat(((value >> 8) & 0xff)) / 255.0
        let blue = CGFloat(((value >> 0) & 0xff)) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }

    var rgbHex: UInt32 {
        var red = CGFloat.zero
        var green = CGFloat.zero
        var blue = CGFloat.zero
        getRed(&red, green: &green, blue: &blue, alpha: nil)
        return UInt32(red * 255) << 16 | UInt32(green * 255) << 8 | UInt32(blue * 255) << 0
    }

    convenience init(argbHex value: UInt32) {
        let alpha = CGFloat(((value >> 24) & 0xff)) / 255.0
        let red = CGFloat(((value >> 16) & 0xff)) / 255.0
        let green = CGFloat(((value >> 8) & 0xff)) / 255.0
        let blue = CGFloat(((value >> 0) & 0xff)) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    var argbHex: UInt32 {
        var alpha = CGFloat.zero
        var red = CGFloat.zero
        var green = CGFloat.zero
        var blue = CGFloat.zero
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UInt32(alpha * 255) << 24 | UInt32(red * 255) << 16 | UInt32(green * 255) << 8 | UInt32(blue * 255) << 0
    }

    func isEqualToColor(_ color: UIColor, tolerance: CGFloat = 0) -> Bool {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)

        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        return abs(r1 - r2) <= tolerance &&
        abs(g1 - g2) <= tolerance &&
        abs(b1 - b2) <= tolerance &&
        abs(a1 - a2) <= tolerance
    }
}
