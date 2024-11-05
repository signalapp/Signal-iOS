//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
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
}

extension UIKit.UIColor.Signal {
    public static var background: UIColor {
        UIColor.byUserInterfaceLevel(
            base: UIColor.Signal.BackgroundLevels.backgroundBase,
            elevated: UIColor.Signal.BackgroundLevels.backgroundElevated
        )
    }

    public static var secondaryBackground: UIColor {
        if #available(iOS 16.0, *) {
            UIColor.byUserInterfaceLevel(
                base: UIColor.Signal.BackgroundLevels.secondaryBackgroundBase,
                elevated: UIColor.Signal.BackgroundLevels.secondaryBackgroundElevated
            )
        } else {
            UIColor.secondarySystemBackground
        }
    }

    public static var tertiaryBackground: UIColor {
        UIColor.byUserInterfaceLevel(
            base: UIColor.Signal.BackgroundLevels.tertiaryBackgroundBase,
            elevated: UIColor.Signal.BackgroundLevels.tertiaryBackgroundElevated
        )
    }

    public static var groupedBackground: UIColor {
        if #available(iOS 16.0, *) {
            UIColor.byUserInterfaceLevel(
                base: UIColor.Signal.BackgroundLevels.groupedBackgroundBase,
                elevated: UIColor.Signal.BackgroundLevels.groupedBackgroundElevated
            )
        } else {
            UIColor.systemGroupedBackground
        }
    }

    public static var secondaryGroupedBackground: UIColor {
        UIColor.byUserInterfaceLevel(
            base: UIColor.Signal.BackgroundLevels.secondaryGroupedBackgroundBase,
            elevated: UIColor.Signal.BackgroundLevels.secondaryGroupedBackgroundElevated
        )
    }

    public static var tertiaryGroupedBackground: UIColor {
        if #available(iOS 16.0, *) {
            UIColor.byUserInterfaceLevel(
                base: UIColor.Signal.BackgroundLevels.tertiaryGroupedBackgroundBase,
                elevated: UIColor.Signal.BackgroundLevels.tertiaryGroupedBackgroundElevated
            )
        } else {
            UIColor.tertiarySystemGroupedBackground
        }
    }

    public static var accent: UIColor { UIColor.Signal.ultramarine }
}

extension SwiftUI.Color.Signal {
    public static var background: Color {
        Color(uiColor: UIColor.Signal.background)
    }

    public static var secondaryBackground: Color {
        Color(uiColor: UIColor.Signal.secondaryBackground)
    }

    public static var tertiaryBackground: Color {
        Color(uiColor: UIColor.Signal.tertiaryBackground)
    }

    public static var groupedBackground: Color {
        Color(uiColor: UIColor.Signal.groupedBackground)
    }

    public static var secondaryGroupedBackground: Color {
        Color(uiColor: UIColor.Signal.secondaryGroupedBackground)
    }

    public static var tertiaryGroupedBackground: Color {
        Color(uiColor: UIColor.Signal.tertiaryGroupedBackground)
    }

    public static var accent: Color { Color.Signal.ultramarine }
}

// MARK: - GeneratedAssetSymbols.swift -

// The below is selectively copy-and-pasted from GeneratedAssetSymbols.swift,
// with access control updated and unnecessary OS compiler checks removed.

import DeveloperToolsSupport

private let resourceBundle = Foundation.Bundle.main

// MARK: - Color Symbols -

extension ColorResource {

    /// The "Signal" asset catalog resource namespace.
    public enum Signal {

        /// The "Signal/BackgroundLevels" asset catalog resource namespace.
        fileprivate enum BackgroundLevels {

            /// The "Signal/BackgroundLevels/backgroundBase" asset catalog color resource.
            static let backgroundBase = ColorResource(name: "Signal/BackgroundLevels/backgroundBase", bundle: resourceBundle)

            /// The "Signal/BackgroundLevels/backgroundElevated" asset catalog color resource.
            static let backgroundElevated = ColorResource(name: "Signal/BackgroundLevels/backgroundElevated", bundle: resourceBundle)

            /// The "Signal/BackgroundLevels/groupedBackgroundBase" asset catalog color resource.
            static let groupedBackgroundBase = ColorResource(name: "Signal/BackgroundLevels/groupedBackgroundBase", bundle: resourceBundle)

            /// The "Signal/BackgroundLevels/groupedBackgroundElevated" asset catalog color resource.
            static let groupedBackgroundElevated = ColorResource(name: "Signal/BackgroundLevels/groupedBackgroundElevated", bundle: resourceBundle)

            /// The "Signal/BackgroundLevels/secondaryBackgroundBase" asset catalog color resource.
            static let secondaryBackgroundBase = ColorResource(name: "Signal/BackgroundLevels/secondaryBackgroundBase", bundle: resourceBundle)

            /// The "Signal/BackgroundLevels/secondaryBackgroundElevated" asset catalog color resource.
            static let secondaryBackgroundElevated = ColorResource(name: "Signal/BackgroundLevels/secondaryBackgroundElevated", bundle: resourceBundle)

            /// The "Signal/BackgroundLevels/secondaryGroupedBackgroundBase" asset catalog color resource.
            static let secondaryGroupedBackgroundBase = ColorResource(name: "Signal/BackgroundLevels/secondaryGroupedBackgroundBase", bundle: resourceBundle)

            /// The "Signal/BackgroundLevels/secondaryGroupedBackgroundElevated" asset catalog color resource.
            static let secondaryGroupedBackgroundElevated = ColorResource(name: "Signal/BackgroundLevels/secondaryGroupedBackgroundElevated", bundle: resourceBundle)

            /// The "Signal/BackgroundLevels/tertiaryBackgroundBase" asset catalog color resource.
            static let tertiaryBackgroundBase = ColorResource(name: "Signal/BackgroundLevels/tertiaryBackgroundBase", bundle: resourceBundle)

            /// The "Signal/BackgroundLevels/tertiaryBackgroundElevated" asset catalog color resource.
            static let tertiaryBackgroundElevated = ColorResource(name: "Signal/BackgroundLevels/tertiaryBackgroundElevated", bundle: resourceBundle)

            /// The "Signal/BackgroundLevels/tertiaryGroupedBackgroundBase" asset catalog color resource.
            static let tertiaryGroupedBackgroundBase = ColorResource(name: "Signal/BackgroundLevels/tertiaryGroupedBackgroundBase", bundle: resourceBundle)

            /// The "Signal/BackgroundLevels/tertiaryGroupedBackgroundElevated" asset catalog color resource.
            static let tertiaryGroupedBackgroundElevated = ColorResource(name: "Signal/BackgroundLevels/tertiaryGroupedBackgroundElevated", bundle: resourceBundle)

        }

        /// The "Signal/green" asset catalog color resource.
        public static let green = ColorResource(name: "Signal/green", bundle: resourceBundle)

        /// The "Signal/indigo" asset catalog color resource.
        public static let indigo = ColorResource(name: "Signal/indigo", bundle: resourceBundle)

        /// The "Signal/label" asset catalog color resource.
        public static let label = ColorResource(name: "Signal/label", bundle: resourceBundle)

        /// The "Signal/opaqueSeparator" asset catalog color resource.
        public static let opaqueSeparator = ColorResource(name: "Signal/opaqueSeparator", bundle: resourceBundle)

        /// The "Signal/orange" asset catalog color resource.
        public static let orange = ColorResource(name: "Signal/orange", bundle: resourceBundle)

        /// The "Signal/primaryFill" asset catalog color resource.
        public static let primaryFill = ColorResource(name: "Signal/primaryFill", bundle: resourceBundle)

        /// The "Signal/quaternaryFill" asset catalog color resource.
        public static let quaternaryFill = ColorResource(name: "Signal/quaternaryFill", bundle: resourceBundle)

        /// The "Signal/quaternaryLabel" asset catalog color resource.
        public static let quaternaryLabel = ColorResource(name: "Signal/quaternaryLabel", bundle: resourceBundle)

        /// The "Signal/red" asset catalog color resource.
        public static let red = ColorResource(name: "Signal/red", bundle: resourceBundle)

        /// The "Signal/secondaryFill" asset catalog color resource.
        public static let secondaryFill = ColorResource(name: "Signal/secondaryFill", bundle: resourceBundle)

        /// The "Signal/secondaryLabel" asset catalog color resource.
        public static let secondaryLabel = ColorResource(name: "Signal/secondaryLabel", bundle: resourceBundle)

        /// The "secondaryUltramarineBackground" asset catalog color resource.
        public static let secondaryUltramarineBackground = ColorResource(name: "Signal/secondaryUltramarineBackground", bundle: resourceBundle)

        /// The "Signal/tertiaryFill" asset catalog color resource.
        public static let tertiaryFill = ColorResource(name: "Signal/tertiaryFill", bundle: resourceBundle)

        /// The "Signal/tertiaryLabel" asset catalog color resource.
        public static let tertiaryLabel = ColorResource(name: "Signal/tertiaryLabel", bundle: resourceBundle)

        /// The "Signal/transparentSeparator" asset catalog color resource.
        public static let transparentSeparator = ColorResource(name: "Signal/transparentSeparator", bundle: resourceBundle)

        /// The "Signal/ultramarine" asset catalog color resource.
        public static let ultramarine = ColorResource(name: "Signal/ultramarine", bundle: resourceBundle)

        /// The "Signal/yellow" asset catalog color resource.
        public static let yellow = ColorResource(name: "Signal/yellow", bundle: resourceBundle)

    }

}

// MARK: - UIKit Color Symbol Extensions -

extension UIKit.UIColor {

    /// The "Signal" asset catalog resource namespace.
    public enum Signal {

        /// The "Signal/BackgroundLevels" asset catalog resource namespace.
        fileprivate enum BackgroundLevels {

            /// The "Signal/BackgroundLevels/backgroundBase" asset catalog color.
            static var backgroundBase: UIKit.UIColor {
                .init(resource: .Signal.BackgroundLevels.backgroundBase)
            }

            /// The "Signal/BackgroundLevels/backgroundElevated" asset catalog color.
            static var backgroundElevated: UIKit.UIColor {
                .init(resource: .Signal.BackgroundLevels.backgroundElevated)
            }

            /// The "Signal/BackgroundLevels/groupedBackgroundBase" asset catalog color.
            static var groupedBackgroundBase: UIKit.UIColor {
                .init(resource: .Signal.BackgroundLevels.groupedBackgroundBase)
            }

            /// The "Signal/BackgroundLevels/groupedBackgroundElevated" asset catalog color.
            static var groupedBackgroundElevated: UIKit.UIColor {
                .init(resource: .Signal.BackgroundLevels.groupedBackgroundElevated)
            }

            /// The "Signal/BackgroundLevels/secondaryBackgroundBase" asset catalog color.
            static var secondaryBackgroundBase: UIKit.UIColor {
                .init(resource: .Signal.BackgroundLevels.secondaryBackgroundBase)
            }

            /// The "Signal/BackgroundLevels/secondaryBackgroundElevated" asset catalog color.
            static var secondaryBackgroundElevated: UIKit.UIColor {
                .init(resource: .Signal.BackgroundLevels.secondaryBackgroundElevated)
            }

            /// The "Signal/BackgroundLevels/secondaryGroupedBackgroundBase" asset catalog color.
            static var secondaryGroupedBackgroundBase: UIKit.UIColor {
                .init(resource: .Signal.BackgroundLevels.secondaryGroupedBackgroundBase)
            }

            /// The "Signal/BackgroundLevels/secondaryGroupedBackgroundElevated" asset catalog color.
            static var secondaryGroupedBackgroundElevated: UIKit.UIColor {
                .init(resource: .Signal.BackgroundLevels.secondaryGroupedBackgroundElevated)
            }

            /// The "Signal/BackgroundLevels/tertiaryBackgroundBase" asset catalog color.
            static var tertiaryBackgroundBase: UIKit.UIColor {
                .init(resource: .Signal.BackgroundLevels.tertiaryBackgroundBase)
            }

            /// The "Signal/BackgroundLevels/tertiaryBackgroundElevated" asset catalog color.
            static var tertiaryBackgroundElevated: UIKit.UIColor {
                .init(resource: .Signal.BackgroundLevels.tertiaryBackgroundElevated)
            }

            /// The "Signal/BackgroundLevels/tertiaryGroupedBackgroundBase" asset catalog color.
            static var tertiaryGroupedBackgroundBase: UIKit.UIColor {
                .init(resource: .Signal.BackgroundLevels.tertiaryGroupedBackgroundBase)
            }

            /// The "Signal/BackgroundLevels/tertiaryGroupedBackgroundElevated" asset catalog color.
            static var tertiaryGroupedBackgroundElevated: UIKit.UIColor {
                .init(resource: .Signal.BackgroundLevels.tertiaryGroupedBackgroundElevated)
            }

        }

        /// The "Signal/green" asset catalog color.
        public static var green: UIKit.UIColor {
            .init(resource: .Signal.green)
        }

        /// The "Signal/indigo" asset catalog color.
        public static var indigo: UIKit.UIColor {
            .init(resource: .Signal.indigo)
        }

        /// The "Signal/label" asset catalog color.
        public static var label: UIKit.UIColor {
            .init(resource: .Signal.label)
        }

        /// The "Signal/opaqueSeparator" asset catalog color.
        public static var opaqueSeparator: UIKit.UIColor {
            .init(resource: .Signal.opaqueSeparator)
        }

        /// The "Signal/orange" asset catalog color.
        public static var orange: UIKit.UIColor {
            .init(resource: .Signal.orange)
        }

        /// The "Signal/primaryFill" asset catalog color.
        public static var primaryFill: UIKit.UIColor {
            .init(resource: .Signal.primaryFill)
        }

        /// The "Signal/quaternaryFill" asset catalog color.
        public static var quaternaryFill: UIKit.UIColor {
            .init(resource: .Signal.quaternaryFill)
        }

        /// The "Signal/quaternaryLabel" asset catalog color.
        public static var quaternaryLabel: UIKit.UIColor {
            .init(resource: .Signal.quaternaryLabel)
        }

        /// The "Signal/red" asset catalog color.
        public static var red: UIKit.UIColor {
            .init(resource: .Signal.red)
        }

        /// The "Signal/secondaryFill" asset catalog color.
        public static var secondaryFill: UIKit.UIColor {
            .init(resource: .Signal.secondaryFill)
        }

        /// The "Signal/secondaryLabel" asset catalog color.
        public static var secondaryLabel: UIKit.UIColor {
            .init(resource: .Signal.secondaryLabel)
        }

        /// The "secondaryUltramarineBackground" asset catalog color.
        public static var secondaryUltramarineBackground: UIKit.UIColor {
            .init(resource: .Signal.secondaryUltramarineBackground)
        }

        /// The "Signal/tertiaryFill" asset catalog color.
        public static var tertiaryFill: UIKit.UIColor {
            .init(resource: .Signal.tertiaryFill)
        }

        /// The "Signal/tertiaryLabel" asset catalog color.
        public static var tertiaryLabel: UIKit.UIColor {
            .init(resource: .Signal.tertiaryLabel)
        }

        /// The "Signal/transparentSeparator" asset catalog color.
        public static var transparentSeparator: UIKit.UIColor {
            .init(resource: .Signal.transparentSeparator)
        }

        /// The "Signal/ultramarine" asset catalog color.
        public static var ultramarine: UIKit.UIColor {
            .init(resource: .Signal.ultramarine)
        }

        /// The "Signal/yellow" asset catalog color.
        public static var yellow: UIKit.UIColor {
            .init(resource: .Signal.yellow)
        }

    }

}

// MARK: - SwiftUI Color Symbol Extensions -

extension SwiftUI.Color {

    /// The "Signal" asset catalog resource namespace.
    public enum Signal {

        /// The "Signal/BackgroundLevels" asset catalog resource namespace.
        fileprivate enum BackgroundLevels {

            /// The "Signal/BackgroundLevels/backgroundBase" asset catalog color.
            static var backgroundBase: SwiftUI.Color { .init(.Signal.BackgroundLevels.backgroundBase) }

            /// The "Signal/BackgroundLevels/backgroundElevated" asset catalog color.
            static var backgroundElevated: SwiftUI.Color { .init(.Signal.BackgroundLevels.backgroundElevated) }

            /// The "Signal/BackgroundLevels/groupedBackgroundBase" asset catalog color.
            static var groupedBackgroundBase: SwiftUI.Color { .init(.Signal.BackgroundLevels.groupedBackgroundBase) }

            /// The "Signal/BackgroundLevels/groupedBackgroundElevated" asset catalog color.
            static var groupedBackgroundElevated: SwiftUI.Color { .init(.Signal.BackgroundLevels.groupedBackgroundElevated) }

            /// The "Signal/BackgroundLevels/secondaryBackgroundBase" asset catalog color.
            static var secondaryBackgroundBase: SwiftUI.Color { .init(.Signal.BackgroundLevels.secondaryBackgroundBase) }

            /// The "Signal/BackgroundLevels/secondaryBackgroundElevated" asset catalog color.
            static var secondaryBackgroundElevated: SwiftUI.Color { .init(.Signal.BackgroundLevels.secondaryBackgroundElevated) }

            /// The "Signal/BackgroundLevels/secondaryGroupedBackgroundBase" asset catalog color.
            static var secondaryGroupedBackgroundBase: SwiftUI.Color { .init(.Signal.BackgroundLevels.secondaryGroupedBackgroundBase) }

            /// The "Signal/BackgroundLevels/secondaryGroupedBackgroundElevated" asset catalog color.
            static var secondaryGroupedBackgroundElevated: SwiftUI.Color { .init(.Signal.BackgroundLevels.secondaryGroupedBackgroundElevated) }

            /// The "Signal/BackgroundLevels/tertiaryBackgroundBase" asset catalog color.
            static var tertiaryBackgroundBase: SwiftUI.Color { .init(.Signal.BackgroundLevels.tertiaryBackgroundBase) }

            /// The "Signal/BackgroundLevels/tertiaryBackgroundElevated" asset catalog color.
            static var tertiaryBackgroundElevated: SwiftUI.Color { .init(.Signal.BackgroundLevels.tertiaryBackgroundElevated) }

            /// The "Signal/BackgroundLevels/tertiaryGroupedBackgroundBase" asset catalog color.
            static var tertiaryGroupedBackgroundBase: SwiftUI.Color { .init(.Signal.BackgroundLevels.tertiaryGroupedBackgroundBase) }

            /// The "Signal/BackgroundLevels/tertiaryGroupedBackgroundElevated" asset catalog color.
            static var tertiaryGroupedBackgroundElevated: SwiftUI.Color { .init(.Signal.BackgroundLevels.tertiaryGroupedBackgroundElevated) }

        }

        /// The "Signal/green" asset catalog color.
        public static var green: SwiftUI.Color { .init(.Signal.green) }

        /// The "Signal/indigo" asset catalog color.
        public static var indigo: SwiftUI.Color { .init(.Signal.indigo) }

        /// The "Signal/label" asset catalog color.
        public static var label: SwiftUI.Color { .init(.Signal.label) }

        /// The "Signal/opaqueSeparator" asset catalog color.
        public static var opaqueSeparator: SwiftUI.Color { .init(.Signal.opaqueSeparator) }

        /// The "Signal/orange" asset catalog color.
        public static var orange: SwiftUI.Color { .init(.Signal.orange) }

        /// The "Signal/primaryFill" asset catalog color.
        public static var primaryFill: SwiftUI.Color { .init(.Signal.primaryFill) }

        /// The "Signal/quaternaryFill" asset catalog color.
        public static var quaternaryFill: SwiftUI.Color { .init(.Signal.quaternaryFill) }

        /// The "Signal/quaternaryLabel" asset catalog color.
        public static var quaternaryLabel: SwiftUI.Color { .init(.Signal.quaternaryLabel) }

        /// The "Signal/red" asset catalog color.
        public static var red: SwiftUI.Color { .init(.Signal.red) }

        /// The "Signal/secondaryFill" asset catalog color.
        public static var secondaryFill: SwiftUI.Color { .init(.Signal.secondaryFill) }

        /// The "Signal/secondaryLabel" asset catalog color.
        public static var secondaryLabel: SwiftUI.Color { .init(.Signal.secondaryLabel) }

        /// The "Signal/secondaryUltramarineBackground" asset catalog color.
        public static var secondaryUltramarineBackground: SwiftUI.Color { .init(.Signal.secondaryUltramarineBackground) }

        /// The "Signal/tertiaryFill" asset catalog color.
        public static var tertiaryFill: SwiftUI.Color { .init(.Signal.tertiaryFill) }

        /// The "Signal/tertiaryLabel" asset catalog color.
        public static var tertiaryLabel: SwiftUI.Color { .init(.Signal.tertiaryLabel) }

        /// The "Signal/transparentSeparator" asset catalog color.
        public static var transparentSeparator: SwiftUI.Color { .init(.Signal.transparentSeparator) }

        /// The "Signal/ultramarine" asset catalog color.
        public static var ultramarine: SwiftUI.Color { .init(.Signal.ultramarine) }

        /// The "Signal/yellow" asset catalog color.
        public static var yellow: SwiftUI.Color { .init(.Signal.yellow) }

    }

}

// MARK: - Backwards Deployment Support -

/// A color resource.
struct ColorResource: Swift.Hashable, Swift.Sendable {
    /// An asset catalog color resource name.
    fileprivate let name: Swift.String

    /// An asset catalog color resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize a `ColorResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }
}

extension UIKit.UIColor {
    /// Initialize a `UIColor` with a color resource.
    convenience init(resource: ColorResource) {
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
    }
}

extension SwiftUI.Color {
    /// Initialize a `Color` with a color resource.
    init(_ resource: ColorResource) {
        self.init(resource.name, bundle: resource.bundle)
    }
}
