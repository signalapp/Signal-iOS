// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIColor
import SessionUtilitiesKit

public extension UIColor {
    func toImage() -> UIImage {
        let bounds: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let renderer: UIGraphicsImageRenderer = UIGraphicsImageRenderer(bounds: bounds)

        return renderer.image { rendererContext in
            rendererContext.cgContext.setFillColor(self.cgColor)
            rendererContext.cgContext.fill(bounds)
        }
    }
    
    func blend(with otherColor: UIColor, alpha: CGFloat) -> UIColor {
        var r0: CGFloat = 0
        var g0: CGFloat = 0
        var b0: CGFloat = 0
        var a0: CGFloat = 0
        self.getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        
        let finalAlpha: CGFloat = CGFloatClamp01(alpha)
        
        return UIColor(
            red: CGFloatLerp(r0, r1, finalAlpha),
            green: CGFloatLerp(g0, g1, finalAlpha),
            blue: CGFloatLerp(b0, b1, finalAlpha),
            alpha: CGFloatLerp(a0, a1, finalAlpha)
        )
    }
    
    func brighten(by percentage: CGFloat) -> UIColor {
        guard percentage != 0 else { return self }
        
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        // Note: Looks like as of iOS 10 devices use the kCGColorSpaceExtendedGray color
        // space for grayscale colors which seems to be compatible with the RGB color space
        // meaning we don't need to check 'getWhite:alpha:' if the below method fails, for
        // more info see: https://developer.apple.com/documentation/uikit/uicolor#overview
        guard self.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }

        return UIColor(
            hue: hue,
            saturation: saturation,
            brightness: (brightness + percentage),
            alpha: alpha
        )
    }
}

