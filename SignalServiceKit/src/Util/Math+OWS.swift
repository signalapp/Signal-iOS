//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

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

public extension Bool {
    static func ^ (left: Bool, right: Bool) -> Bool {
        return left != right
    }
}
