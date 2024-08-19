//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

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
        constrainedTo size: CGSize? = nil
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

extension UIImage {
    /// Redraw the image into a new image, with an added background color, and inset the
    /// original image by the provided insets.
    public func withBackgroundColor(_ color: UIColor, insets: UIEdgeInsets = .zero) -> UIImage? {
        let bounds = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(bounds: bounds).image { context in
            color.setFill()
            context.fill(bounds)
            draw(in: bounds.inset(by: insets))
        }
    }
}

// MARK: -

public extension UIView {

    func renderAsImage() -> UIImage {
        renderAsImage(opaque: false, scale: UIScreen.main.scale)
    }

    func renderAsImage(opaque: Bool, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = opaque
        let renderer = UIGraphicsImageRenderer(bounds: self.bounds,
                                               format: format)
        return renderer.image { (context) in
            self.layer.render(in: context.cgContext)
        }
    }
}
