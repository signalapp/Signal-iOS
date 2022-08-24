// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIColor

public extension UIColor {
    func toImage() -> UIImage {
        let bounds: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let renderer: UIGraphicsImageRenderer = UIGraphicsImageRenderer(bounds: bounds)

        return renderer.image { rendererContext in
            rendererContext.cgContext.setFillColor(self.cgColor)
            rendererContext.cgContext.fill(bounds)
        }
    }
}

