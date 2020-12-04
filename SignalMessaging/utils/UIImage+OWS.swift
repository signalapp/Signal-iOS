//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import CoreImage

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

    @objc
    public func withTitle(
        _ title: String,
        font: UIFont,
        color: UIColor,
        maxTitleWidth: CGFloat,
        minimumScaleFactor: CGFloat,
        spacing: CGFloat
    ) -> UIImage? {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = font
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = minimumScaleFactor
        titleLabel.textAlignment = .center
        titleLabel.textColor = color
        titleLabel.numberOfLines = title.components(separatedBy: " ").count > 1 ? 2 : 1
        titleLabel.lineBreakMode = .byTruncatingTail

        let titleSize = titleLabel.textRect(forBounds: CGRect(
            origin: .zero,
            size: CGSize(width: maxTitleWidth, height: .greatestFiniteMagnitude
        )), limitedToNumberOfLines: titleLabel.numberOfLines).size
        let additionalWidth = size.width >= titleSize.width ? 0 : titleSize.width - size.width

        var newSize = size
        newSize.height += spacing + titleSize.height
        newSize.width = max(titleSize.width, size.width)

        UIGraphicsBeginImageContextWithOptions(newSize, false, max(scale, UIScreen.main.scale))

        // Draw the image into the new image
        draw(in: CGRect(origin: CGPoint(x: additionalWidth / 2, y: 0), size: size))

        // Draw the title label into the new image
        titleLabel.drawText(in: CGRect(origin: CGPoint(
            x: size.width > titleSize.width ? (size.width - titleSize.width) / 2 : 0,
            y: size.height + spacing
        ), size: titleSize))

        let newImage = UIGraphicsGetImageFromCurrentImageContext()

        UIGraphicsEndImageContext()

        return newImage
    }
}
