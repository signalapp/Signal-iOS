//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public extension UIImageView {

    func setImage(imageName: String) {
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Couldn't load image: \(imageName)")
            return
        }
        self.image = image
    }

    func setTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) {
        guard let templateImage else {
            owsFailDebug("Missing image")
            return
        }
        self.image = templateImage.withRenderingMode(.alwaysTemplate)
        self.tintColor = tintColor
    }

    func setTemplateImageName(_ imageName: String, tintColor: UIColor) {
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Couldn't load image: \(imageName)")
            return
        }
        setTemplateImage(image, tintColor: tintColor)
    }

    class func withTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) -> UIImageView {
        let imageView = UIImageView()
        imageView.setTemplateImage(templateImage, tintColor: tintColor)
        return imageView
    }

    class func withTemplateImageName(_ imageName: String, tintColor: UIColor) -> UIImageView {
        let imageView = UIImageView()
        imageView.setTemplateImageName(imageName, tintColor: tintColor)
        return imageView
    }

    /// Creates an image view with the given theme icon, tinted with the given
    /// color, and constrained to the given size if present.
    /// - Parameters:
    ///   - icon: The ``ThemeIcon`` to display.
    ///   - tintColor: The color to tint the icon
    ///   - size: The size to constrain the image to.
    ///   When `nil`, no constraints are added.
    /// - Returns: A `UIImageView` of the icon.
    class func withTemplateIcon(
        _ icon: ThemeIcon,
        tintColor: UIColor,
        constrainedTo size: CGSize? = nil,
    ) -> UIImageView {
        let imageView = UIImageView()
        imageView.setTemplateImage(Theme.iconImage(icon), tintColor: tintColor)
        if let size {
            imageView.autoSetDimensions(to: size)
        }
        return imageView
    }
}

// MARK: -

public extension UIImage {
    /// Redraw the image into a new image, with an added background color, and inset the
    /// original image by the provided insets.
    func withBackgroundColor(_ color: UIColor, insets: UIEdgeInsets = .zero) -> UIImage? {
        let bounds = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(bounds: bounds).image { context in
            color.setFill()
            context.fill(bounds)
            draw(in: bounds.inset(by: insets))
        }
    }

    func normalized() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            self.draw(in: CGRect(origin: CGPoint.zero, size: size))
        }
    }

    func withTitle(
        _ title: String,
        font: UIFont,
        color: UIColor,
        maxTitleWidth: CGFloat,
        minimumScaleFactor: CGFloat,
        spacing: CGFloat,
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
            size: CGSize(
                width: maxTitleWidth,
                height: .greatestFiniteMagnitude,
            ),
        ), limitedToNumberOfLines: titleLabel.numberOfLines).size
        let additionalWidth = size.width >= titleSize.width ? 0 : titleSize.width - size.width

        var newSize = size
        newSize.height += spacing + titleSize.height
        newSize.width = max(titleSize.width, size.width)

        let displayScale = UITraitCollection.current.displayScale
        UIGraphicsBeginImageContextWithOptions(newSize, false, max(scale, displayScale))

        // Draw the image into the new image
        draw(in: CGRect(origin: CGPoint(x: additionalWidth / 2, y: 0), size: size))

        // Draw the title label into the new image
        titleLabel.drawText(in: CGRect(origin: CGPoint(
            x: size.width > titleSize.width ? (size.width - titleSize.width) / 2 : 0,
            y: size.height + spacing,
        ), size: titleSize))

        let newImage = UIGraphicsGetImageFromCurrentImageContext()

        UIGraphicsEndImageContext()

        return newImage
    }

    func withBadge(
        color: UIColor,
        badgeSize: CGSize = .square(8.5),
    ) -> UIImage {
        let newSize = CGSize(
            width: size.width + (badgeSize.width / 2.0),
            height: size.height + (badgeSize.height / 2.0),
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { context in
            // Draw the image
            draw(at: .zero)

            // Draw the badge in the top-right corner, over the image
            let badgeOrigin = CGPoint(x: size.width - badgeSize.width, y: 0)
            let badgeRect = CGRect(origin: badgeOrigin, size: badgeSize)
            let badgePath = UIBezierPath(ovalIn: badgeRect)
            color.setFill()
            badgePath.fill()
        }
        .withRenderingMode(.alwaysOriginal)
    }
}

// MARK: -

public extension UIView {

    func renderAsImage() -> UIImage {
        renderAsImage(opaque: false, scale: traitCollection.displayScale)
    }

    func renderAsImage(opaque: Bool, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = opaque
        let renderer = UIGraphicsImageRenderer(
            bounds: self.bounds,
            format: format,
        )
        return renderer.image { context in
            self.layer.render(in: context.cgContext)
        }
    }
}
