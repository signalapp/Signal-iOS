//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalServiceKit
public import SwiftUI

// MARK: - Custom Colors -

extension UIColor {
    fileprivate static func byUserInterfaceLevel(
        base: UIColor,
        elevated: UIColor
    ) -> UIColor {
        UIColor { traitCollection in
            if traitCollection.userInterfaceLevel == .elevated {
                elevated
            } else {
                base
            }
        }
    }

    public static func byRGBHex(
        light: UInt32,
        lightHighContrast: UInt32,
        dark: UInt32,
        darkHighContrast: UInt32
    ) -> UIColor {
        UIColor(
            light: UIColor(rgbHex: light),
            lightHighContrast: UIColor(rgbHex: lightHighContrast),
            dark: UIColor(rgbHex: dark),
            darkHighContrast: UIColor(rgbHex: darkHighContrast)
        )
    }

    public convenience init(
        light: UIColor,
        lightHighContrast: UIColor,
        dark: UIColor,
        darkHighContrast: UIColor
    ) {
        self.init { traitCollection in
            switch (traitCollection.userInterfaceStyle, traitCollection.accessibilityContrast) {
            case (.dark, .high):
                darkHighContrast
            case (.dark, _):
                dark
            case (_, .high):
                lightHighContrast
            case (_, _):
                light
            }
        }
    }
}

// MARK: - UIKit

extension UIColor {
    public enum Signal {}
}

extension UIColor.Signal {

    // MARK: Accent

    public static var ultramarine: UIColor {
        UIColor.byRGBHex(
            light: 0x2267F5,
            lightHighContrast: 0x0A43B9,
            dark: 0x2D70FA,
            darkHighContrast: 0x5D92FF
        )
    }

    public static var red: UIColor {
        UIColor.byRGBHex(
            light: 0xFF3B30,
            lightHighContrast: 0xD70015,
            dark: 0xFF453A,
            darkHighContrast: 0xFF6961
        )
    }

    public static var orange: UIColor {
        UIColor.byRGBHex(
            light: 0xFF9500,
            lightHighContrast: 0xC93400,
            dark: 0xFF9F0A,
            darkHighContrast: 0xFFB340
        )
    }

    public static var yellow: UIColor {
        UIColor.byRGBHex(
            light: 0xFFCC00,
            lightHighContrast: 0xB25000,
            dark: 0xFFD60A,
            darkHighContrast: 0xFFD426
        )
    }

    public static var green: UIColor {
        UIColor.byRGBHex(
            light: 0x34C759,
            lightHighContrast: 0x248A3D,
            dark: 0x30D158,
            darkHighContrast: 0x30DB5B
        )
    }

    public static var indigo: UIColor {
        UIColor.byRGBHex(
            light: 0x5856D6,
            lightHighContrast: 0x3634A3,
            dark: 0x5E5CE6,
            darkHighContrast: 0x7D7AFF
        )
    }

    public static var accent: UIColor { ultramarine }

    // MARK: Label

    public static var label: UIColor {
        UIColor(
            light: UIColor(rgbHex: 0x000000),
            lightHighContrast: UIColor(rgbHex: 0x000000),
            dark: UIColor(rgbHex: 0xFFFFFF),
            darkHighContrast: UIColor(rgbHex: 0xFFFFFF)
        )
    }

    public static var secondaryLabel: UIColor {
        UIColor(
            light: UIColor(rgbHex: 0x3C3C43, alpha: 0.72),
            lightHighContrast: UIColor(rgbHex: 0x3C3C43, alpha: 0.95),
            dark: UIColor(rgbHex: 0xEBEBF5, alpha: 0.7),
            darkHighContrast: UIColor(rgbHex: 0xEBEBF5, alpha: 0.8)
        )
    }

    public static var tertiaryLabel: UIColor {
        UIColor(
            light: UIColor(rgbHex: 0x3C3C43, alpha: 0.3),
            lightHighContrast: UIColor(rgbHex: 0x3C3C43, alpha: 0.5),
            dark: UIColor(rgbHex: 0xEBEBF5, alpha: 0.3),
            darkHighContrast: UIColor(rgbHex: 0xEBEBF5, alpha: 0.4)
        )
    }

    public static var quaternaryLabel: UIColor {
        UIColor(
            light: UIColor(rgbHex: 0x3C3C43, alpha: 0.18),
            lightHighContrast: UIColor(rgbHex: 0x3C3C43, alpha: 0.4),
            dark: UIColor(rgbHex: 0xEBEBF5, alpha: 0.16),
            darkHighContrast: UIColor(rgbHex: 0xEBEBF5, alpha: 0.26)
        )
    }

    // MARK: Background

    public static var background: UIColor {
        UIColor.byUserInterfaceLevel(
            base: UIColor.byRGBHex(
                light: 0xFFFFFF,
                lightHighContrast: 0xFFFFFF,
                dark: 0x000000,
                darkHighContrast: 0x000000
            ),
            elevated: UIColor.byRGBHex(
                light: 0xFFFFFF,
                lightHighContrast: 0xFFFFFF,
                dark: 0x1C1C1E,
                darkHighContrast: 0x343438
            )
        )
    }

    public static var secondaryBackground: UIColor {
        UIColor.byUserInterfaceLevel(
            base: UIColor.byRGBHex(
                light: 0xEFEFF0,
                lightHighContrast: 0xE4E4E7,
                dark: 0x1C1C1E,
                darkHighContrast: 0x343438
            ),
            elevated: UIColor.byRGBHex(
                light: 0xEFEFF0,
                lightHighContrast: 0xE4E4E7,
                dark: 0x2C2C2E,
                darkHighContrast: 0x444447
            )
        )
    }

    public static var tertiaryBackground: UIColor {
        UIColor.byUserInterfaceLevel(
            base: UIColor.byRGBHex(
                light: 0xFFFFFF,
                lightHighContrast: 0xFFFFFF,
                dark: 0x2C2C2E,
                darkHighContrast: 0x444447
            ),
            elevated: UIColor.byRGBHex(
                light: 0xFFFFFF,
                lightHighContrast: 0xFFFFFF,
                dark: 0x3A3A3C,
                darkHighContrast: 0x545457
            )
        )
    }

    public static var secondaryUltramarineBackground: UIColor {
        UIColor(rgbHex: 0xC7DDFB)
    }

    // MARK: Grouped Background

    public static var groupedBackground: UIColor {
        UIColor.byUserInterfaceLevel(
            base: UIColor.byRGBHex(
                light: 0xEFEFF0,
                lightHighContrast: 0xE4E4E7,
                dark: 0x000000,
                darkHighContrast: 0x000000
            ),
            elevated: UIColor.byRGBHex(
                light: 0xEFEFF0,
                lightHighContrast: 0xE4E4E7,
                dark: 0x1C1C1E,
                darkHighContrast: 0x343438
            )
        )
    }

    public static var secondaryGroupedBackground: UIColor {
        UIColor.byUserInterfaceLevel(
            base: UIColor.byRGBHex(
                light: 0xFFFFFF,
                lightHighContrast: 0xFFFFFF,
                dark: 0x1C1C1E,
                darkHighContrast: 0x343438
            ),
            elevated: UIColor.byRGBHex(
                light: 0xFFFFFF,
                lightHighContrast: 0xFFFFFF,
                dark: 0x2C2C2E,
                darkHighContrast: 0x444447
            )
        )
    }

    public static var tertiaryGroupedBackground: UIColor {
        UIColor.byUserInterfaceLevel(
            base: UIColor.byRGBHex(
                light: 0xEFEFF0,
                lightHighContrast: 0xE4E4E7,
                dark: 0x2C2C2E,
                darkHighContrast: 0x444447
            ),
            elevated: UIColor.byRGBHex(
                light: 0xEFEFF0,
                lightHighContrast: 0xE4E4E7,
                dark: 0x3A3A3C,
                darkHighContrast: 0x545457
            )
        )
    }

    // MARK: Fill

    public static var primaryFill: UIColor {
        UIColor(
            light: UIColor(rgbHex: 0x787880, alpha: 0.2),
            lightHighContrast: UIColor(rgbHex: 0x787880, alpha: 0.3),
            dark: UIColor(rgbHex: 0x787880, alpha: 0.36),
            darkHighContrast: UIColor(rgbHex: 0x787880, alpha: 0.46)
        )
    }

    public static var secondaryFill: UIColor {
        UIColor(
            light: UIColor(rgbHex: 0x787880, alpha: 0.16),
            lightHighContrast: UIColor(rgbHex: 0x787880, alpha: 0.26),
            dark: UIColor(rgbHex: 0x787880, alpha: 0.32),
            darkHighContrast: UIColor(rgbHex: 0x787880, alpha: 0.42)
        )
    }

    public static var tertiaryFill: UIColor {
        UIColor(
            light: UIColor(rgbHex: 0x767680, alpha: 0.12),
            lightHighContrast: UIColor(rgbHex: 0x767680, alpha: 0.22),
            dark: UIColor(rgbHex: 0x767680, alpha: 0.24),
            darkHighContrast: UIColor(rgbHex: 0x767680, alpha: 0.34)
        )
    }

    public static var quaternaryFill: UIColor {
        UIColor(
            light: UIColor(rgbHex: 0x747480, alpha: 0.08),
            lightHighContrast: UIColor(rgbHex: 0x747480, alpha: 0.18),
            dark: UIColor(rgbHex: 0x747480, alpha: 0.18),
            darkHighContrast: UIColor(rgbHex: 0x747480, alpha: 0.28)
        )
    }

    // MARK: Separator

    public static var opaqueSeparator: UIColor {
        UIColor.byRGBHex(
            light: 0xC6C6C8,
            lightHighContrast: 0xAEAEB2,
            dark: 0x38383A,
            darkHighContrast: 0x515154
        )
    }

    public static var transparentSeparator: UIColor {
        UIColor(
            light: UIColor(rgbHex: 0x3C3C43, alpha: 0.36),
            lightHighContrast: UIColor(rgbHex: 0x3C3C43, alpha: 0.46),
            dark: UIColor(rgbHex: 0x545458, alpha: 0.65),
            darkHighContrast: UIColor(rgbHex: 0x545458, alpha: 0.75)
        )
    }
}

// MARK: - SwiftUI

extension Color {
    public enum Signal {}
}

extension Color.Signal {

    // MARK: Accent

    public static var ultramarine: Color {
        Color(UIColor.Signal.ultramarine)
    }

    public static var red: Color {
        Color(UIColor.Signal.red)
    }

    public static var orange: Color {
        Color(UIColor.Signal.orange)
    }

    public static var yellow: Color {
        Color(UIColor.Signal.yellow)
    }

    public static var green: Color {
        Color(UIColor.Signal.green)
    }

    public static var indigo: Color {
        Color(UIColor.Signal.indigo)
    }

    public static var accent: Color { ultramarine }

    // MARK: Label

    public static var label: Color {
        Color(UIColor.Signal.label)
    }

    public static var secondaryLabel: Color {
        Color(UIColor.Signal.secondaryLabel)
    }

    public static var tertiaryLabel: Color {
        Color(UIColor.Signal.tertiaryLabel)
    }

    public static var quaternaryLabel: Color {
        Color(UIColor.Signal.quaternaryLabel)
    }

    // MARK: Background

    public static var background: Color {
        Color(UIColor.Signal.background)
    }

    public static var secondaryBackground: Color {
        Color(UIColor.Signal.secondaryBackground)
    }

    public static var tertiaryBackground: Color {
        Color(UIColor.Signal.tertiaryBackground)
    }

    // MARK: Grouped Background

    public static var groupedBackground: Color {
        Color(UIColor.Signal.groupedBackground)
    }

    public static var secondaryGroupedBackground: Color {
        Color(UIColor.Signal.secondaryGroupedBackground)
    }

    public static var tertiaryGroupedBackground: Color {
        Color(UIColor.Signal.tertiaryGroupedBackground)
    }

    // MARK: Fill

    public static var primaryFill: Color {
        Color(UIColor.Signal.primaryFill)
    }

    public static var secondaryFill: Color {
        Color(UIColor.Signal.secondaryFill)
    }

    public static var tertiaryFill: Color {
        Color(UIColor.Signal.tertiaryFill)
    }

    public static var quaternaryFill: Color {
        Color(UIColor.Signal.quaternaryFill)
    }

    // MARK: Separator

    public static var opaqueSeparator: Color {
        Color(UIColor.Signal.opaqueSeparator)
    }

    public static var transparentSeparator: Color {
        Color(UIColor.Signal.transparentSeparator)
    }

}
