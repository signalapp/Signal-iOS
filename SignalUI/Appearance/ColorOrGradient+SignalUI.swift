//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit
import UIKit

// MARK: -

/// ColorOrGradientSetting is used for persistence and comparison.
/// ColorOrGradientValue is used for rendering.
public enum ColorOrGradientValue: CustomStringConvertible {
    case transparent
    case solidColor(color: UIColor)
    /// If angleRadians = 0, gradientColor1 is N.
    /// If angleRadians = PI / 2, gradientColor1 is E.
    /// etc.
    case gradient(
        gradientColor1: UIColor,
        gradientColor2: UIColor,
        angleRadians: CGFloat
    )

    public var description: String {
        switch self {
        case .transparent:
            return "[transparent]"
        case .solidColor(let color):
            return "[solidColor: \(color.asOWSColor)]"
        case .gradient(let gradientColor1, let gradientColor2, let angleRadians):
            return "[gradient gradientColor1: \(gradientColor1.asOWSColor), gradientColor2: \(gradientColor2.asOWSColor), angleRadians: \(angleRadians)]"
        }
    }
}

// MARK: -

public enum ColorOrGradientThemeMode: Int {
    case auto
    case alwaysLight
    case alwaysDark
}

// MARK: -

public extension ColorOrGradientSetting {
    var asValue: ColorOrGradientValue {
        asValue(themeMode: .auto)
    }

    func asValue(themeMode: ColorOrGradientThemeMode) -> ColorOrGradientValue {
        let shouldUseDarkColors: Bool = {
            switch themeMode {
            case .auto:
                return Theme.isDarkThemeEnabled
            case .alwaysDark:
                return true
            case .alwaysLight:
                return false
            }
        }()

        switch self {
        case .solidColor(let solidColor):
            return .solidColor(color: solidColor.asUIColor)
        case .themedColor(let lightThemeColor, let darkThemeColor):
            let color = shouldUseDarkColors ? darkThemeColor : lightThemeColor
            return .solidColor(color: color.asUIColor)
        case .gradient(let gradientColor1, let gradientColor2, let angleRadians):
            return .gradient(
                gradientColor1: gradientColor1.asUIColor,
                gradientColor2: gradientColor2.asUIColor,
                angleRadians: angleRadians
            )
        case .themedGradient(
            let lightGradientColor1,
            let lightGradientColor2,
            let darkGradientColor1,
            let darkGradientColor2,
            let angleRadians
        ):
            let gradientColor1 = shouldUseDarkColors ? darkGradientColor1 : lightGradientColor1
            let gradientColor2 = shouldUseDarkColors ? darkGradientColor2 : lightGradientColor2
            return .gradient(
                gradientColor1: gradientColor1.asUIColor,
                gradientColor2: gradientColor2.asUIColor,
                angleRadians: angleRadians
            )
        }
    }
}

// MARK: -

public extension UIColor {
    var asOWSColor: OWSColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        self.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return OWSColor(red: red.clamp01(), green: green.clamp01(), blue: blue.clamp01())
    }
}
