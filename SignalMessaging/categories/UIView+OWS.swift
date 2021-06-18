//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension UIEdgeInsets {
    init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.init(top: top,
                  left: CurrentAppContext().isRTL ? trailing : leading,
                  bottom: bottom,
                  right: CurrentAppContext().isRTL ? leading : trailing)
    }

    init(hMargin: CGFloat, vMargin: CGFloat) {
        self.init(top: vMargin, left: hMargin, bottom: vMargin, right: hMargin)
    }

    init(margin: CGFloat) {
        self.init(top: margin, left: margin, bottom: margin, right: margin)
    }

    func plus(_ inset: CGFloat) -> UIEdgeInsets {
        var newInsets = self
        newInsets.top += inset
        newInsets.bottom += inset
        newInsets.left += inset
        newInsets.right += inset
        return newInsets
    }

    func minus(_ inset: CGFloat) -> UIEdgeInsets {
        plus(-inset)
    }

    var asSize: CGSize {
        CGSize(width: left + right,
               height: top + bottom)
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
    func renderAsImage() -> UIImage? {
        renderAsImage(opaque: false, scale: UIScreen.main.scale)
    }

    func renderAsImage(opaque: Bool, scale: CGFloat) -> UIImage? {
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
        NSLayoutConstraint.autoSetPriority(UILayoutPriority.defaultHigh) {
            constraints.append(subview.autoMatch(.width, to: .width, of: self, withMultiplier: 1.0, relation: .equal))
            constraints.append(subview.autoMatch(.height, to: .height, of: self, withMultiplier: 1.0, relation: .equal))
        }

        return constraints
    }

    func setShadow(radius: CGFloat = 2.0, opacity: Float = 0.66, offset: CGSize = .zero, color: CGColor = UIColor.black.cgColor) {
        layer.shadowRadius = radius
        layer.shadowOpacity = opacity
        layer.shadowOffset = offset
        layer.shadowColor = color
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

            // time = (end position - start positon) / velocity

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
}

// MARK: -

public extension CGPoint {
    func toUnitCoordinates(viewBounds: CGRect, shouldClamp: Bool) -> CGPoint {
        CGPoint(x: (x - viewBounds.origin.x).inverseLerp(0, viewBounds.width, shouldClamp: shouldClamp),
                y: (y - viewBounds.origin.y).inverseLerp(0, viewBounds.height, shouldClamp: shouldClamp))
    }

    func toUnitCoordinates(viewSize: CGSize, shouldClamp: Bool) -> CGPoint {
        toUnitCoordinates(viewBounds: CGRect(origin: .zero, size: viewSize), shouldClamp: shouldClamp)
    }

    func fromUnitCoordinates(viewBounds: CGRect) -> CGPoint {
        CGPoint(x: viewBounds.origin.x + x.lerp(0, viewBounds.size.width),
                y: viewBounds.origin.y + y.lerp(0, viewBounds.size.height))
    }

    func fromUnitCoordinates(viewSize: CGSize) -> CGPoint {
        fromUnitCoordinates(viewBounds: CGRect(origin: .zero, size: viewSize))
    }

    func inverse() -> CGPoint {
        CGPoint(x: -x, y: -y)
    }

    func plus(_ value: CGPoint) -> CGPoint {
        CGPointAdd(self, value)
    }

    func plusX(_ value: CGFloat) -> CGPoint {
        CGPointAdd(self, CGPoint(x: value, y: 0))
    }

    func plusY(_ value: CGFloat) -> CGPoint {
        CGPointAdd(self, CGPoint(x: 0, y: value))
    }

    func minus(_ value: CGPoint) -> CGPoint {
        CGPointSubtract(self, value)
    }

    func times(_ value: CGFloat) -> CGPoint {
        CGPoint(x: x * value, y: y * value)
    }

    func min(_ value: CGPoint) -> CGPoint {
        // We use "Swift" to disambiguate the global function min() from this method.
        CGPoint(x: Swift.min(x, value.x),
                y: Swift.min(y, value.y))
    }

    func max(_ value: CGPoint) -> CGPoint {
        // We use "Swift" to disambiguate the global function max() from this method.
        CGPoint(x: Swift.max(x, value.x),
                y: Swift.max(y, value.y))
    }

    var length: CGFloat {
        sqrt(x * x + y * y)
    }

    @inlinable
    func distance(_ other: CGPoint) -> CGFloat {
        sqrt(pow(x - other.x, 2) + pow(y - other.y, 2))
    }

    @inlinable
    func within(_ delta: CGFloat, of other: CGPoint) -> Bool {
        distance(other) <= delta
    }

    static let unit: CGPoint = CGPoint(x: 1.0, y: 1.0)

    static let unitMidpoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    func applyingInverse(_ transform: CGAffineTransform) -> CGPoint {
        applying(transform.inverted())
    }

    func fuzzyEquals(_ other: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
        (x.fuzzyEquals(other.x, tolerance: tolerance) &&
            y.fuzzyEquals(other.y, tolerance: tolerance))
    }

    static func tan(angle: CGFloat) -> CGPoint {
        CGPoint(x: sin(angle),
                y: cos(angle))
    }

    func clamp(_ rect: CGRect) -> CGPoint {
        CGPoint(x: x.clamp(rect.minX, rect.maxX),
                y: y.clamp(rect.minY, rect.maxY))
    }

    static func + (left: CGPoint, right: CGPoint) -> CGPoint {
        left.plus(right)
    }

    static func - (left: CGPoint, right: CGPoint) -> CGPoint {
        CGPoint(x: left.x - right.x, y: left.y - right.y)
    }

    static func * (left: CGPoint, right: CGFloat) -> CGPoint {
        CGPoint(x: left.x * right, y: left.y * right)
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
        CGPoint(x: width, y: height)
    }

    var ceil: CGSize {
        CGSizeCeil(self)
    }

    var floor: CGSize {
        CGSizeFloor(self)
    }

    var round: CGSize {
        CGSizeRound(self)
    }

    var abs: CGSize {
        CGSize(width: Swift.abs(width), height: Swift.abs(height))
    }

    var largerAxis: CGFloat {
        Swift.max(width, height)
    }

    var smallerAxis: CGFloat {
        min(width, height)
    }

    var isNonEmpty: Bool {
        width > 0 && height > 0
    }

    init(square: CGFloat) {
        self.init(width: square, height: square)
    }

    func plus(_ value: CGSize) -> CGSize {
        CGSizeAdd(self, value)
    }

    func max(_ other: CGSize) -> CGSize {
        return CGSize(width: Swift.max(self.width, other.width),
                      height: Swift.max(self.height, other.height))
    }

    static func square(_ size: CGFloat) -> CGSize {
        CGSize(width: size, height: size)
    }

    static func + (left: CGSize, right: CGSize) -> CGSize {
        left.plus(right)
    }

    static func - (left: CGSize, right: CGSize) -> CGSize {
        CGSize(width: left.width - right.width,
               height: left.height - right.height)
    }

    static func * (left: CGSize, right: CGFloat) -> CGSize {
        CGSize(width: left.width * right,
               height: left.height * right)
    }
}

// MARK: -

public extension CGRect {

    var x: CGFloat {
        get {
            origin.x
        }
        set {
            origin.x = newValue
        }
    }

    var y: CGFloat {
        get {
            origin.y
        }
        set {
            origin.y = newValue
        }
    }

    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var topLeft: CGPoint {
        origin
    }

    var topRight: CGPoint {
        CGPoint(x: maxX, y: minY)
    }

    var bottomLeft: CGPoint {
        CGPoint(x: minX, y: maxY)
    }

    var bottomRight: CGPoint {
        CGPoint(x: maxX, y: maxY)
    }

    func pinnedToVerticalEdge(of boundingRect: CGRect) -> CGRect {
        var newRect = self

        // If we're positioned outside of the vertical bounds,
        // we need to move to the nearest bound
        let positionedOutOfVerticalBounds = newRect.minY < boundingRect.minY || newRect.maxY > boundingRect.maxY

        // If we're position anywhere but exactly at the vertical
        // edges (left and right of bounding rect), we need to
        // move to the nearest edge
        let positionedAwayFromVerticalEdges = boundingRect.minX != newRect.minX && boundingRect.maxX != newRect.maxX

        if positionedOutOfVerticalBounds {
            let distanceFromTop = newRect.minY - boundingRect.minY
            let distanceFromBottom = boundingRect.maxY - newRect.maxY

            if distanceFromTop > distanceFromBottom {
                newRect.origin.y = boundingRect.maxY - newRect.height
            } else {
                newRect.origin.y = boundingRect.minY
            }
        }

        if positionedAwayFromVerticalEdges {
            let distanceFromLeading = newRect.minX - boundingRect.minX
            let distanceFromTrailing = boundingRect.maxX - newRect.maxX

            if distanceFromLeading > distanceFromTrailing {
                newRect.origin.x = boundingRect.maxX - newRect.width
            } else {
                newRect.origin.x = boundingRect.minX
            }
        }

        return newRect
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

// MARK: -

public extension UIEdgeInsets {
    var totalWidth: CGFloat {
        left + right
    }

    var totalHeight: CGFloat {
        top + bottom
    }

    var totalSize: CGSize {
        CGSize(width: totalWidth, height: totalHeight)
    }

    var leading: CGFloat {
        get { CurrentAppContext().isRTL ? right : left }
        set {
            if CurrentAppContext().isRTL {
                right = newValue
            } else {
                left = newValue
            }
        }
    }

    var trailing: CGFloat {
        get { CurrentAppContext().isRTL ? left : right }
        set {
            if CurrentAppContext().isRTL {
                left = newValue
            } else {
                right = newValue
            }
        }
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
    static func roundedRect(_ rect: CGRect,
                            sharpCorners: UIRectCorner,
                            sharpCornerRadius: CGFloat,
                            wideCornerRadius: CGFloat) -> UIBezierPath {
        let bezierPath = UIBezierPath()

        func cornerRounding(forCorner corner: UIRectCorner) -> CGFloat {
            sharpCorners.contains(corner) ? sharpCornerRadius : wideCornerRadius
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

public extension CGFloat {
    var pointsAsPixels: CGFloat {
        self * UIScreen.main.scale
    }

    var sqr: CGFloat {
        self * self
    }
}
