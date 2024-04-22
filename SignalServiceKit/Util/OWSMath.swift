//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension CGFloat {
    @inlinable
    public static func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }

    @inlinable
    public static func clamp01(_ value: CGFloat) -> CGFloat {
        clamp(value, min: 0, max: 1)
    }

    @inlinable
    public static func lerp(left: CGFloat, right: CGFloat, alpha: CGFloat) -> CGFloat {
        (left * (1.0 - alpha)) + (right * alpha)
    }

    @inlinable
    public static func inverseLerp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        (value - min) / (max - min)
    }

    /// Ceil to an even number
    @inlinable
    public static func ceilEven(_ value: CGFloat) -> CGFloat {
        2.0 * Darwin.ceil(value * 0.5)
    }
}

extension CGSize {
    @inlinable
    public static func ceil(_ size: CGSize) -> CGSize {
        CGSize(width: Darwin.ceil(size.width), height: Darwin.ceil(size.height))
    }

    @inlinable
    public static func floor(_ size: CGSize) -> CGSize {
        CGSize(width: Darwin.floor(size.width), height: Darwin.floor(size.height))
    }

    @inlinable
    public static func round(_ size: CGSize) -> CGSize {
        CGSize(width: Darwin.round(size.width), height: Darwin.round(size.height))
    }

    @inlinable
    public static func max(_ a: CGSize, _ b: CGSize) -> CGSize {
        CGSize(width: Swift.max(a.width, b.width), height: Swift.max(a.height, b.height))
    }

    @inlinable
    public static func scale(_ size: CGSize, factor: CGFloat) -> CGSize {
        CGSize(width: size.width * factor, height: size.height * factor)
    }

    @inlinable
    public static func add(_ lhs: CGSize, _ rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}

extension CGPoint {
    @inlinable
    public static func add(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    @inlinable
    public static func subtract(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    @inlinable
    public static func scale(_ point: CGPoint, factor: CGFloat) -> CGPoint {
        CGPoint(x: point.x * factor, y: point.y * factor)
    }

    @inlinable
    public static func min(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: Swift.min(a.x, b.x), y: Swift.min(a.y, b.y))
    }

    @inlinable
    public static func max(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: Swift.max(a.x, b.x), y: Swift.max(a.y, b.y))
    }

    @inlinable
    public static func clamp01(_ point: CGPoint) -> CGPoint {
        CGPoint(x: CGFloat.clamp01(point.x), y: CGFloat.clamp01(point.y))
    }

    @inlinable
    public static func invert(_ point: CGPoint) -> CGPoint {
        CGPoint(x: -point.x, y: -point.y)
    }
}

extension CGRect {
    @inlinable
    public static func scale(_ rect: CGRect, factor: CGFloat) -> CGRect {
        CGRect(origin: CGPoint.scale(rect.origin, factor: factor),
               size: CGSize.scale(rect.size, factor: factor))
    }
}
