//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

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

// MARK: - SpacerView

public class SpacerView: UIView {
    private var preferredSize: CGSize

    override open class var layerClass: AnyClass {
        CATransformLayer.self
    }

    convenience public init(preferredWidth: CGFloat = UIView.noIntrinsicMetric, preferredHeight: CGFloat = UIView.noIntrinsicMetric) {
        self.init(preferredSize: CGSize(width: preferredWidth, height: preferredHeight))
    }

    public init(preferredSize: CGSize = CGSize(square: UIView.noIntrinsicMetric)) {
        self.preferredSize = preferredSize
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: CGSize {
        get { preferredSize }
        set { preferredSize = newValue }
    }
}

// MARK: -

@objc
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

    class func spacer(withWidth width: CGFloat) -> UIView {
        let view = TransparentView()
        view.autoSetDimension(.width, toSize: width)
        return view
    }

    class func spacer(withHeight height: CGFloat) -> UIView {
        let view = TransparentView()
        view.autoSetDimension(.height, toSize: height)
        return view
    }

    class func spacer(matchingHeightOf matchView: UIView, withMultiplier multiplier: CGFloat) -> UIView {
        let spacer = TransparentView()
        spacer.autoMatch(.height, to: .height, of: matchView, withMultiplier: multiplier)
        return spacer
    }

    class func hStretchingSpacer() -> UIView {
        let view = TransparentView()
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        return view
    }

    @nonobjc
    class func vStretchingSpacer(minHeight: CGFloat? = nil, maxHeight: CGFloat? = nil) -> UIView {
        let view = TransparentView()
        view.setContentHuggingVerticalLow()
        view.setCompressionResistanceVerticalLow()

        if let minHeight = minHeight {
            view.autoSetDimension(.height, toSize: minHeight, relation: .greaterThanOrEqual)
        }
        if let maxHeight = maxHeight {
            NSLayoutConstraint.autoSetPriority(.defaultLow) {
                view.autoSetDimension(.height, toSize: maxHeight)
            }
        }

        return view
    }

    class func transparentSpacer() -> UIView {
        let view = TransparentView()
        view.setContentHuggingHorizontalLow()
        view.setCompressionResistanceHorizontalLow()
        return view
    }

    @objc
    class TransparentView: UIView {
        override open class var layerClass: AnyClass {
            CATransformLayer.self
        }

        #if TESTABLE_BUILD
        @objc
        public override var backgroundColor: UIColor? {
            didSet {
                // iOS 12 sometimes clears the backgroundColor for views in
                // table view cells. This assert is only intended to catch
                // bugs in our own code, so we can ignore older versions
                // of iOS.
                if #available(iOS 14, *) {
                    owsFailDebug("This is a non-rendering view.")
                }
            }
        }
        #endif
    }

    func setShadow(radius: CGFloat = 2.0, opacity: Float = 0.66, offset: CGSize = .zero, color: UIColor = UIColor.black) {
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = offset
        layer.shadowColor = color.cgColor
    }

    class func accessibilityIdentifier(in container: NSObject, name: String) -> String {
        "\(type(of: container)).\(name)"
    }

    class func accessibilityIdentifier(containerName: String, name: String) -> String {
        "\(containerName).\(name)"
    }

    func setAccessibilityIdentifier(in container: NSObject, name: String) {
        self.accessibilityIdentifier = UIView.accessibilityIdentifier(in: container, name: name)
    }

    func animateDecelerationToVerticalEdge(
        withDuration duration: TimeInterval,
        velocity: CGPoint,
        velocityThreshold: CGFloat = 500,
        boundingRect: CGRect,
        completion: ((Bool) -> Void)? = nil
    ) {
        var velocity = velocity
        if abs(velocity.x) < velocityThreshold { velocity.x = 0 }
        if abs(velocity.y) < velocityThreshold { velocity.y = 0 }

        let currentPosition = frame.origin

        let referencePoint: CGPoint
        if velocity != .zero {
            // Calculate the time until we intersect with each edge with
            // a constant velocity.

            // time = (end position - start position) / velocity

            let timeUntilVerticalEdge: CGFloat
            if velocity.x > 0 {
                timeUntilVerticalEdge = ((boundingRect.maxX - width) - currentPosition.x) / velocity.x
            } else if velocity.x < 0 {
                timeUntilVerticalEdge = (boundingRect.minX - currentPosition.x) / velocity.x
            } else {
                timeUntilVerticalEdge = .greatestFiniteMagnitude
            }

            let timeUntilHorizontalEdge: CGFloat
            if velocity.y > 0 {
                timeUntilHorizontalEdge = ((boundingRect.maxY - height) - currentPosition.y) / velocity.y
            } else if velocity.y < 0 {
                timeUntilHorizontalEdge = (boundingRect.minY - currentPosition.y) / velocity.y
            } else {
                timeUntilHorizontalEdge = .greatestFiniteMagnitude
            }

            // See which edge we intersect with first and calculate the position
            // on the other axis when we reach that intersection point.

            // end position = (time * velocity) + start position

            let intersectPoint: CGPoint
            if timeUntilHorizontalEdge > timeUntilVerticalEdge {
                intersectPoint = CGPoint(
                    x: velocity.x > 0 ? (boundingRect.maxX - width) : boundingRect.minX,
                    y: (timeUntilVerticalEdge * velocity.y) + currentPosition.y
                )
            } else {
                intersectPoint = CGPoint(
                    x: (timeUntilHorizontalEdge * velocity.x) + currentPosition.x,
                    y: velocity.y > 0 ? (boundingRect.maxY - height) : boundingRect.minY
                )
            }

            referencePoint = intersectPoint
        } else {
            referencePoint = currentPosition
        }

        let destinationFrame = CGRect(origin: referencePoint, size: frame.size).pinnedToVerticalEdge(of: boundingRect)
        let distance = destinationFrame.origin.distance(currentPosition)

        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: abs(velocity.length / distance),
            options: .curveEaseOut,
            animations: { self.frame = destinationFrame },
            completion: completion
        )
    }

    @discardableResult
    func autoPinHeight(toHeightOf otherView: UIView) -> NSLayoutConstraint {
        return autoMatch(.height, to: .height, of: otherView)
    }

    @discardableResult
    func autoPinWidth(toWidthOf otherView: UIView) -> NSLayoutConstraint {
        return autoMatch(.width, to: .width, of: otherView)
    }

    @discardableResult
    func autoPinEdgesToSuperviewEdges(withInsets insets: UIEdgeInsets) -> [NSLayoutConstraint] {
        [
            autoPinEdge(toSuperviewEdge: .top, withInset: insets.top),
            autoPinEdge(toSuperviewEdge: .bottom, withInset: insets.bottom),
            autoPinEdge(toSuperviewEdge: .left, withInset: insets.left),
            autoPinEdge(toSuperviewEdge: .right, withInset: insets.right)
        ]
    }

    @discardableResult
    func autoPinWidthToSuperview(relation: NSLayoutConstraint.Relation) -> [NSLayoutConstraint] {
        // We invert the relation because of the weird grammar switch when talking about
        // the size of widths to the positioning of edges
        // "Width less than or equal to superview margin width"
        // -> "Leading edge greater than or equal to superview leading edge"
        // -> "Trailing edge less than or equal to superview trailing edge" (then PureLayout re-inverts for whatever reason)
        let resolvedRelation = relation.inverse
        return [
            autoPinEdge(toSuperviewEdge: .leading, withInset: .zero, relation: resolvedRelation),
            autoPinEdge(toSuperviewEdge: .trailing, withInset: .zero, relation: resolvedRelation)
        ]
    }

    @discardableResult
    func autoPinHeightToSuperview(relation: NSLayoutConstraint.Relation) -> [NSLayoutConstraint] {
        // We invert the relation because of the weird grammar switch when talking about
        // the size of height to the positioning of edges
        // "Height less than or equal to superview margin height"
        // -> "Top edge greater than or equal to superview top edge"
        // -> "Bottom edge less than or equal to superview bottom edge" (then PureLayout re-inverts for whatever reason)
        let resolvedRelation = relation.inverse
        return [
            autoPinEdge(toSuperviewEdge: .top, withInset: .zero, relation: resolvedRelation),
            autoPinEdge(toSuperviewEdge: .bottom, withInset: .zero, relation: resolvedRelation)
        ]
    }

    @discardableResult
    func autoPinWidthToSuperviewMargins(relation: NSLayoutConstraint.Relation) -> [NSLayoutConstraint] {
        // We invert the relation because of the weird grammar switch when talking about
        // the size of widths to the positioning of edges
        // "Width less than or equal to superview margin width"
        // -> "Leading edge greater than or equal to superview leading edge"
        // -> "Trailing edge less than or equal to superview trailing edge" (then PureLayout re-inverts for whatever reason)
        let resolvedRelation = relation.inverse
        return [
            autoPinEdge(toSuperviewMargin: .leading, relation: resolvedRelation),
            autoPinEdge(toSuperviewMargin: .trailing, relation: resolvedRelation)
        ]
    }

    @discardableResult
    func autoPinHeightToSuperviewMargins(relation: NSLayoutConstraint.Relation) -> [NSLayoutConstraint] {
        // We invert the relation because of the weird grammar switch when talking about
        // the size of height to the positioning of edges
        // "Height less than or equal to superview margin height"
        // -> "Top edge greater than or equal to superview top edge"
        // -> "Bottom edge less than or equal to superview bottom edge" (then PureLayout re-inverts for whatever reason)
        let resolvedRelation = relation.inverse
        return [
            autoPinEdge(toSuperviewMargin: .top, relation: resolvedRelation),
            autoPinEdge(toSuperviewMargin: .bottom, relation: resolvedRelation)
        ]
    }

    func removeAllSubviews() {
        for subview in subviews {
            subview.removeFromSuperview()
        }
    }

    static func matchWidthsOfViews(_ views: [UIView]) {
        var firstView: UIView?
        for view in views {
            if let otherView = firstView {
                view.autoMatch(.width, to: .width, of: otherView)
            } else {
                firstView = view
            }
        }
    }

    static func matchHeightsOfViews(_ views: [UIView]) {
        var firstView: UIView?
        for view in views {
            if let otherView = firstView {
                view.autoMatch(.height, to: .height, of: otherView)
            } else {
                firstView = view
            }
        }
    }

    var sizeThatFitsMaxSize: CGSize {
        sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude))
    }

    func deactivateAllConstraints() {
        for constraint in constraints {
            constraint.isActive = false
        }
    }

    @objc(containerView)
    static func container() -> UIView {
        let view = UIView()
        view.layoutMargins = .zero
        return view
    }

    // If the container doesn't need a background color, it's
    // more efficient to use a non-rendering view.
    static func transparentContainer() -> UIView {
        let view = TransparentView()
        view.layoutMargins = .zero
        return view
    }

    func setIsHidden(_ isHidden: Bool, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        setIsHidden(isHidden, withAnimationDuration: animated ? 0.2 : 0, completion: completion)
    }

    func setIsHidden(_ isHidden: Bool, withAnimationDuration duration: TimeInterval, completion: ((Bool) -> Void)? = nil) {
        guard duration > 0, isHidden != self.isHidden else {
            self.isHidden = isHidden
            completion?(true)
            return
        }

        let initialAlpha = alpha
        if !isHidden && initialAlpha > 0 {
            UIView.performWithoutAnimation {
                self.alpha = 0
                self.isHidden = false
            }
        }

        UIView.animate(withDuration: duration,
                       animations: {
            self.alpha = isHidden ? 0 : initialAlpha
        },
                       completion: { finished in
            guard finished else {
                completion?(false)
                return
            }
            self.isHidden = isHidden
            self.alpha = initialAlpha
            completion?(true)
        })
    }
}

// MARK: -

@objc
public extension UIViewController {
    func presentActionSheet(_ alert: ActionSheetController) {
        self.presentActionSheet(alert, animated: true)
    }

    func presentActionSheet(_ alert: ActionSheetController, animated: Bool) {
        self.present(alert, animated: animated)
    }

    func presentActionSheet(_ alert: ActionSheetController, completion: @escaping (() -> Void)) {
        self.present(alert,
                     animated: true,
                     completion: completion)
    }

    /// A convenience function to present a modal view full screen, not using
    /// the default card style added in iOS 13.
    @objc(presentFullScreenViewController:animated:completion:)
    func presentFullScreen(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        viewControllerToPresent.modalPresentationStyle = .fullScreen
        present(viewControllerToPresent, animated: animated, completion: completion)
    }

    @objc(presentFormSheetViewController:animated:completion:)
    func presentFormSheet(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        // Presenting form sheet on iPhone should always use the default presentation style.
        // We get this for free, except on phones with the regular width size class (big phones
        // in landscape, XR, XS Max, 8+, etc.)
        if UIDevice.current.isIPad {
            viewControllerToPresent.modalPresentationStyle = .formSheet
        }
        present(viewControllerToPresent, animated: animated, completion: completion)
    }

    var owsNavigationController: OWSNavigationController? {
        return navigationController as? OWSNavigationController
    }
}

// MARK: -

public extension CGAffineTransform {
    static func translate(_ point: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: point.x, y: point.y)
    }

    static func scale(_ scaling: CGFloat) -> CGAffineTransform {
        CGAffineTransform(scaleX: scaling, y: scaling)
    }

    static func rotate(_ angleRadians: CGFloat) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: angleRadians)
    }

    func translate(_ point: CGPoint) -> CGAffineTransform {
        translatedBy(x: point.x, y: point.y)
    }

    func scale(_ scaling: CGFloat) -> CGAffineTransform {
        scaledBy(x: scaling, y: scaling)
    }

    func rotate(_ angleRadians: CGFloat) -> CGAffineTransform {
        rotated(by: angleRadians)
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

public extension CACornerMask {
    static let top: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    static let bottom: CACornerMask = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    static let left: CACornerMask = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
    static let right: CACornerMask = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]

    static let all: CACornerMask = top.union(bottom)
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
    func setTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) {
        guard let templateImage = templateImage else {
            owsFailDebug("Missing image")
            return
        }
        setImage(templateImage.withRenderingMode(.alwaysTemplate), for: .normal)
        self.tintColor = tintColor
    }

    func setTemplateImageName(_ imageName: String, tintColor: UIColor) {
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Couldn't load image: \(imageName)")
            return
        }
        setTemplateImage(image, tintColor: tintColor)
    }

    class func withTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) -> UIButton {
        let imageView = UIButton()
        imageView.setTemplateImage(templateImage, tintColor: tintColor)
        return imageView
    }

    class func withTemplateImageName(_ imageName: String, tintColor: UIColor) -> UIButton {
        let imageView = UIButton()
        imageView.setTemplateImageName(imageName, tintColor: tintColor)
        return imageView
    }

    func setImage(_ image: UIImage?, animated: Bool) {
        setImage(image, withAnimationDuration: animated ? 0.2 : 0)
    }

    func setImage(_ image: UIImage?, withAnimationDuration duration: TimeInterval) {
        guard duration > 0 else {
            setImage(image, for: .normal)
            return
        }
        UIView.transition(with: self, duration: duration, options: .transitionCrossDissolve) {
            self.setImage(image, for: .normal)
        }
    }
}

// MARK: -

@objc
public extension UIImageView {
    func setImage(imageName: String) {
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Couldn't load image: \(imageName)")
            return
        }
        self.image = image
    }

    func setTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) {
        guard let templateImage = templateImage else {
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
}

// MARK: -

@objc
public extension UISearchBar {
    var textField: UITextField? {
        if #available(iOS 13, *) { return searchTextField }

        guard let textField = self.value(forKey: "_searchField") as? UITextField else {
            owsFailDebug("Couldn't find UITextField.")
            return nil
        }
        return textField
    }
}

// MARK: -

@objc
public extension UITextView {
    func acceptAutocorrectSuggestion() {
        // https://stackoverflow.com/a/27865136/4509555
        inputDelegate?.selectionWillChange(self)
        inputDelegate?.selectionDidChange(self)
    }

    func updateVerticalInsetsForDynamicBodyType(defaultInsets: CGFloat) {
        let currentFontSize = UIFont.ows_dynamicTypeBody.pointSize
        let systemDefaultFontSize: CGFloat = 17
        let insetFontAdjustment = systemDefaultFontSize > currentFontSize ? systemDefaultFontSize - currentFontSize : 0
        let topInset = defaultInsets + insetFontAdjustment
        let bottomInset = systemDefaultFontSize > currentFontSize ? topInset - 1 : topInset
        textContainerInset.top = topInset
        textContainerInset.bottom = bottomInset
    }
}

// MARK: -

@objc
public extension UITextField {
    func acceptAutocorrectSuggestion() {
        inputDelegate?.selectionWillChange(self)
        inputDelegate?.selectionDidChange(self)
    }
}

public extension UIView {
    func firstAncestor<T>(ofType type: T.Type) -> T? {
        guard let superview = superview else {
            return nil
        }

        return superview as? T ?? superview.firstAncestor(ofType: type)
    }
}

// MARK: -

public extension UIToolbar {
    static func clear() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.backgroundColor = .clear

        // Making a toolbar transparent requires setting an empty uiimage
        toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)

        // hide 1px top-border
        toolbar.clipsToBounds = true

        return toolbar
    }
}

// MARK: - Gestures

public extension UIView {
    func containsGestureLocation(_ gestureRecognizer: UIGestureRecognizer,
                                 hotAreaAdjustment: CGFloat? = nil) -> Bool {
        let location = gestureRecognizer.location(in: self)
        var hotArea = bounds
        if let hotAreaAdjustment = hotAreaAdjustment {
            owsAssertDebug(hotAreaAdjustment > 0)
            // Permissive hot area to make it easier to perform gesture.
            hotArea = hotArea.insetBy(dx: -hotAreaAdjustment, dy: -hotAreaAdjustment)
        }
        return hotArea.contains(location)
    }
}

// MARK: -

public extension UIStackView {
    func addArrangedSubviews(_ subviews: [UIView], reverseOrder: Bool = false) {
        var subviews = subviews
        if reverseOrder {
            subviews.reverse()
        }
        for subview in subviews {
            addArrangedSubview(subview)
        }
    }
}

// MARK: -

// This works around a UIStackView bug where hidden subviews
// sometimes re-appear.
@objc
public extension UIView {
    var isHiddenInStackView: Bool {
        get { isHidden }
        set {
            isHidden = newValue
            alpha = newValue ? 0 : 1
        }
    }
}

// MARK: -

public extension UIStackView {
    func addArrangedSubviews(_ subviews: [UIView]) {
        for subview in subviews {
            addArrangedSubview(subview)
        }
    }

    var layoutMarginsWidth: CGFloat {
        guard isLayoutMarginsRelativeArrangement else {
            return 0
        }
        return layoutMargins.left + layoutMargins.right
    }

    var layoutMarginsHeight: CGFloat {
        guard isLayoutMarginsRelativeArrangement else {
            return 0
        }
        return layoutMargins.top + layoutMargins.bottom
    }

    @discardableResult
    func addPillBackgroundView(backgroundColor: UIColor) -> UIView {
        let backgroundView = OWSLayerView.pillView()
        backgroundView.backgroundColor = backgroundColor
        addSubview(backgroundView)
        backgroundView.autoPinEdgesToSuperviewEdges()
        backgroundView.setCompressionResistanceLow()
        backgroundView.setContentHuggingLow()
        sendSubviewToBack(backgroundView)
        return backgroundView
    }
}

// MARK: -

extension UIImage {
    @objc
    public func asTintedImage(color: UIColor) -> UIImage? {
        let template = self.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: template)
        imageView.tintColor = color

        return imageView.renderAsImage(opaque: imageView.isOpaque, scale: UIScreen.main.scale)
    }

    /// Redraw the image into a new image, with an added background color, and inset the
    /// original image by the provided insets.
    public func withBackgroundColor(
        _ color: UIColor,
        insets: UIEdgeInsets = .zero
    ) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, true, scale)
        defer {
            UIGraphicsEndImageContext()
        }

        guard let ctx = UIGraphicsGetCurrentContext(), let image = cgImage else {
            owsFailDebug("Failed to create image context when setting image background")
            return nil
        }

        let rect = CGRect(origin: .zero, size: size)
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect)
        // draw the background behind
        ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height))
        ctx.draw(image, in: rect.inset(by: insets))

        guard let newImage = UIGraphicsGetImageFromCurrentImageContext() else {
            owsFailDebug("Failed to create background-colored image from context")
            return nil
        }
        return newImage
    }
}

// MARK: -

private class CALayerDelegateNoAnimations: NSObject, CALayerDelegate {
    /* If defined, called by the default implementation of the
     * -actionForKey: method. Should return an object implementing the
     * CAAction protocol. May return 'nil' if the delegate doesn't specify
     * a behavior for the current event. Returning the null object (i.e.
     * '[NSNull null]') explicitly forces no further search. (I.e. the
     * +defaultActionForKey: method will not be called.) */
    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        NSNull()
    }
}

// MARK: -

extension CALayer {
    private static let delegateNoAnimations = CALayerDelegateNoAnimations()

    @objc
    public func disableAnimationsWithDelegate() {
        owsAssertDebug(self.delegate == nil)

        self.delegate = Self.delegateNoAnimations
    }
}

// MARK: - Corners

@objc
public extension UIView {
    static func uiRectCorner(forOWSDirectionalRectCorner corner: OWSDirectionalRectCorner) -> UIRectCorner {
        if corner == .allCorners {
            return .allCorners
        }

        var result: UIRectCorner = []
        let isRTL = CurrentAppContext().isRTL

        if corner.contains(.topLeading) {
            result.insert(isRTL ? .topRight : .topLeft)
        }
        if corner.contains(.topTrailing) {
            result.insert(isRTL ? .topLeft : .topRight)
        }
        if corner.contains(.bottomTrailing) {
            result.insert(isRTL ? .bottomLeft : .bottomRight)
        }
        if corner.contains(.bottomLeading) {
            result.insert(isRTL ? .bottomRight : .bottomLeft)
        }
        return result
    }
}

// MARK: - Corners

@objc
public extension UIBezierPath {
    /// Create a roundedRect path with two different corner radii.
    ///
    /// - Parameters:
    ///   - rect: The outer bounds of the roundedRect.
    ///   - sharpCorners: The corners that should use `sharpCornerRadius`. The
    ///     other corners will use `wideCornerRadius`.
    ///   - sharpCornerRadius: The corner radius of `sharpCorners`.
    ///   - wideCornerRadius: The corner radius of non-`sharpCorners`.
    ///
    static func roundedRect(
        _ rect: CGRect,
        sharpCorners: UIRectCorner,
        sharpCornerRadius: CGFloat,
        wideCornerRadius: CGFloat
    ) -> UIBezierPath {

        return roundedRect(
            rect,
            sharpCorners: sharpCorners,
            sharpCornerRadius: sharpCornerRadius,
            wideCorners: .allCorners.subtracting(sharpCorners),
            wideCornerRadius: wideCornerRadius
        )
    }

    /// Create a roundedRect path with two different corner radii.
    ///
    /// The behavior is undefined if `sharpCorners` and `wideCorners` overlap.
    ///
    /// - Parameters:
    ///   - rect: The outer bounds of the roundedRect.
    ///   - sharpCorners: The corners that should use `sharpCornerRadius`.
    ///   - sharpCornerRadius: The corner radius of `sharpCorners`.
    ///   - wideCorners: The corners that should use `wideCornerRadius`.
    ///   - wideCornerRadius: The corner radius of `wideCorners`.
    ///
    static func roundedRect(
        _ rect: CGRect,
        sharpCorners: UIRectCorner,
        sharpCornerRadius: CGFloat,
        wideCorners: UIRectCorner,
        wideCornerRadius: CGFloat
    ) -> UIBezierPath {

        assert(sharpCorners.isDisjoint(with: wideCorners))

        let bezierPath = UIBezierPath()

        func cornerRounding(forCorner corner: UIRectCorner) -> CGFloat {
            if sharpCorners.contains(corner) {
                return sharpCornerRadius
            }
            if wideCorners.contains(corner) {
                return wideCornerRadius
            }
            return 0
        }
        let topLeftRounding = cornerRounding(forCorner: .topLeft)
        let topRightRounding = cornerRounding(forCorner: .topRight)
        let bottomRightRounding = cornerRounding(forCorner: .bottomRight)
        let bottomLeftRounding = cornerRounding(forCorner: .bottomLeft)

        let topAngle = CGFloat.halfPi * 3
        let rightAngle = CGFloat.halfPi * 0
        let bottomAngle = CGFloat.halfPi * 1
        let leftAngle = CGFloat.halfPi * 2

        let bubbleLeft = rect.minX
        let bubbleTop = rect.minY
        let bubbleRight = rect.maxX
        let bubbleBottom = rect.maxY

        // starting just to the right of the top left corner and working clockwise
        bezierPath.move(to: CGPoint(x: bubbleLeft + topLeftRounding, y: bubbleTop))

        // top right corner
        bezierPath.addArc(
            withCenter: CGPoint(x: bubbleRight - topRightRounding,
                                y: bubbleTop + topRightRounding),
            radius: topRightRounding,
            startAngle: topAngle,
            endAngle: rightAngle,
            clockwise: true
        )

        // bottom right corner
        bezierPath.addArc(
            withCenter: CGPoint(x: bubbleRight - bottomRightRounding,
                                y: bubbleBottom - bottomRightRounding),
            radius: bottomRightRounding,
            startAngle: rightAngle,
            endAngle: bottomAngle,
            clockwise: true
        )

        // bottom left corner
        bezierPath.addArc(
            withCenter: CGPoint(x: bubbleLeft + bottomLeftRounding,
                                y: bubbleBottom - bottomLeftRounding),
            radius: bottomLeftRounding,
            startAngle: bottomAngle,
            endAngle: leftAngle,
            clockwise: true
        )

        // top left corner
        bezierPath.addArc(
            withCenter: CGPoint(x: bubbleLeft + topLeftRounding,
                                y: bubbleTop + topLeftRounding),
            radius: topLeftRounding,
            startAngle: leftAngle,
            endAngle: topAngle,
            clockwise: true
        )

        return bezierPath
    }
}

// MARK: -

public extension NSTextAlignment {
    static var trailing: NSTextAlignment {
        CurrentAppContext().isRTL ? .left : .right
    }
}

// MARK: -

public extension UIApplication {
    func hideKeyboard() {
        sendAction(#selector(UIView.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: -

extension NSTextAlignment: CustomStringConvertible {
    public var description: String {
        switch self {
        case .left:
            return "left"
        case .center:
            return "center"
        case .right:
            return "right"
        case .justified:
            return "justified"
        case .natural:
            return "natural"
        @unknown default:
            return "unknown"
        }
    }
}

extension NSLayoutConstraint.Relation {
    var inverse: NSLayoutConstraint.Relation {
        switch self {
        case .lessThanOrEqual: return .greaterThanOrEqual
        case .equal: return .equal
        case .greaterThanOrEqual: return .lessThanOrEqual
        @unknown default:
            owsFailDebug("Unknown case")
            return .equal
        }
    }
}
