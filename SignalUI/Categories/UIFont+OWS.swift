//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import UIKit

public extension UIFont {

    // MARK: - Icon Font

    class func awesomeFont(ofSize size: CGFloat) -> UIFont {
        return UIFont(name: "FontAwesome", size: size)!
    }

    // MARK: -

    class func regularFont(ofSize size: CGFloat) -> UIFont {
        return .systemFont(ofSize: size, weight: .regular)
    }

    class func semiboldFont(ofSize size: CGFloat) -> UIFont {
        return .systemFont(ofSize: size, weight: .semibold)
    }

    class func monospacedDigitFont(ofSize size: CGFloat) -> UIFont {
        return .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: - Dynamic Type

    class var dynamicTypeTitle1: UIFont { UIFont.preferredFont(forTextStyle: .title1) }

    class var dynamicTypeTitle2: UIFont { UIFont.preferredFont(forTextStyle: .title2) }

    class var dynamicTypeTitle3: UIFont { UIFont.preferredFont(forTextStyle: .title3) }

    class var dynamicTypeHeadline: UIFont { UIFont.preferredFont(forTextStyle: .headline) }

    class var dynamicTypeBody: UIFont { UIFont.preferredFont(forTextStyle: .body) }

    class var dynamicTypeBody2: UIFont { UIFont.preferredFont(forTextStyle: .subheadline) }

    class var dynamicTypeCallout: UIFont { UIFont.preferredFont(forTextStyle: .callout) }

    class var dynamicTypeSubheadline: UIFont { UIFont.preferredFont(forTextStyle: .subheadline) }

    class var dynamicTypeFootnote: UIFont { UIFont.preferredFont(forTextStyle: .footnote) }

    class var dynamicTypeCaption1: UIFont { UIFont.preferredFont(forTextStyle: .caption1) }

    class var dynamicTypeCaption2: UIFont { UIFont.preferredFont(forTextStyle: .caption2) }

    // MARK: - Dynamic Type Clamped

    // We clamp the dynamic type sizes at the max size available
    // without "larger accessibility sizes" enabled.
    static private var maxPointSizeMap: [UIFont.TextStyle: CGFloat] = [
        .title1: 34,
        .title2: 28,
        .title3: 26,
        .headline: 23,
        .body: 23,
        .callout: 22,
        .subheadline: 21,
        .footnote: 19,
        .caption1: 18,
        .caption2: 17,
        .largeTitle: 40
    ]

    private class func preferredFontClamped(forTextStyle textStyle: UIFont.TextStyle) -> UIFont {
        // From the documentation of -[id<UIContentSizeCategoryAdjusting> adjustsFontForContentSizeCategory:]
        // Dynamic sizing is only supported with fonts that are:
        // a. Vended using UIFont.preferredFont(forTextStyle:)
        // b. Vended from UIFontMetrics.scaledFont(for:) or one of its variants
        //
        // If we clamp fonts by checking the resulting point size and then creating a new, smaller UIFont with
        // a fallback max size, we'll lose dynamic sizing. Max sizes can be specified using UIFontMetrics though.
        //
        // UIFontMetrics will only operate on unscaled fonts. So we do this dance to cap the system default styles
        // 1. Grab the standard, unscaled font by using the default trait collection
        // 2. Use UIFontMetrics to scale it up, capped at the desired max size
        let defaultTraitCollection = UITraitCollection(preferredContentSizeCategory: .large)
        let unscaledFont = UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: defaultTraitCollection)

        let desiredStyleMetrics = UIFontMetrics(forTextStyle: textStyle)
        guard let maxPointSize = maxPointSizeMap[textStyle] else {
            owsFailDebug("Missing max point size for style: \(textStyle)")
            return desiredStyleMetrics.scaledFont(for: unscaledFont)
        }
        return desiredStyleMetrics.scaledFont(for: unscaledFont, maximumPointSize: maxPointSize)
    }

    class var dynamicTypeLargeTitle1Clamped: UIFont { preferredFontClamped(forTextStyle: .largeTitle) }
    class var dynamicTypeTitle1Clamped: UIFont { preferredFontClamped(forTextStyle: .title1) }
    class var dynamicTypeTitle2Clamped: UIFont { preferredFontClamped(forTextStyle: .title2) }
    class var dynamicTypeTitle3Clamped: UIFont { preferredFontClamped(forTextStyle: .title3) }
    class var dynamicTypeHeadlineClamped: UIFont { preferredFontClamped(forTextStyle: .headline) }
    class var dynamicTypeBodyClamped: UIFont { preferredFontClamped(forTextStyle: .body) }
    class var dynamicTypeBody2Clamped: UIFont { preferredFontClamped(forTextStyle: .subheadline) }
    class var dynamicTypeCalloutClamped: UIFont { preferredFontClamped(forTextStyle: .callout) }
    class var dynamicTypeSubheadlineClamped: UIFont { preferredFontClamped(forTextStyle: .subheadline) }
    class var dynamicTypeFootnoteClamped: UIFont { preferredFontClamped(forTextStyle: .footnote) }
    class var dynamicTypeCaption1Clamped: UIFont { preferredFontClamped(forTextStyle: .caption1) }
    class var dynamicTypeCaption2Clamped: UIFont { preferredFontClamped(forTextStyle: .caption2) }

    // MARK: -

    func italic() -> UIFont {
        guard let fontDescriptor = fontDescriptor.withSymbolicTraits(.traitItalic) else { return self }
        return UIFont(descriptor: fontDescriptor, size: 0)
    }

    func medium() -> UIFont {
        let fontTraits = [UIFontDescriptor.TraitKey.weight: UIFont.Weight.medium]
        let fontDescriptor = fontDescriptor.addingAttributes([.traits: fontTraits])
        return UIFont(descriptor: fontDescriptor, size: 0)
    }

    func semibold() -> UIFont {
        let fontTraits = [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]
        let fontDescriptor = fontDescriptor.addingAttributes([.traits: fontTraits])
        return UIFont(descriptor: fontDescriptor, size: 0)
    }

    func monospaced() -> UIFont {
        return .monospacedDigitFont(ofSize: pointSize)
    }

}
