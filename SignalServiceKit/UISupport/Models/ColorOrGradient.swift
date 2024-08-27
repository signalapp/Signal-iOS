//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// ColorOrGradientSetting is used for persistence and comparison.
// ColorOrGradientValue is used for rendering.
public enum ColorOrGradientSetting: Equatable, Codable {
    case solidColor(color: OWSColor)
    case themedColor(lightThemeColor: OWSColor, darkThemeColor: OWSColor)
    // If angleRadians = 0, gradientColor1 is N.
    // If angleRadians = PI / 2, gradientColor1 is E.
    // etc.
    case gradient(gradientColor1: OWSColor,
                  gradientColor2: OWSColor,
                  angleRadians: CGFloat)
    case themedGradient(lightGradientColor1: OWSColor,
                        lightGradientColor2: OWSColor,
                        darkGradientColor1: OWSColor,
                        darkGradientColor2: OWSColor,
                        angleRadians: CGFloat)

    private enum TypeKey: UInt, Codable {
        case solidColor = 0
        case gradient = 1
        case themedColor = 2
        case themedGradient = 3
    }

    private enum CodingKeys: String, CodingKey {
        case typeKey
        case solidColor
        case lightThemeColor
        case darkThemeColor
        case gradientColor1
        case gradientColor2
        case lightGradientColor1
        case lightGradientColor2
        case darkGradientColor1
        case darkGradientColor2
        case angleRadians
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let typeKey = try container.decode(TypeKey.self, forKey: .typeKey)
        switch typeKey {
        case .solidColor:
            let color = try container.decode(OWSColor.self, forKey: .solidColor)
            self = .solidColor(color: color)
        case .themedColor:
            let lightThemeColor = try container.decode(OWSColor.self, forKey: .lightThemeColor)
            let darkThemeColor = try container.decode(OWSColor.self, forKey: .darkThemeColor)
            self = .themedColor(lightThemeColor: lightThemeColor, darkThemeColor: darkThemeColor)
        case .gradient:
            let gradientColor1 = try container.decode(OWSColor.self, forKey: .gradientColor1)
            let gradientColor2 = try container.decode(OWSColor.self, forKey: .gradientColor2)
            let angleRadians = try container.decode(CGFloat.self, forKey: .angleRadians)
            self = .gradient(gradientColor1: gradientColor1,
                             gradientColor2: gradientColor2,
                             angleRadians: angleRadians)
        case .themedGradient:
            let lightGradientColor1 = try container.decode(OWSColor.self, forKey: .lightGradientColor1)
            let lightGradientColor2 = try container.decode(OWSColor.self, forKey: .lightGradientColor2)
            let darkGradientColor1 = try container.decode(OWSColor.self, forKey: .darkGradientColor1)
            let darkGradientColor2 = try container.decode(OWSColor.self, forKey: .darkGradientColor2)
            let angleRadians = try container.decode(CGFloat.self, forKey: .angleRadians)
            self = .themedGradient(lightGradientColor1: lightGradientColor1,
                                   lightGradientColor2: lightGradientColor2,
                                   darkGradientColor1: darkGradientColor1,
                                   darkGradientColor2: darkGradientColor2,
                                   angleRadians: angleRadians)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .solidColor(let solidColor):
            try container.encode(TypeKey.solidColor, forKey: .typeKey)
            try container.encode(solidColor, forKey: .solidColor)
        case .themedColor(let lightThemeColor, let darkThemeColor):
            try container.encode(TypeKey.themedColor, forKey: .typeKey)
            try container.encode(lightThemeColor, forKey: .lightThemeColor)
            try container.encode(darkThemeColor, forKey: .darkThemeColor)
        case .gradient(let gradientColor1, let gradientColor2, let angleRadians):
            try container.encode(TypeKey.gradient, forKey: .typeKey)
            try container.encode(gradientColor1, forKey: .gradientColor1)
            try container.encode(gradientColor2, forKey: .gradientColor2)
            try container.encode(angleRadians, forKey: .angleRadians)
        case .themedGradient(let lightGradientColor1,
                             let lightGradientColor2,
                             let darkGradientColor1,
                             let darkGradientColor2,
                             let angleRadians):
            try container.encode(TypeKey.themedGradient, forKey: .typeKey)
            try container.encode(lightGradientColor1, forKey: .lightGradientColor1)
            try container.encode(lightGradientColor2, forKey: .lightGradientColor2)
            try container.encode(darkGradientColor1, forKey: .darkGradientColor1)
            try container.encode(darkGradientColor2, forKey: .darkGradientColor2)
            try container.encode(angleRadians, forKey: .angleRadians)
        }
    }
}

// MARK: -

// We want a color model that...
//
// * ...can be safely, losslessly serialized.
// * ...is Equatable.
public struct OWSColor: Equatable, Codable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red.clamp01()
        self.green = green.clamp01()
        self.blue = blue.clamp01()
    }

    public var asUIColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }

    public var description: String {
        "[red: \(red), green: \(green), blue: \(blue)]"
    }
}
