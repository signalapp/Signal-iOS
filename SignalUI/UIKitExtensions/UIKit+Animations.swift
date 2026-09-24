//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public extension UIViewPropertyAnimator {

    convenience init(
        duration: TimeInterval,
        springDamping: CGFloat,
        springResponse: CGFloat,
        initialVelocity velocity: CGVector = .zero,
    ) {
        let stiffness = pow(2 * .pi / springResponse, 2)
        let damping = 4 * .pi * springDamping / springResponse
        let timingParameters = UISpringTimingParameters(
            mass: 1,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: velocity,
        )
        self.init(duration: duration, timingParameters: timingParameters)
        isUserInteractionEnabled = true
    }
}

public extension UIView {

    func animateDecelerationToVerticalEdge(
        withDuration duration: TimeInterval,
        velocity: CGPoint,
        velocityThreshold: CGFloat = 500,
        boundingRect: CGRect,
        completion: ((Bool) -> Void)? = nil,
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
                    y: (timeUntilVerticalEdge * velocity.y) + currentPosition.y,
                )
            } else {
                intersectPoint = CGPoint(
                    x: (timeUntilHorizontalEdge * velocity.x) + currentPosition.x,
                    y: velocity.y > 0 ? (boundingRect.maxY - height) : boundingRect.minY,
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
            completion: completion,
        )
    }

    /// Shows or hides the view by fading it, using a 0.2 s animation if `animated` is true.
    ///
    /// See ``setIsHidden(_:withAnimationDuration:completion:)``.
    func setIsHidden(_ isHidden: Bool, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        setIsHidden(isHidden, withAnimationDuration: animated ? 0.2 : 0, completion: completion)
    }

    /// Shows or hides the view by fading its `alpha`.
    ///
    /// A show sets `isHidden` to false right away and fades `alpha` in to 1. A hide fades `alpha` out,
    /// and only once the animation finishes sets `isHidden` to true and restores `alpha` to 1.
    ///
    /// Changes may overlap: the most recent one wins, including over pending changes made with
    /// ``setIsHidden(_:using:)``. A change with a `duration` of 0 is applied immediately.
    ///
    /// - Parameter completion: Called when the change has been applied. Called synchronously if
    ///   the view needed no animation, for example because it was already in the requested state.
    func setIsHidden(_ isHidden: Bool, withAnimationDuration duration: TimeInterval, completion: ((Bool) -> Void)? = nil) {
        guard duration > 0, let change = beginAnimatedIsHiddenChange(isHidden) else {
            setIsHiddenWithoutAnimation(isHidden)
            completion?(true)
            return
        }

        UIView.animate(
            withDuration: duration,
            animations: {
                self.animateIsHiddenChange(change)
            },
            completion: { finished in
                self.completeIsHiddenChange(change, finished: finished)
                completion?(finished)
            },
        )
    }

    /// Shows or hides the view by fading its `alpha` using `animator`.
    ///
    /// A show sets `isHidden` to false right away and fades `alpha` in to 1. A hide fades `alpha` out,
    /// and only once `animator` finishes at its end sets `isHidden` to true and restores `alpha` to 1.
    ///
    /// Changes may overlap: the most recent one wins, even if the animator of an earlier change
    /// hasn't started yet, or is stopped or reversed.
    ///
    /// - Parameter animator: The animator to add the fade to, which the caller must start.
    ///   Pass nil to apply the change immediately.
    func setIsHidden(_ isHidden: Bool, using animator: UIViewPropertyAnimator?) {
        guard let animator, let change = beginAnimatedIsHiddenChange(isHidden) else {
            setIsHiddenWithoutAnimation(isHidden)
            return
        }

        animator.addAnimations {
            self.animateIsHiddenChange(change)
        }
        animator.addCompletion { position in
            self.completeIsHiddenChange(change, finished: position == .end)
        }
    }
}

// MARK: - Animated isHidden changes

/// An animated change of `UIView.isHidden`, used to tell whether it has been superseded.
private final class IsHiddenChange {
    let isHidden: Bool

    init(isHidden: Bool) {
        self.isHidden = isHidden
    }
}

private extension UIView {

    static var pendingIsHiddenChangeKey: UInt8 = 0

    /// The most recent animated change of `isHidden`, until it completes.
    ///
    /// `isHidden` is only updated once an animated hide completes, so it can't be used
    /// to tell which state the view is heading to while an animation is in flight.
    var pendingIsHiddenChange: IsHiddenChange? {
        get {
            objc_getAssociatedObject(self, &UIView.pendingIsHiddenChangeKey) as? IsHiddenChange
        }
        set {
            objc_setAssociatedObject(self, &UIView.pendingIsHiddenChangeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Makes `isHidden` the view's pending change and prepares the view to animate to it.
    ///
    /// - Returns: The new pending change, or nil if the view is already in that state and no
    ///   other change is pending, in which case there is nothing to animate.
    func beginAnimatedIsHiddenChange(_ isHidden: Bool) -> IsHiddenChange? {
        // A pending change is superseded even if it's heading to the same state:
        // its animator might never finish at its end.
        guard pendingIsHiddenChange != nil || self.isHidden != isHidden else {
            return nil
        }

        let change = IsHiddenChange(isHidden: isHidden)
        pendingIsHiddenChange = change

        if !isHidden, self.isHidden {
            UIView.performWithoutAnimation {
                self.alpha = 0
                self.isHidden = false
            }
        }
        return change
    }

    /// Called from the animation block of `change`.
    func animateIsHiddenChange(_ change: IsHiddenChange) {
        // Animators run their animation blocks when they start,
        // which might be after a later change has been made.
        guard pendingIsHiddenChange === change else {
            return
        }
        alpha = change.isHidden ? 0 : 1
    }

    /// Called from the completion handler of `change`.
    func completeIsHiddenChange(_ change: IsHiddenChange, finished: Bool) {
        guard pendingIsHiddenChange === change else {
            return
        }
        pendingIsHiddenChange = nil

        guard finished, change.isHidden else {
            return
        }
        alpha = 1
        isHidden = true
    }

    /// Applies `isHidden` immediately, superseding any pending change.
    func setIsHiddenWithoutAnimation(_ isHidden: Bool) {
        if pendingIsHiddenChange != nil {
            pendingIsHiddenChange = nil
            alpha = 1
        }
        self.isHidden = isHidden
    }
}

public extension UIView.AnimationCurve {

    var asAnimationOptions: UIView.AnimationOptions {
        switch self {
        case .easeInOut:
            return .curveEaseInOut
        case .easeIn:
            return .curveEaseIn
        case .easeOut:
            return .curveEaseOut
        case .linear:
            return .curveLinear
        @unknown default:
            return .curveEaseInOut
        }
    }
}

public extension Optional where Wrapped == UIView.AnimationCurve {

    var asAnimationOptions: UIView.AnimationOptions {
        return (self ?? .easeInOut).asAnimationOptions
    }
}

// MARK: - Corners

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
        wideCornerRadius: CGFloat,
    ) -> UIBezierPath {

        return roundedRect(
            rect,
            sharpCorners: sharpCorners,
            sharpCornerRadius: sharpCornerRadius,
            wideCorners: .allCorners.subtracting(sharpCorners),
            wideCornerRadius: wideCornerRadius,
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
        wideCornerRadius: CGFloat,
    ) -> UIBezierPath {

        assert(sharpCorners.isDisjoint(with: wideCorners))

        func cornerRounding(forCorner corner: UIRectCorner) -> CGFloat {
            if sharpCorners.contains(corner) {
                return sharpCornerRadius
            }
            if wideCorners.contains(corner) {
                return wideCornerRadius
            }
            return 0
        }

        return UIBezierPath.roundedRect(
            rect,
            topLeftRounding: cornerRounding(forCorner: .topLeft),
            topRightRounding: cornerRounding(forCorner: .topRight),
            bottomRightRounding: cornerRounding(forCorner: .bottomRight),
            bottomLeftRounding: cornerRounding(forCorner: .bottomLeft),
        )
    }

    static func roundedRect(
        _ rect: CGRect,
        topLeftRounding: CGFloat,
        topRightRounding: CGFloat,
        bottomRightRounding: CGFloat,
        bottomLeftRounding: CGFloat,
    ) -> UIBezierPath {

        let topAngle = CGFloat.halfPi * 3
        let rightAngle = CGFloat.halfPi * 0
        let bottomAngle = CGFloat.halfPi * 1
        let leftAngle = CGFloat.halfPi * 2

        let bubbleLeft = rect.minX
        let bubbleTop = rect.minY
        let bubbleRight = rect.maxX
        let bubbleBottom = rect.maxY

        let bezierPath = UIBezierPath()

        // starting just to the right of the top left corner and working clockwise
        bezierPath.move(to: CGPoint(x: bubbleLeft + topLeftRounding, y: bubbleTop))

        // top right corner
        bezierPath.addArc(
            withCenter: CGPoint(
                x: bubbleRight - topRightRounding,
                y: bubbleTop + topRightRounding,
            ),
            radius: topRightRounding,
            startAngle: topAngle,
            endAngle: rightAngle,
            clockwise: true,
        )

        // bottom right corner
        bezierPath.addArc(
            withCenter: CGPoint(
                x: bubbleRight - bottomRightRounding,
                y: bubbleBottom - bottomRightRounding,
            ),
            radius: bottomRightRounding,
            startAngle: rightAngle,
            endAngle: bottomAngle,
            clockwise: true,
        )

        // bottom left corner
        bezierPath.addArc(
            withCenter: CGPoint(
                x: bubbleLeft + bottomLeftRounding,
                y: bubbleBottom - bottomLeftRounding,
            ),
            radius: bottomLeftRounding,
            startAngle: bottomAngle,
            endAngle: leftAngle,
            clockwise: true,
        )

        // top left corner
        bezierPath.addArc(
            withCenter: CGPoint(
                x: bubbleLeft + topLeftRounding,
                y: bubbleTop + topLeftRounding,
            ),
            radius: topLeftRounding,
            startAngle: leftAngle,
            endAngle: topAngle,
            clockwise: true,
        )

        return bezierPath
    }
}

// MARK: CoreAnimation

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

extension CALayer {

    private static let delegateNoAnimations = CALayerDelegateNoAnimations()

    public func disableAnimationsWithDelegate() {
        owsAssertDebug(self.delegate == nil)

        self.delegate = Self.delegateNoAnimations
    }
}

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

public extension CACornerMask {
    static let top: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    static let bottom: CACornerMask = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    static let left: CACornerMask = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
    static let right: CACornerMask = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]

    static let all: CACornerMask = top.union(bottom)
}
