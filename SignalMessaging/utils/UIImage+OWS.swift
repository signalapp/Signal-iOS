//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

extension UIImage {
    @objc
    public func asTintedImage(color: UIColor) -> UIImage? {
        let template = self.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: template)
        imageView.tintColor = color

        return imageView.renderAsImage(opaque: imageView.isOpaque, scale: UIScreen.main.scale)
    }

    @objc
    public func withCornerRadius(_ cornerRadius: CGFloat) -> UIImage? {
        let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: size)
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        draw(in: rect)
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
