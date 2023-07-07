//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Preset color options for the username link QR code.
///
/// Exposes a set of colors to use for various parts of the QR code rendering.
enum UsernameLinkQRCodeColor: String, UnknownEnumCodable, CaseIterable {
    case blue
    case white
    case grey
    case olive
    case green
    case orange
    case pink
    case purple

    static var unknown: UsernameLinkQRCodeColor { .blue }

    /// Background color for the QR code.
    var background: UIColor {
        switch self {
        case .blue:
            return UIColor(rgbHex: 0x506ECD)
        case .white:
            return .ows_white
        case .grey:
            return UIColor(rgbHex: 0x6A6C74)
        case .olive:
            return UIColor(rgbHex: 0xA89D7F)
        case .green:
            return UIColor(rgbHex: 0x829A6E)
        case .orange:
            return UIColor(rgbHex: 0xDE7134)
        case .pink:
            return UIColor(rgbHex: 0xE67899)
        case .purple:
            return UIColor(rgbHex: 0x9C84CF)
        }
    }

    /// Foreground color for the QR code.
    var foreground: UIColor {
        switch self {
        case .blue:
            return UIColor(rgbHex: 0x2449C0)
        case .white:
            return .ows_black
        case .grey:
            return UIColor(rgbHex: 0x464852)
        case .olive:
            return UIColor(rgbHex: 0x73694F)
        case .green:
            return UIColor(rgbHex: 0x55733F)
        case .orange:
            return UIColor(rgbHex: 0xD96B2D)
        case .pink:
            return UIColor(rgbHex: 0xBB617B)
        case .purple:
            return UIColor(rgbHex: 0x7651C5)
        }
    }

    /// Border color for the padding around the QR code.
    var paddingBorder: UIColor {
        switch self {
        case .white:
            return .ows_gray05
        default:
            return .clear
        }
    }

    /// Color for the username displayed alongside the QR code.
    var username: UIColor {
        switch self {
        case .white:
            return .ows_black
        default:
            return .ows_white
        }
    }
}
