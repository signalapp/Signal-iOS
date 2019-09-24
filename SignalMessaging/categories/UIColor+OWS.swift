//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

// MARK: - Color Helpers

@objc
public extension UIColor {

    @objc(colorWithRGBHex:)
    class func color(rgbHex: UInt) -> UIColor {
        return UIColor(rgbHex: rgbHex)
    }

    convenience init(rgbHex value: UInt) {
        let red = CGFloat(((value >> 16) & 0xff)) / 255.0
        let green = CGFloat(((value >> 8) & 0xff)) / 255.0
        let blue = CGFloat(((value >> 0) & 0xff)) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }

    @objc(blendedWithColor:alpha:)
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

@objc
public extension UIColor {

    @objc(ows_signalBrandBlueColor)
    class var ows_signalBrandBlue: UIColor {
        return UIColor(red: 0.1135657504, green: 0.4787300229, blue: 0.89595204589999999, alpha: 1)
    }

    @objc(ows_materialBlueColor)
    class var ows_materialBlue: UIColor {
        // blue: #2090EA
        return UIColor(red: 32.0 / 255.0, green: 144.0 / 255.0, blue: 234.0 / 255.0, alpha: 1)
    }

    @objc(ows_darkIconColor)
    class var ows_darkIcon: UIColor {
        return UIColor(rgbHex: 0x505050)
    }

    @objc(ows_darkGrayColor)
    class var ows_darkGray: UIColor {
        return UIColor(red: 81.0 / 255.0, green: 81.0 / 255.0, blue: 81.0 / 255.0, alpha: 1)
    }

    @objc(ows_darkThemeBackgroundColor)
    class var ows_darkThemeBackground: UIColor {
        return UIColor(red: 35.0 / 255.0, green: 31.0 / 255.0, blue: 32.0 / 255.0, alpha: 1)
    }

    @objc(ows_fadedBlueColor)
    class var ows_fadedBlue: UIColor {
        // blue: #B6DEF4
        return UIColor(red: 182.0 / 255.0, green: 222.0 / 255.0, blue: 244.0 / 255.0, alpha: 1)
    }

    @objc(ows_yellowColor)
    class var ows_yellow: UIColor {
        // gold: #FFBB5C
        return UIColor(red: 245.0 / 255.0, green: 186.0 / 255.0, blue: 98.0 / 255.0, alpha: 1)
    }

    @objc(ows_reminderYellowColor)
    class var ows_reminderYellow: UIColor {
        return UIColor(red: 252.0 / 255.0, green: 240.0 / 255.0, blue: 217.0 / 255.0, alpha: 1)
    }

    @objc(ows_reminderDarkYellowColor)
    class var ows_reminderDarkYellow: UIColor {
        return UIColor(rgbHex: 0xFCDA91)
    }

    @objc(ows_destructiveRedColor)
    class var ows_destructiveRed: UIColor {
        return UIColor(rgbHex: 0xF44336)
    }

    @objc(ows_errorMessageBorderColor)
    class var ows_errorMessageBorder: UIColor {
        return UIColor(red: 195.0 / 255.0, green: 0, blue: 22.0 / 255.0, alpha: 1)
    }

    @objc(ows_infoMessageBorderColor)
    class var ows_infoMessageBorder: UIColor {
        return UIColor(red: 239.0 / 255.0, green: 189.0 / 255.0, blue: 88.0 / 255.0, alpha: 1)
    }

    @objc(ows_lightBackgroundColor)
    class var ows_lightBackground: UIColor {
        return UIColor(red: 242.0 / 255.0, green: 242.0 / 255.0, blue: 242.0 / 255.0, alpha: 1)
    }

    @objc(ows_systemPrimaryButtonColor)
    static let ows_systemPrimaryButton: UIColor = UIView().tintColor

    @objc(ows_messageBubbleLightGrayColor)
    class var ows_messageBubbleLightGray: UIColor {
        return UIColor(hue: 240.0 / 360.0, saturation: 0.02, brightness: 0.92, alpha: 1)
    }

    // MJK TODO: dedupe this color
    @objc(ows_signalBlueColor)
    class var ows_signalBlue: UIColor {
        return UIColor(rgbHex: 0x2090EA)
    }

    @objc(ows_greenColor)
    class var ows_green: UIColor {
        return UIColor(rgbHex: 0x4caf50)
    }

    @objc(ows_redColor)
    class var ows_red: UIColor {
        return UIColor(rgbHex: 0xf44336)
    }

    // MARK: - GreyScale

    @objc(ows_whiteColor)
    class var ows_white: UIColor {
        return UIColor(rgbHex: 0xFFFFFF)
    }

    @objc(ows_gray02Color)
    class var ows_gray02: UIColor {
        return UIColor(rgbHex: 0xF8F9F9)
    }

    @objc(ows_gray05Color)
    class var ows_gray05: UIColor {
        return UIColor(rgbHex: 0xEEEFEF)
    }

    @objc(ows_gray10Color)
    class var ows_gray10: UIColor {
        return UIColor(rgbHex: 0xE1E2E3)
    }

    @objc(ows_gray15Color)
    class var ows_gray15: UIColor {
        return UIColor(rgbHex: 0xD5D6D6)
    }

    @objc(ows_gray25Color)
    class var ows_gray25: UIColor {
        return UIColor(rgbHex: 0xBBBDBE)
    }

    @objc(ows_gray45Color)
    class var ows_gray45: UIColor {
        return UIColor(rgbHex: 0x898A8C)
    }

    @objc(ows_gray60Color)
    class var ows_gray60: UIColor {
        return UIColor(rgbHex: 0x6B6D70)
    }

    @objc(ows_gray75Color)
    class var ows_gray75: UIColor {
        return UIColor(rgbHex: 0x3D3E44)
    }

    @objc(ows_gray85Color)
    class var ows_gray85: UIColor {
        return UIColor(rgbHex: 0x23252A)
    }

    @objc(ows_gray90Color)
    class var ows_gray90: UIColor {
        return UIColor(rgbHex: 0x17191D)
    }

    @objc(ows_gray95Color)
    class var ows_gray95: UIColor {
        return UIColor(rgbHex: 0x0F1012)
    }

    @objc(ows_blackColor)
    class var ows_black: UIColor {
        return UIColor(rgbHex: 0x000000)
    }

    // TODO: dedupe
    @objc(ows_darkSkyBlueColor)
    class var ows_darkSkyBlue: UIColor {
        // HEX 0xc2090EA
        return UIColor(red: 32.0 / 255.0, green: 144.0 / 255.0, blue: 234.0 / 255.0, alpha: 1.0)
    }
}
