//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

    static func += (left: inout CGPoint, right: CGPoint) {
        left.x += right.x
        left.y += right.y
    }

    static func - (left: CGPoint, right: CGPoint) -> CGPoint {
        CGPoint(x: left.x - right.x, y: left.y - right.y)
    }

    static func * (left: CGPoint, right: CGFloat) -> CGPoint {
        CGPoint(x: left.x * right, y: left.y * right)
    }

    static func *= (left: inout CGPoint, right: CGFloat) {
        left.x *= right
        left.y *= right
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

// MARK: -

public extension CGFloat {
    var pointsAsPixels: CGFloat {
        self * UIScreen.main.scale
    }

    // An epsilon is a small, non-zero value.
    //
    // This value is _NOT_ an appropriate tolerance for fuzzy comparison,
    // e.g. fuzzyEquals().
    static var epsilon: CGFloat {
        // ulpOfOne is the difference between 1.0 and the next largest CGFloat value.
        .ulpOfOne
    }
}

// MARK: -

extension UIGestureRecognizer {
    @objc
    public var stateString: String {
        switch state {
        case .possible:
            return "UIGestureRecognizerStatePossible"
        case .began:
            return "UIGestureRecognizerStateBegan"
        case .changed:
            return "UIGestureRecognizerStateChanged"
        case .ended:
            return "UIGestureRecognizerStateEnded"
        case .cancelled:
            return "UIGestureRecognizerStateCancelled"
        case .failed:
            return "UIGestureRecognizerStateFailed"
        default:
            return "Unknown"
        }
    }
}
