//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import NaturalLanguage
import SignalServiceKit
public import SwiftUI

public enum SignalSymbol: Character {

    // MARK: - Symbols

    case album = "\u{E001}"
    case arrowDown = "\u{E16C}"
    case arrowDownLeft = "\u{E16F}"
    case arrowDownRight = "\u{E170}"
    case arrowLeft = "\u{E169}"
    case arrowRight = "\u{E16A}"
    case arrowUp = "\u{E16B}"
    case arrowUpLeft = "\u{E16D}"
    case arrowUpRight = "\u{E16E}"
    case at = "\u{E01B}"
    case audio = "\u{E01C}"
    case audioSquare = "\u{E01D}"
    case bell = "\u{E01E}"
    case bellRing = "\u{E020}"
    case bellSlash = "\u{E01F}"
    case block = "\u{E002}"
    case checkCircle = "\u{E022}"
    case checkmark = "\u{E180}"
    case checkSquare = "\u{E023}"
    case chevronDown = "\u{E027}"
    case chevronLeft = "\u{E024}"
    case chevronRight = "\u{E025}"
    case chevronUp = "\u{E026}"
    case clear = "\u{2327}"
    case creditcard = "\u{E127}"
    case edit = "\u{E030}"
    case error = "\u{E032}"
    case file = "\u{E034}"
    case forward = "\u{E035}"
    case gif = "\u{E037}"
    case gifRectangle = "\u{E195}"
    case group = "\u{E038}"
    case heart = "\u{E039}"
    case incoming = "\u{E03A}"
    case info = "\u{E03B}"
    case leaveLTR = "\u{E03C}"
    case leaveRTL = "\u{E03D}"
    case link = "\u{E03E}"
    case location = "\u{E0BC}"
    case lock = "\u{E041}"
    case megaphone = "\u{E042}"
    case merge = "\u{E043}"
    case messageStatusDelivered = "\u{E046}"
    case messageStatusRead = "\u{E047}"
    case messageStatusSending = "\u{E044}"
    case messageStatusSent = "\u{E045}"
    case messageTimer00 = "\u{E048}"
    case messageTimer05 = "\u{E049}"
    case messageTimer10 = "\u{E04A}"
    case messageTimer15 = "\u{E04B}"
    case messageTimer20 = "\u{E04C}"
    case messageTimer25 = "\u{E04D}"
    case messageTimer30 = "\u{E04E}"
    case messageTimer35 = "\u{E04F}"
    case messageTimer40 = "\u{E050}"
    case messageTimer45 = "\u{E051}"
    case messageTimer50 = "\u{E052}"
    case messageTimer55 = "\u{E053}"
    case messageTimer60 = "\u{E054}"
    case mic = "\u{E055}"
    case micClash = "\u{E056}"
    case minus = "\u{E1B7}"
    case minusCircle = "\u{E1B8}"
    case missedIncoming = "\u{E05A}"
    case missedOutgoing = "\u{E05B}"
    case multiply = "\u{00D7}"
    case outgoing = "\u{E05C}"
    case person = "\u{E05D}"
    case personCheck = "\u{E05F}"
    case personCircle = "\u{E05E}"
    case personMinus = "\u{E062}"
    case personPlus = "\u{E061}"
    case personX = "\u{E060}"
    case phone = "\u{E063}"
    case phoneFill = "\u{E064}"
    case photo = "\u{E065}"
    case photoRectangle = "\u{E066}"
    case pin = "\u{E12E}"
    case play = "\u{E067}"
    case playRectangle = "\u{E069}"
    case playSquare = "\u{E068}"
    case plus = "\u{E1D1}"
    case plusCircle = "\u{E1D2}"
    case poll = "\u{E082}"
    case refresh = "\u{E0C4}"
    case reply = "\u{E06D}"
    case safetyNumber = "\u{E06F}"
    case shareScreen = "\u{E171}"
    case shareScreenFill = "\u{E174}"
    case signal = "\u{E000}"
    case spam = "\u{E033}"
    case sticker = "\u{E070}"
    case thread = "\u{E071}"
    case threadFill = "\u{E072}"
    case timer = "\u{E073}"
    case timerSlash = "\u{E074}"
    case timesCircle = "\u{2297}"
    case video = "\u{E075}"
    case videoFill = "\u{E077}"
    case viewOnce = "\u{E078}"
    case viewOnceSlash = "\u{E079}"
    case xCircle = "\u{E1EE}"
    case groupXInline = "\u{E0AE}"

    // MARK: Localized symbols

    public static var leave: SignalSymbol {
        localizedSymbol(ltr: .leaveLTR, rtl: .leaveRTL)
    }

    /// Use this when adding a trailing chevron to the end of strings we are
    /// localizing ourselves. For names or other user-input text, you might want
    /// to try ``chevronTrailing(for:)`` instead.
    public static var chevronTrailing: SignalSymbol {
        localizedSymbol(ltr: .chevronRight, rtl: .chevronLeft)
    }

    private static func localizedSymbol(ltr: SignalSymbol, rtl: SignalSymbol) -> SignalSymbol {
        CurrentAppContext().isRTL ? rtl : ltr
    }

    private static var stringIsRTLCache: [String: Bool] = [:]
    private static func isRTL(string: String) -> Bool {
        if let isRTL = stringIsRTLCache[string] {
            return isRTL
        }

        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(string)
        let dominantLanguage = languageRecognizer.dominantLanguage

        let isRTL = if let dominantLanguage {
            Locale.characterDirection(forLanguage: dominantLanguage.rawValue) == .rightToLeft
        } else {
            CurrentAppContext().isRTL
        }

        stringIsRTLCache[string] = isRTL
        return isRTL
    }

    /// Use this when adding a chevron to the end of user-input strings like
    /// names. For strings we are localizing ourselves, use ``chevronTrailing``.
    public static func chevronTrailing(for string: String) -> SignalSymbol {
        isRTL(string: string) ? .chevronLeft : .chevronRight
    }

    // MARK: - Font

    public enum Weight {
        case light
        case regular
        case bold
        case medium
        case thin

        fileprivate var fontName: String {
            switch self {
            case .light:
                return "SignalSymbols-Light"
            case .regular:
                return "SignalSymbols-Regular"
            case .bold:
                return "SignalSymbols-Bold"
            case .medium:
                return "SignalSymbols-Medium"
            case .thin:
                return "SignalSymbols-Thin"
            }
        }

        fileprivate func staticFont(ofSize size: CGFloat) -> UIFont {
            UIFont(
                descriptor: UIFontDescriptor(fontAttributes: [
                    .name: self.fontName,
                ]),
                size: size,
            )
        }

        fileprivate func dynamicTypeFont(
            for textStyle: UIFont.TextStyle,
            clamped: Bool,
        ) -> UIFont {
            self.dynamicTypeFont(
                ofStandardSize: UIFont.preferredFont(
                    forTextStyle: textStyle,
                    compatibleWith: UITraitCollection(
                        preferredContentSizeCategory: .large,
                    ),
                ).pointSize,
                clamped: clamped,
            )
        }

        fileprivate func dynamicTypeFont(
            ofStandardSize standardSize: CGFloat,
            clamped: Bool,
        ) -> UIFont {
            let unscaledFont = UIFont(
                descriptor: UIFontDescriptor(fontAttributes: [
                    .name: self.fontName,
                ]),
                size: standardSize,
            )

            if clamped {
                let xxxl = UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge)
                let maxSize = UIFontMetrics.default.scaledValue(for: standardSize, compatibleWith: xxxl)
                return UIFontMetrics.default.scaledFont(for: unscaledFont, maximumPointSize: maxSize)
            }

            return UIFontMetrics.default.scaledFont(
                for: unscaledFont,
            )
        }
    }

    // MARK: - Attributed string

    public enum LeadingCharacter: String {
        case space = " "
        case nonBreakingSpace = "\u{00A0}"
    }

    public func attributedString(
        for textStyle: UIFont.TextStyle,
        clamped: Bool = false,
        weight: Weight = .regular,
        leadingCharacter: LeadingCharacter? = nil,
        attributes: [NSAttributedString.Key: Any] = [:],
    ) -> NSAttributedString {
        self.attributedString(
            font: weight.dynamicTypeFont(
                for: textStyle,
                clamped: clamped,
            ),
            leadingCharacter: leadingCharacter,
            attributes: attributes,
        )
    }

    public func attributedString(
        dynamicTypeBaseSize: CGFloat,
        clamped: Bool = false,
        weight: Weight = .regular,
        leadingCharacter: LeadingCharacter? = nil,
        attributes: [NSAttributedString.Key: Any] = [:],
    ) -> NSAttributedString {
        self.attributedString(
            font: weight.dynamicTypeFont(
                ofStandardSize: dynamicTypeBaseSize,
                clamped: clamped,
            ),
            leadingCharacter: leadingCharacter,
            attributes: attributes,
        )
    }

    public func attributedString(
        staticFontSize: CGFloat,
        weight: Weight = .regular,
        leadingCharacter: LeadingCharacter? = nil,
        attributes: [NSAttributedString.Key: Any] = [:],
    ) -> NSAttributedString {
        self.attributedString(
            font: weight.staticFont(ofSize: staticFontSize),
            leadingCharacter: leadingCharacter,
            attributes: attributes,
        )
    }

    private func attributedString(
        font: UIFont,
        leadingCharacter: LeadingCharacter?,
        attributes: [NSAttributedString.Key: Any],
    ) -> NSAttributedString {
        var attributes = attributes
        attributes[.font] = font

        return NSAttributedString(
            string: "\(leadingCharacter?.rawValue ?? "")\(self.rawValue)",
            attributes: attributes,
        )
    }

    // MARK: - SwiftUI

    /// Creates a SwiftUI `Text` view with the specified dynamic type size and weight.
    ///
    /// Can be combined with other `Text` views with the `+` operator.
    /// For example:
    ///
    /// ```swift
    /// SignalSymbol.arrowUp.text(dynamicTypeBaseSize: 16) +
    /// Text(" Share")
    /// ```
    /// - Parameters:
    ///   - dynamicTypeBaseSize: The base size of the font at 100% Dynamic Type
    ///   scale which will then be scaled based on the current device scale.
    ///   - weight: The font weight.
    /// - Returns: A SwiftUI `Text` view with this symbol and the given font.
    public func text(
        dynamicTypeBaseSize: CGFloat,
        weight: Weight = .regular,
    ) -> Text {
        Text(verbatim: "\(self.rawValue)")
            .font(Font.custom(weight.fontName, size: dynamicTypeBaseSize))
    }
}
