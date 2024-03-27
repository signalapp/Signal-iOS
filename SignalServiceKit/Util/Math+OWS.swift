//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension CGFloat {
    func clamp(_ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        return CGFloatClamp(self, minValue, maxValue)
    }

    func clamp01() -> CGFloat {
        return CGFloatClamp01(self)
    }

    /// Returns a random value within the specified range with a fixed number of discrete choices.
    ///
    /// ```
    /// CGFloat.random(in: 0..10, choices: 2)  // => 5
    /// CGFloat.random(in: 0..10, choices: 2)  // => 0
    /// CGFloat.random(in: 0..10, choices: 2)  // => 5
    ///
    /// CGFloat.random(in: 0..10, choices: 10)  // => 8
    /// CGFloat.random(in: 0..10, choices: 10)  // => 4
    /// CGFloat.random(in: 0..10, choices: 10)  // => 0
    /// ```
    ///
    /// - Parameters:
    ///   - range: The range in which to create a random value.
    ///     `range` must be finite and nonempty.
    ///   - choices: The number of discrete choices for the result.
    /// - Returns: A random value within the bounds of `range`, constrained to the number of `choices`.
    static func random(in range: Range<CGFloat>, choices: UInt) -> CGFloat {
        let rangeSize = range.upperBound - range.lowerBound
        let choice = UInt.random(in: 0..<choices)
        return range.lowerBound + (rangeSize * CGFloat(choice) / CGFloat(choices))
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

    func average(_ other: CGFloat) -> CGFloat {
        (self + other) * 0.5
    }
}

// MARK: -

public extension Double {
    func clamp(_ minValue: Double, _ maxValue: Double) -> Double {
        return max(minValue, min(maxValue, self))
    }

    func clamp01() -> Double {
        return clamp(0, 1)
    }

    // Linear interpolation
    func lerp(_ minValue: Double, _ maxValue: Double) -> Double {
        return (minValue * (1 - self)) + (maxValue * self)
    }

    // Inverse linear interpolation
    func inverseLerp(_ minValue: Double, _ maxValue: Double, shouldClamp: Bool = false) -> Double {
        let value = (self - minValue) / (maxValue - minValue)
        return (shouldClamp ? value.clamp01() : value)
    }
}

// MARK: -

public extension Float {
    func clamp(_ minValue: Float, _ maxValue: Float) -> Float {
        return max(minValue, min(maxValue, self))
    }

    func clamp01() -> Float {
        return clamp(0, 1)
    }

    // Linear interpolation
    func lerp(_ minValue: Float, _ maxValue: Float) -> Float {
        return (minValue * (1 - self)) + (maxValue * self)
    }

    // Inverse linear interpolation
    func inverseLerp(_ minValue: Float, _ maxValue: Float, shouldClamp: Bool = false) -> Float {
        let value = (self - minValue) / (maxValue - minValue)
        return (shouldClamp ? value.clamp01() : value)
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

public extension UInt {
    func clamp(_ minValue: UInt, _ maxValue: UInt) -> UInt {
        assert(minValue <= maxValue)

        return Swift.max(minValue, Swift.min(maxValue, self))
    }
}

// MARK: -

public extension UInt64 {
    var asNSNumber: NSNumber {
        NSNumber(value: self)
    }
}

// MARK: -

public extension Bool {
    static func ^ (left: Bool, right: Bool) -> Bool {
        return left != right
    }
}
