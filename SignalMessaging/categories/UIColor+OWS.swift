//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - Color Helpers

public extension UIColor {

    func blended(with otherColor: UIColor, alpha alphaParam: CGFloat) -> UIColor {
        var r0: CGFloat = 0
        var g0: CGFloat = 0
        var b0: CGFloat = 0
        var a0: CGFloat = 0
        let result0 = self.getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        assert(result0)

        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        let result1 = otherColor.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        assert(result1)

        let alpha = CGFloatClamp01(alphaParam)
        return UIColor(red: CGFloatLerp(r0, r1, alpha),
                       green: CGFloatLerp(g0, g1, alpha),
                       blue: CGFloatLerp(b0, b1, alpha),
                       alpha: CGFloatLerp(a0, a1, alpha))

    }
}

// MARK: - Palette

public extension UIColor {

    // MARK: Brand Colors

    class var ows_signalBlue: UIColor {
        return UIColor(rgbHex: 0x3A76F0)
    }

    class var ows_signalBlueDark: UIColor {
        return UIColor(rgbHex: 0x1851B4)
    }

    // MARK: Accent Colors

    /// Nav Bar, Primary Buttons
    @objc(ows_accentBlueColor)
    class var ows_accentBlue: UIColor {
        // Ultramarine UI
        return UIColor(rgbHex: 0x2C6BED)
    }

    class var ows_accentBlueDark: UIColor {
        // Ultramarine UI Light
        return UIColor(rgbHex: 0x6191F3)
    }

    class var ows_accentBlueTint: UIColor {
        return UIColor(rgbHex: 0xB0C8F9)
    }

    /// Making calls, success states
    @objc(ows_accentGreenColor)
    class var ows_accentGreen: UIColor {
        return UIColor(rgbHex: 0x4CAF50)
    }

    /// Warning, update states
    class var ows_accentYellow: UIColor {
        return UIColor(rgbHex: 0xFFD624)
    }

    /// Ending calls, error states
    @objc(ows_accentRedColor)
    class var ows_accentRed: UIColor {
        return UIColor(rgbHex: 0xF44336)
    }

    /// mute unmute background color
    class var ows_accentIndigo: UIColor {
        return UIColor(rgbHex: 0x5951c8)
    }

    // MARK: - GreyScale

    @objc(ows_whiteColor)
    class var ows_white: UIColor {
        return UIColor(rgbHex: 0xFFFFFF)
    }

    class var ows_gray02: UIColor {
        return UIColor(rgbHex: 0xF6F6F6)
    }

    class var ows_gray05: UIColor {
        return UIColor(rgbHex: 0xE9E9E9)
    }

    class var ows_gray10: UIColor {
        return UIColor(rgbHex: 0xf0f0f0)
    }

    class var ows_gray12: UIColor {
        return UIColor(rgbHex: 0xe0e0e0)
    }

    class var ows_gray15: UIColor {
        return UIColor(rgbHex: 0xD4D4D4)
    }

    class var ows_gray20: UIColor {
        return UIColor(rgbHex: 0xCCCCCC)
    }

    class var ows_gray22: UIColor {
        return UIColor(rgbHex: 0xC6C6C6)
    }

    class var ows_gray25: UIColor {
        return UIColor(rgbHex: 0xB9B9B9)
    }

    class var ows_gray40: UIColor {
        return UIColor(rgbHex: 0x999999)
    }

    @objc(ows_gray45Color)
    class var ows_gray45: UIColor {
        return UIColor(rgbHex: 0x848484)
    }

    @objc(ows_middleGrayColor)
    class var ows_middleGray: UIColor {
        return UIColor(white: 0.5, alpha: 1)
    }

    class var ows_gray60: UIColor {
        return UIColor(rgbHex: 0x5E5E5E)
    }

    class var ows_gray65: UIColor {
        return UIColor(rgbHex: 0x4A4A4A)
    }

    class var ows_gray75: UIColor {
        return UIColor(rgbHex: 0x3B3B3B)
    }

    class var ows_gray80: UIColor {
        return UIColor(rgbHex: 0x2E2E2E)
    }

    class var ows_gray85: UIColor {
        return UIColor(rgbHex: 0x23252A)
    }

    class var ows_gray90: UIColor {
        return UIColor(rgbHex: 0x1B1B1B)
    }

    class var ows_gray95: UIColor {
        return UIColor(rgbHex: 0x121212)
    }

    class var ows_black: UIColor {
        return UIColor(rgbHex: 0x000000)
    }

    // MARK: Masks

    class var ows_whiteAlpha00: UIColor {
        return UIColor(white: 1.0, alpha: 0)
    }

    class var ows_whiteAlpha20: UIColor {
        return UIColor(white: 1.0, alpha: 0.2)
    }

    class var ows_whiteAlpha25: UIColor {
        return UIColor(white: 1.0, alpha: 0.25)
    }

    class var ows_whiteAlpha30: UIColor {
        return UIColor(white: 1.0, alpha: 0.3)
    }

    class var ows_whiteAlpha40: UIColor {
        return UIColor(white: 1.0, alpha: 0.4)
    }

    class var ows_whiteAlpha50: UIColor {
        return UIColor(white: 1.0, alpha: 0.5)
    }

    class var ows_whiteAlpha60: UIColor {
        return UIColor(white: 1.0, alpha: 0.6)
    }

    class var ows_whiteAlpha70: UIColor {
        return UIColor(white: 1.0, alpha: 0.7)
    }

    class var ows_whiteAlpha80: UIColor {
        return UIColor(white: 1.0, alpha: 0.8)
    }

    class var ows_whiteAlpha90: UIColor {
        return UIColor(white: 1.0, alpha: 0.9)
    }

    class var ows_blackAlpha05: UIColor {
        return UIColor(white: 0, alpha: 0.05)
    }

    class var ows_blackAlpha10: UIColor {
        return UIColor(white: 0, alpha: 0.10)
    }

    class var ows_blackAlpha20: UIColor {
        return UIColor(white: 0, alpha: 0.20)
    }

    class var ows_blackAlpha25: UIColor {
        return UIColor(white: 0, alpha: 0.25)
    }

    class var ows_blackAlpha40: UIColor {
        return UIColor(white: 0, alpha: 0.40)
    }

    class var ows_blackAlpha50: UIColor {
        return UIColor(white: 0, alpha: 0.50)
    }

    class var ows_blackAlpha60: UIColor {
        return UIColor(white: 0, alpha: 0.60)
    }

    class var ows_blackAlpha80: UIColor {
        return UIColor(white: 0, alpha: 0.80)
    }

    // MARK: -

    class func ows_randomColor(isAlphaRandom: Bool) -> UIColor {
        func randomComponent() -> CGFloat {
            CGFloat.random(in: 0..<1, choices: 256)
        }
        return UIColor(red: randomComponent(),
                       green: randomComponent(),
                       blue: randomComponent(),
                       alpha: isAlphaRandom ? randomComponent() : 1)
    }
}
