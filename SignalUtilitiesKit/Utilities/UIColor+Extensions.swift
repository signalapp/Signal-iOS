// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIColor

public extension UIColor {
    func toImage(isDarkMode: Bool) -> UIImage {
        let bounds: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let renderer: UIGraphicsImageRenderer = UIGraphicsImageRenderer(bounds: bounds)

        return renderer.image { rendererContext in
            if #available(iOS 13.0, *) {
                rendererContext.cgContext
                    .setFillColor(
                        self.resolvedColor(
                            // Note: This is needed for '.cgColor' to support dark mode
                            with: UITraitCollection(userInterfaceStyle: isDarkMode ? .dark : .light)
                        ).cgColor
                    )
            }
            else {
                rendererContext.cgContext.setFillColor(self.cgColor)
            }
            
            rendererContext.cgContext.fill(bounds)
        }
    }
}
