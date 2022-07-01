// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIColor

public extension UIColor {
    struct HSBA {
        public var hue: CGFloat = 0
        public var saturation: CGFloat = 0
        public var brightness: CGFloat = 0
        public var alpha: CGFloat = 0

        public init?(color: UIColor) {
            // Note: Looks like as of iOS 10 devices use the kCGColorSpaceExtendedGray color
            // space for grayscale colors which seems to be compatible with the RGB color space
            // meaning we don'e need to check 'getWhite:alpha:' if the below method fails, for
            // more info see: https://developer.apple.com/documentation/uikit/uicolor#overview
            guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
                return nil
            }
        }
    }

    var hsba: HSBA? { return HSBA(color: self) }

    // MARK: - Functions

    func toImage(isDarkMode: Bool) -> UIImage {
        let bounds: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let renderer: UIGraphicsImageRenderer = UIGraphicsImageRenderer(bounds: bounds)

        return renderer.image { rendererContext in
            rendererContext.cgContext
                .setFillColor(
                    self.resolvedColor(
                        // Note: This is needed for '.cgColor' to support dark mode
                        with: UITraitCollection(userInterfaceStyle: isDarkMode ? .dark : .light)
                    ).cgColor
                )
            rendererContext.cgContext.fill(bounds)
        }
    }

    func darken(by percentage: CGFloat) -> UIColor {
        guard percentage != 0 else { return self }
        guard let hsba: HSBA = self.hsba else { return self }

        return UIColor(hue: hsba.hue, saturation: hsba.saturation, brightness: (hsba.brightness - percentage), alpha: hsba.alpha)
    }
}
