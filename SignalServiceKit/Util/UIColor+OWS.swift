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

        let alpha = CGFloat.clamp01(alphaParam)
        return UIColor(
            red: CGFloat.lerp(left: r0, right: r1, alpha: alpha),
            green: CGFloat.lerp(left: g0, right: g1, alpha: alpha),
            blue: CGFloat.lerp(left: b0, right: b1, alpha: alpha),
            alpha: CGFloat.lerp(left: a0, right: a1, alpha: alpha),
        )

    }

    /// Blends this color with another color using the overlay blend mode
    /// - Parameters:
    ///   - overlayColor: The color to blend on top
    ///   - opacity: The opacity of the overlay color (0.0 to 1.0)
    /// - Returns: The resulting blended color
    func blendedWithOverlay(_ overlayColor: UIColor, opacity: CGFloat = 1.0) -> UIColor {
        let alpha = opacity.clamp01()

        // Base
        var baseR: CGFloat = 0
        var baseG: CGFloat = 0
        var baseB: CGFloat = 0
        var baseA: CGFloat = 0
        self.getRed(&baseR, green: &baseG, blue: &baseB, alpha: &baseA)

        // Overlay
        var overlayR: CGFloat = 0
        var overlayG: CGFloat = 0
        var overlayB: CGFloat = 0
        var overlayA: CGFloat = 0
        overlayColor.getRed(&overlayR, green: &overlayG, blue: &overlayB, alpha: &overlayA)

        // Apply overlay blend mode formula for each channel
        func overlayBlend(_ base: CGFloat, _ overlay: CGFloat) -> CGFloat {
            if base < 0.5 {
                return 2.0 * base * overlay
            } else {
                return 1.0 - 2.0 * (1.0 - base) * (1.0 - overlay)
            }
        }

        // Calculate blended RGB values
        let blendedR = overlayBlend(baseR, overlayR)
        let blendedG = overlayBlend(baseG, overlayG)
        let blendedB = overlayBlend(baseB, overlayB)

        // Mix the blended result with the base color based on opacity
        let finalR = baseR + (blendedR - baseR) * alpha
        let finalG = baseG + (blendedG - baseG) * alpha
        let finalB = baseB + (blendedB - baseB) * alpha

        return UIColor(red: finalR, green: finalG, blue: finalB, alpha: baseA)
    }

    func midPoint(with otherColor: UIColor) -> UIColor {
        var h1: CGFloat = 0
        var s1: CGFloat = 0
        var v1: CGFloat = 0
        var a1: CGFloat = 0
        var h2: CGFloat = 0
        var s2: CGFloat = 0
        var v2: CGFloat = 0
        var a2: CGFloat = 0

        guard
            getHue(&h1, saturation: &s1, brightness: &v1, alpha: &a1),
            otherColor.getHue(&h2, saturation: &s2, brightness: &v2, alpha: &a2)
        else {
            return midPointRGB(with: otherColor)
        }

        // Handle the Hue component for shortest path around the color wheel (0 to 1 range)
        var hue: CGFloat
        let diff = h2 - h1
        if abs(diff) > 0.5 { // Check if the difference is greater than 180 degrees (0.5 in 0-1 range)
            if diff > 0 {
                h1 += 1.0 // Go counter-clockwise
            } else {
                h2 += 1.0 // Go clockwise
            }
        }
        hue = (h1 + h2) / 2.0
        // Ensure the hue is within the 0 to 1 range
        if hue > 1.0 {
            hue -= 1.0
        }

        // Average the Saturation, Brightness, and Alpha components linearly
        let saturation = (s1 + s2) / 2.0
        let brightness = (v1 + v2) / 2.0
        let alpha = (a1 + a2) / 2.0

        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
    }

    private func midPointRGB(with otherColor: UIColor) -> UIColor {
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0

        self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        otherColor.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        return UIColor(
            red: (r1 + r2) / 2.0,
            green: (g1 + g2) / 2.0,
            blue: (b1 + b2) / 2.0,
            alpha: (a1 + a2) / 2.0,
        )
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

    class var ows_whiteAlpha10: UIColor {
        return UIColor(white: 1.0, alpha: 0.1)
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

    class var ows_blackAlpha70: UIColor {
        return UIColor(white: 0, alpha: 0.70)
    }

    class var ows_blackAlpha80: UIColor {
        return UIColor(white: 0, alpha: 0.80)
    }

    // MARK: -

    class func ows_randomColor(isAlphaRandom: Bool) -> UIColor {
        func randomComponent() -> CGFloat {
            CGFloat.random(in: 0..<1, choices: 256)
        }
        return UIColor(
            red: randomComponent(),
            green: randomComponent(),
            blue: randomComponent(),
            alpha: isAlphaRandom ? randomComponent() : 1,
        )
    }
}
