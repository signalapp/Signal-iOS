//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension UIEdgeInsets {
    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.init(top: top,
                  left: CurrentAppContext().isRTL ? trailing : leading,
                  bottom: bottom,
                  right: CurrentAppContext().isRTL ? leading : trailing)
    }
}

@objc
public extension UINavigationController {
    @objc
    public func pushViewController(_ viewController: UIViewController,
                                   animated: Bool,
                                   completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        pushViewController(viewController, animated: animated)
        CATransaction.commit()
    }

    @objc
    public func popViewController(animated: Bool,
                                  completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        popViewController(animated: animated)
        CATransaction.commit()
    }

    @objc
    public func popToViewController(_ viewController: UIViewController,
                                    animated: Bool,
                                    completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        self.popToViewController(viewController, animated: animated)
        CATransaction.commit()
    }
}

extension UIView {
    public func renderAsImage() -> UIImage? {
        return renderAsImage(opaque: false, scale: UIScreen.main.scale)
    }

    public func renderAsImage(opaque: Bool, scale: CGFloat) -> UIImage? {
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

    @objc
    public class func spacer(withWidth width: CGFloat) -> UIView {
        let view = UIView()
        view.autoSetDimension(.width, toSize: width)
        return view
    }

    @objc
    public class func spacer(withHeight height: CGFloat) -> UIView {
        let view = UIView()
        view.autoSetDimension(.height, toSize: height)
        return view
    }

    @objc
    public class func hStretchingSpacer() -> UIView {
        let view = UIView()
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        return view
    }

    @objc
    public class func vStretchingSpacer() -> UIView {
        let view = UIView()
        view.setContentHuggingVerticalLow()
        view.setCompressionResistanceVerticalLow()
        return view
    }

    @objc
    public func applyScaleAspectFitLayout(subview: UIView, aspectRatio: CGFloat) -> [NSLayoutConstraint] {
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
}

public extension CGFloat {
    public func clamp(_ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        return CGFloatClamp(self, minValue, maxValue)
    }

    public func clamp01() -> CGFloat {
        return CGFloatClamp01(self)
    }

    // Linear interpolation
    public func lerp(_ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        return CGFloatLerp(minValue, maxValue, self)
    }

    // Inverse linear interpolation
    public func inverseLerp(_ minValue: CGFloat, _ maxValue: CGFloat, shouldClamp: Bool = false) -> CGFloat {
        let value = CGFloatInverseLerp(self, minValue, maxValue)
        return (shouldClamp ? CGFloatClamp01(value) : value)
    }

    public static let halfPi: CGFloat = CGFloat.pi * 0.5
}

public extension Int {
    public func clamp(_ minValue: Int, _ maxValue: Int) -> Int {
        assert(minValue <= maxValue)

        return Swift.max(minValue, Swift.min(maxValue, self))
    }
}

public extension CGPoint {
    public func toUnitCoordinates(viewBounds: CGRect, shouldClamp: Bool) -> CGPoint {
        return CGPoint(x: (x - viewBounds.origin.x).inverseLerp(0, viewBounds.width, shouldClamp: shouldClamp),
                       y: (y - viewBounds.origin.y).inverseLerp(0, viewBounds.height, shouldClamp: shouldClamp))
    }

    public func toUnitCoordinates(viewSize: CGSize, shouldClamp: Bool) -> CGPoint {
        return toUnitCoordinates(viewBounds: CGRect(origin: .zero, size: viewSize), shouldClamp: shouldClamp)
    }

    public func fromUnitCoordinates(viewBounds: CGRect) -> CGPoint {
        return CGPoint(x: viewBounds.origin.x + x.lerp(0, viewBounds.size.width),
                       y: viewBounds.origin.y + y.lerp(0, viewBounds.size.height))
    }

    public func fromUnitCoordinates(viewSize: CGSize) -> CGPoint {
        return fromUnitCoordinates(viewBounds: CGRect(origin: .zero, size: viewSize))
    }

    public func inverse() -> CGPoint {
        return CGPoint(x: -x, y: -y)
    }

    public func plus(_ value: CGPoint) -> CGPoint {
        return CGPointAdd(self, value)
    }

    public func minus(_ value: CGPoint) -> CGPoint {
        return CGPointSubtract(self, value)
    }

    public func times(_ value: CGFloat) -> CGPoint {
        return CGPoint(x: x * value, y: y * value)
    }

    public func min(_ value: CGPoint) -> CGPoint {
        // We use "Swift" to disambiguate the global function min() from this method.
        return CGPoint(x: Swift.min(x, value.x),
                       y: Swift.min(y, value.y))
    }

    public func max(_ value: CGPoint) -> CGPoint {
        // We use "Swift" to disambiguate the global function max() from this method.
        return CGPoint(x: Swift.max(x, value.x),
                       y: Swift.max(y, value.y))
    }

    public var length: CGFloat {
        return sqrt(x * x + y * y)
    }

    public static let unit: CGPoint = CGPoint(x: 1.0, y: 1.0)

    public static let unitMidpoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    public func applyingInverse(_ transform: CGAffineTransform) -> CGPoint {
        return applying(transform.inverted())
    }
}

public extension CGRect {
    public var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }

    public var topLeft: CGPoint {
        return origin
    }

    public var topRight: CGPoint {
        return CGPoint(x: maxX, y: minY)
    }

    public var bottomLeft: CGPoint {
        return CGPoint(x: minX, y: maxY)
    }

    public var bottomRight: CGPoint {
        return CGPoint(x: maxX, y: maxY)
    }
}

public extension CGAffineTransform {
    public static func translate(_ point: CGPoint) -> CGAffineTransform {
        return CGAffineTransform(translationX: point.x, y: point.y)
    }

    public static func scale(_ scaling: CGFloat) -> CGAffineTransform {
        return CGAffineTransform(scaleX: scaling, y: scaling)
    }

    public func translate(_ point: CGPoint) -> CGAffineTransform {
        return translatedBy(x: point.x, y: point.y)
    }

    public func scale(_ scaling: CGFloat) -> CGAffineTransform {
        return scaledBy(x: scaling, y: scaling)
    }

    public func rotate(_ angleRadians: CGFloat) -> CGAffineTransform {
        return rotated(by: angleRadians)
    }
}

public extension UIBezierPath {
    public func addRegion(withPoints points: [CGPoint]) {
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
