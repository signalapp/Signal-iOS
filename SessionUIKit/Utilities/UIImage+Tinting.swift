// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public extension UIImage {
    func withTint(_ color: UIColor) -> UIImage? {
        let template = self.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: template)
        imageView.themeTintColorForced = .color(color)
        
        return imageView.toImage(isOpaque: imageView.isOpaque, scale: UIScreen.main.scale)
    }
}
