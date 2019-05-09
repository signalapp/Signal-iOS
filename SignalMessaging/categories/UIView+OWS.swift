//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension UIEdgeInsets {
    init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.init(top: top,
                  left: CurrentAppContext().isRTL ? trailing : leading,
                  bottom: bottom,
                  right: CurrentAppContext().isRTL ? leading : trailing)
    }
}

// MARK: -

@objc
public extension UINavigationController {
    func pushViewController(_ viewController: UIViewController,
                                   animated: Bool,
                                   completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        pushViewController(viewController, animated: animated)
        CATransaction.commit()
    }

    func popViewController(animated: Bool,
                                  completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        popViewController(animated: animated)
        CATransaction.commit()
    }

    func popToViewController(_ viewController: UIViewController,
                                    animated: Bool,
                                    completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        self.popToViewController(viewController, animated: animated)
        CATransaction.commit()
    }
}

// MARK: -

@objc
public extension UIView {
    func renderAsImage() -> UIImage? {
        return renderAsImage(opaque: false, scale: UIScreen.main.scale)
    }

    func renderAsImage(opaque: Bool, scale: CGFloat) -> UIImage? {
        if #available(iOS 10, *) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = opaque
            let renderer = UIGraphicsImageRenderer(bounds: self.bounds,
                                                   format: format)
            return renderer.image { (context) in
                self.layer.render(in: context.cgContext)
            }
        } else {
            UIGraphicsBeginImageContextWithOptions(bounds.size, opaque, scale)
            if let _ = UIGraphicsGetCurrentContext() {
                drawHierarchy(in: bounds, afterScreenUpdates: true)
                let image = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                return image
            }
            owsFailDebug("Could not create graphics context.")
            return nil
        }
    }

    class func spacer(withWidth width: CGFloat) -> UIView {
        let view = UIView()
        view.autoSetDimension(.width, toSize: width)
        return view
    }

    class func spacer(withHeight height: CGFloat) -> UIView {
        let view = UIView()
        view.autoSetDimension(.height, toSize: height)
        return view
    }

    class func hStretchingSpacer() -> UIView {
        let view = UIView()
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        return view
    }

    class func vStretchingSpacer() -> UIView {
        let view = UIView()
        view.setContentHuggingVerticalLow()
        view.setCompressionResistanceVerticalLow()
        return view
    }

    func applyScaleAspectFitLayout(subview: UIView, aspectRatio: CGFloat) -> [NSLayoutConstraint] {
        guard subviews.contains(subview) else {
            owsFailDebug("Not a subview.")
            return []
        }

        // This emulates the behavior of contentMode = .scaleAspectFit using
        // iOS auto layout constraints.
        //
        // This allows ConversationInputToolbar to place the "cancel" button
        // in the upper-right hand corner of the preview content.
        var constraints = [NSLayoutConstraint]()
        constraints.append(contentsOf: subview.autoCenterInSuperview())
        constraints.append(subview.autoPin(toAspectRatio: aspectRatio))
        constraints.append(subview.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual))
        constraints.append(subview.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .lessThanOrEqual))
        return constraints
    }

    func setShadow(radius: CGFloat = 2.0, opacity: Float = 0.66, offset: CGSize = .zero, color: CGColor = UIColor.black.cgColor) {
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = offset
        layer.shadowColor = color
    }
}

// MARK: -

@objc
public extension UIViewController {
    func presentAlert(_ alert: UIAlertController) {
        self.presentAlert(alert, animated: true)
    }

    func presentAlert(_ alert: UIAlertController, animated: Bool) {
        self.present(alert,
                     animated: animated,
                     completion: {
                        alert.applyAccessibilityIdentifiers()
        })
    }

    func presentAlert(_ alert: UIAlertController, completion: @escaping (() -> Void)) {
        self.present(alert,
                     animated: true,
                     completion: {
                        alert.applyAccessibilityIdentifiers()

                        completion()
        })
    }
}

// MARK: -

public extension CGFloat {
    func clamp(_ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        return CGFloatClamp(self, minValue, maxValue)
    }

    func clamp01() -> CGFloat {
        return CGFloatClamp01(self)
    }

    // Linear interpolation
    func lerp(_ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        return CGFloatLerp(minValue, maxValue, self)
    }

    // Inverse linear interpolation
    func inverseLerp(_ minValue: CGFloat, _ maxValue: CGFloat, shouldClamp: Bool = false) -> CGFloat {
        let value = CGFloatInverseLerp(self, minValue, maxValue)
        return (shouldClamp ? CGFloatClamp01(value) : value)
    }

    static let halfPi: CGFloat = CGFloat.pi * 0.5

    func fuzzyEquals(_ other: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
        return abs(self - other) < tolerance
    }

    var square: CGFloat {
        return self * self
    }
}

// MARK: -

public extension Int {
    func clamp(_ minValue: Int, _ maxValue: Int) -> Int {
        assert(minValue <= maxValue)

        return Swift.max(minValue, Swift.min(maxValue, self))
    }
}

// MARK: -

public extension CGPoint {
    func toUnitCoordinates(viewBounds: CGRect, shouldClamp: Bool) -> CGPoint {
        return CGPoint(x: (x - viewBounds.origin.x).inverseLerp(0, viewBounds.width, shouldClamp: shouldClamp),
                       y: (y - viewBounds.origin.y).inverseLerp(0, viewBounds.height, shouldClamp: shouldClamp))
    }

    func toUnitCoordinates(viewSize: CGSize, shouldClamp: Bool) -> CGPoint {
        return toUnitCoordinates(viewBounds: CGRect(origin: .zero, size: viewSize), shouldClamp: shouldClamp)
    }

    func fromUnitCoordinates(viewBounds: CGRect) -> CGPoint {
        return CGPoint(x: viewBounds.origin.x + x.lerp(0, viewBounds.size.width),
                       y: viewBounds.origin.y + y.lerp(0, viewBounds.size.height))
    }

    func fromUnitCoordinates(viewSize: CGSize) -> CGPoint {
        return fromUnitCoordinates(viewBounds: CGRect(origin: .zero, size: viewSize))
    }

    func inverse() -> CGPoint {
        return CGPoint(x: -x, y: -y)
    }

    func plus(_ value: CGPoint) -> CGPoint {
        return CGPointAdd(self, value)
    }

    func minus(_ value: CGPoint) -> CGPoint {
        return CGPointSubtract(self, value)
    }

    func times(_ value: CGFloat) -> CGPoint {
        return CGPoint(x: x * value, y: y * value)
    }

    func min(_ value: CGPoint) -> CGPoint {
        // We use "Swift" to disambiguate the global function min() from this method.
        return CGPoint(x: Swift.min(x, value.x),
                       y: Swift.min(y, value.y))
    }

    func max(_ value: CGPoint) -> CGPoint {
        // We use "Swift" to disambiguate the global function max() from this method.
        return CGPoint(x: Swift.max(x, value.x),
                       y: Swift.max(y, value.y))
    }

    var length: CGFloat {
        return sqrt(x * x + y * y)
    }

    static let unit: CGPoint = CGPoint(x: 1.0, y: 1.0)

    static let unitMidpoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    func applyingInverse(_ transform: CGAffineTransform) -> CGPoint {
        return applying(transform.inverted())
    }

    func fuzzyEquals(_ other: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
        return (x.fuzzyEquals(other.x, tolerance: tolerance) &&
            y.fuzzyEquals(other.y, tolerance: tolerance))
    }

    static func tan(angle: CGFloat) -> CGPoint {
        return CGPoint(x: sin(angle),
                       y: cos(angle))
    }

    func clamp(_ rect: CGRect) -> CGPoint {
        return CGPoint(x: x.clamp(rect.minX, rect.maxX),
                       y: y.clamp(rect.minY, rect.maxY))
    }
}

// MARK: -

public extension CGSize {
    var aspectRatio: CGFloat {
        guard self.height > 0 else {
            return 0
        }

        return self.width / self.height
    }

    var asPoint: CGPoint {
        return CGPoint(x: width, y: height)
    }

    var ceil: CGSize {
        return CGSizeCeil(self)
    }
}

// MARK: -

public extension CGRect {
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }

    var topLeft: CGPoint {
        return origin
    }

    var topRight: CGPoint {
        return CGPoint(x: maxX, y: minY)
    }

    var bottomLeft: CGPoint {
        return CGPoint(x: minX, y: maxY)
    }

    var bottomRight: CGPoint {
        return CGPoint(x: maxX, y: maxY)
    }
}

// MARK: -

public extension CGAffineTransform {
    static func translate(_ point: CGPoint) -> CGAffineTransform {
        return CGAffineTransform(translationX: point.x, y: point.y)
    }

    static func scale(_ scaling: CGFloat) -> CGAffineTransform {
        return CGAffineTransform(scaleX: scaling, y: scaling)
    }

    func translate(_ point: CGPoint) -> CGAffineTransform {
        return translatedBy(x: point.x, y: point.y)
    }

    func scale(_ scaling: CGFloat) -> CGAffineTransform {
        return scaledBy(x: scaling, y: scaling)
    }

    func rotate(_ angleRadians: CGFloat) -> CGAffineTransform {
        return rotated(by: angleRadians)
    }
}

// MARK: -

public extension UIBezierPath {
    func addRegion(withPoints points: [CGPoint]) {
        guard let first = points.first else {
            owsFailDebug("No points.")
            return
        }
        move(to: first)
        for point in points.dropFirst() {
            addLine(to: point)
        }
        addLine(to: first)
    }
}

// MARK: -

@objc
public extension UIBarButtonItem {
    convenience init(image: UIImage?, style: UIBarButtonItem.Style, target: Any?, action: Selector?, accessibilityIdentifier: String) {
        self.init(image: image, style: style, target: target, action: action)

        self.accessibilityIdentifier = accessibilityIdentifier
    }

    convenience init(image: UIImage?, landscapeImagePhone: UIImage?, style: UIBarButtonItem.Style, target: Any?, action: Selector?, accessibilityIdentifier: String) {
        self.init(image: image, landscapeImagePhone: landscapeImagePhone, style: style, target: target, action: action)

        self.accessibilityIdentifier = accessibilityIdentifier
    }

    convenience init(title: String?, style: UIBarButtonItem.Style, target: Any?, action: Selector?, accessibilityIdentifier: String) {
        self.init(title: title, style: style, target: target, action: action)

        self.accessibilityIdentifier = accessibilityIdentifier
    }

    convenience init(barButtonSystemItem systemItem: UIBarButtonItem.SystemItem, target: Any?, action: Selector?, accessibilityIdentifier: String) {
        self.init(barButtonSystemItem: systemItem, target: target, action: action)

        self.accessibilityIdentifier = accessibilityIdentifier
    }

    convenience init(customView: UIView, accessibilityIdentifier: String) {
        self.init(customView: customView)

        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

// MARK: -

@objc
public extension UIButton {
    @objc
    func setTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) {
        guard let templateImage = templateImage else {
            owsFailDebug("Missing image")
            return
        }
        setImage(templateImage.withRenderingMode(.alwaysTemplate), for: .normal)
        self.tintColor = tintColor
    }

    @objc
    func setTemplateImageName(_ imageName: String, tintColor: UIColor) {
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Couldn't load image: \(imageName)")
            return
        }
        setTemplateImage(image, tintColor: tintColor)
    }

    @objc
    class func withTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) -> UIButton {
        let imageView = UIButton()
        imageView.setTemplateImage(templateImage, tintColor: tintColor)
        return imageView
    }

    @objc
    class func withTemplateImageName(_ imageName: String, tintColor: UIColor) -> UIButton {
        let imageView = UIButton()
        imageView.setTemplateImageName(imageName, tintColor: tintColor)
        return imageView
    }
}

// MARK: -

@objc
public extension UIImageView {
    @objc
    func setTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) {
        guard let templateImage = templateImage else {
            owsFailDebug("Missing image")
            return
        }
        self.image = templateImage.withRenderingMode(.alwaysTemplate)
        self.tintColor = tintColor
    }

    @objc
    func setTemplateImageName(_ imageName: String, tintColor: UIColor) {
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Couldn't load image: \(imageName)")
            return
        }
        setTemplateImage(image, tintColor: tintColor)
    }

    @objc
    class func withTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) -> UIImageView {
        let imageView = UIImageView()
        imageView.setTemplateImage(templateImage, tintColor: tintColor)
        return imageView
    }

    @objc
    class func withTemplateImageName(_ imageName: String, tintColor: UIColor) -> UIImageView {
        let imageView = UIImageView()
        imageView.setTemplateImageName(imageName, tintColor: tintColor)
        return imageView
    }
}
