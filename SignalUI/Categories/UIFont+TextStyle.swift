//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

extension UIFont {

    public class func font(for textStyle: TextAttachment.TextStyle, withPointSize pointSize: CGFloat) -> UIFont {
        let primaryFontName: String
        var fontNamesOrDescriptors: [Any]

        switch textStyle {
        case .regular:
            primaryFontName = "Inter-Regular_Medium"
            fontNamesOrDescriptors = [
                "KohinoorDevanagari-Regular",
                "PingFangHK-Regular",
                "PingFangTC-Regular",
                "PingFangSC-Regular",
                "HiraginoSans-W3",
                UIFont.systemFont(ofSize: 10, weight: .regular).fontDescriptor    // Sans Serif Regular
            ]

        case .bold:
            primaryFontName = "Inter-Regular_Black"
            fontNamesOrDescriptors = [
                "KohinoorDevanagari-Semibold",
                "PingFangHK-Semibold",
                "PingFangTC-Semibold",
                "PingFangSC-Semibold",
                "HiraginoSans-W7",
                UIFont.systemFont(ofSize: 10, weight: .bold).fontDescriptor // Sans Serif Bold

            ]

        case .serif:
            primaryFontName = "EBGaramond-Regular"
            fontNamesOrDescriptors = [
                "DevanagariSangamMN",
                "PingFangHK-Ultralight",
                "PingFangTC-Ultralight",
                "PingFangSC-Ultralight",
                "GeezaPro",
                "HiraMinProN-W3"
            ]
            // Serif Regular
            if let fontDescriptor = UIFontDescriptor
                .preferredFontDescriptor(withTextStyle: .body)
                .withSymbolicTraits(.classModernSerifs) {
                fontNamesOrDescriptors.append(fontDescriptor)
            }

        case .script:
            primaryFontName = "Parisienne-Regular"
            fontNamesOrDescriptors = [
                "AmericanTypewriter-Semibold",
                "DevanagariSangamMN-Bold",
                "PingFangHK-Thin",
                "PingFangTC-Thin",
                "PingFangSC-Thin",
                "GeezaPro-Bold",
                "HiraMinProN-W6"
            ]
            // Serif Bold
            if let fontDescriptor = UIFontDescriptor
                .preferredFontDescriptor(withTextStyle: .body)
                .withSymbolicTraits(.classModernSerifs)?
                .withSymbolicTraits(.traitBold) {
                fontNamesOrDescriptors.append(fontDescriptor)
            }

        case .condensed:
            primaryFontName = "BarlowCondensed-Medium"
            fontNamesOrDescriptors = [
                "KohinoorDevanagari-Light",
                "PingFangHK-Light",
                "PingFangTC-Light",
                "PingFangSC-Light",
                "HiraMaruProN-W4",
                UIFont.systemFont(ofSize: 10, weight: .black).fontDescriptor // Sans Serif Black
            ]
        }

        let cascadeList: [UIFontDescriptor] = fontNamesOrDescriptors.compactMap { fontNameOrDescriptor in
            if let fontDescriptor = fontNameOrDescriptor as? UIFontDescriptor {
                return fontDescriptor
            }
            if let fontName = fontNameOrDescriptor as? String {
                return UIFontDescriptor(fontAttributes: [ .name: fontName ])
            }
            owsFailDebug("Not a String or UIFontDescriptor.")
            return nil
        }

        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: primaryFontName,
            .cascadeList: cascadeList
        ])

        return UIFont(descriptor: descriptor, size: pointSize)
    }

    /// Creates a 7-segment display font used for displaying numbers in the style of a digital clock.
    ///
    /// Only supports numbers, `.`, and `:`. Does not support letters.
    /// - Parameter pointSize: The size (in points) to which the font is scaled. This value must be greater than 0.0.
    /// - Returns: A digital clock font object of the specified size.
    class func digitalClockFont(withPointSize pointSize: CGFloat) -> UIFont {
        let fontDescriptor = UIFontDescriptor(fontAttributes: [.name: "Hatsuishi-UPM800"])
        return UIFont(descriptor: fontDescriptor, size: pointSize)
    }
}
