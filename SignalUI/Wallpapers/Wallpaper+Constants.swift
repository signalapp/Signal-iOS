//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Wallpaper {
    var asColorOrGradientSetting: ColorOrGradientSetting? {
        func parseAngleDegreesFromSpec(_ angleDegreesFromSpec: CGFloat) -> CGFloat {
            // In our models:
            // If angleRadians = 0, gradientColor1 is N.
            // If angleRadians = PI / 2, gradientColor1 is E.
            // etc.
            //
            // In the spec:
            // If angleDegrees = 180, gradientColor1 is N.
            // If angleDegrees = 270, gradientColor1 is E.
            // etc.
            return ((angleDegreesFromSpec - 180) / 180) * CGFloat.pi
        }

        switch self {
        case .photo:
            return nil

        // Solid
        case .blush:
            // Spec name: Blush
            return .themedColor(lightThemeColor: UIColor(rgbHex: 0xE26983).asOWSColor,
                                darkThemeColor: UIColor(rgbHex: 0xA7203D).asOWSColor)
        case .copper:
            // Spec name: Copper
            return .themedColor(lightThemeColor: UIColor(rgbHex: 0xDF9171).asOWSColor,
                                darkThemeColor: UIColor(rgbHex: 0x8E3310).asOWSColor)
        case .zorba:
            // Spec name: Dust
            return .themedColor(lightThemeColor: UIColor(rgbHex: 0x9E9887).asOWSColor,
                                darkThemeColor: UIColor(rgbHex: 0x534F41).asOWSColor)
        case .envy:
            // Spec name: Celadon
            return .themedColor(lightThemeColor: UIColor(rgbHex: 0x89AE8F).asOWSColor,
                                darkThemeColor: UIColor(rgbHex: 0x36543B).asOWSColor)
        case .sky:
            // Spec name: Pacific
            return .themedColor(lightThemeColor: UIColor(rgbHex: 0x32C7E2).asOWSColor,
                                darkThemeColor: UIColor(rgbHex: 0x045867).asOWSColor)
        case .wildBlueYonder:
            // Spec name: Frost
            return .themedColor(lightThemeColor: UIColor(rgbHex: 0x7C99B6).asOWSColor,
                                darkThemeColor: UIColor(rgbHex: 0x2C4D6D).asOWSColor)
        case .lavender:
            // Spec name: Lilac
            return .themedColor(lightThemeColor: UIColor(rgbHex: 0xC988E7).asOWSColor,
                                darkThemeColor: UIColor(rgbHex: 0x6D1D90).asOWSColor)
        case .shocking:
            // Spec name: Pink
            return .themedColor(lightThemeColor: UIColor(rgbHex: 0xE297C3).asOWSColor,
                                darkThemeColor: UIColor(rgbHex: 0x772254).asOWSColor)
        case .gray:
            // Spec name: Silver
            return .themedColor(lightThemeColor: UIColor(rgbHex: 0xA2A2AA).asOWSColor,
                                darkThemeColor: UIColor(rgbHex: 0x4F4F59).asOWSColor)
        case .eden:
            // Spec name: Rainforest
            return .themedColor(lightThemeColor: UIColor(rgbHex: 0x146148).asOWSColor,
                                darkThemeColor: UIColor(rgbHex: 0x135841).asOWSColor)
        case .violet:
            // Spec name: Navy
            return .themedColor(lightThemeColor: UIColor(rgbHex: 0x403B91).asOWSColor,
                                darkThemeColor: UIColor(rgbHex: 0x3B3786).asOWSColor)
        case .eggplant:
            // Spec name: Eggplant
            return .themedColor(lightThemeColor: UIColor(rgbHex: 0x624249).asOWSColor,
                                darkThemeColor: UIColor(rgbHex: 0x583C41).asOWSColor)

        // Gradient
        case .starshipGradient:
            // Spec name: Sunset
            return .themedGradient(lightGradientColor1: UIColor(rgbHex: 0xF3DC47).asOWSColor,
                                   lightGradientColor2: UIColor(rgbHex: 0xE44040).asOWSColor,
                                   darkGradientColor1: UIColor(rgbHex: 0xE6CA0F).asOWSColor,
                                   darkGradientColor2: UIColor(rgbHex: 0x971111).asOWSColor,
                                   angleRadians: parseAngleDegreesFromSpec(168))
        case .woodsmokeGradient:
            // Spec name: Noir
            return .themedGradient(lightGradientColor1: UIColor(rgbHex: 0x434356).asOWSColor,
                                   lightGradientColor2: UIColor(rgbHex: 0xA5A5B6).asOWSColor,
                                   darkGradientColor1: UIColor(rgbHex: 0x121217).asOWSColor,
                                   darkGradientColor2: UIColor(rgbHex: 0x535365).asOWSColor,
                                   angleRadians: parseAngleDegreesFromSpec(180))
        case .coralGradient:
            // Spec name: Heatmap
            return .themedGradient(lightGradientColor1: UIColor(rgbHex: 0xF53844).asOWSColor,
                                   lightGradientColor2: UIColor(rgbHex: 0x42378F).asOWSColor,
                                   darkGradientColor1: UIColor(rgbHex: 0xB6202A).asOWSColor,
                                   darkGradientColor2: UIColor(rgbHex: 0x362D76).asOWSColor,
                                   angleRadians: parseAngleDegreesFromSpec(192))
        case .ceruleanGradient:
            // Spec name: Aqua
            return .themedGradient(lightGradientColor1: UIColor(rgbHex: 0x0093E9).asOWSColor,
                                   lightGradientColor2: UIColor(rgbHex: 0x80D0C7).asOWSColor,
                                   darkGradientColor1: UIColor(rgbHex: 0x006199).asOWSColor,
                                   darkGradientColor2: UIColor(rgbHex: 0x3FAB9F).asOWSColor,
                                   angleRadians: parseAngleDegreesFromSpec(180))
        case .roseGradient:
            // Spec name: Iridescent
            return .themedGradient(lightGradientColor1: UIColor(rgbHex: 0xED82E6).asOWSColor,
                                   lightGradientColor2: UIColor(rgbHex: 0x3753E6).asOWSColor,
                                   darkGradientColor1: UIColor(rgbHex: 0xAF0EA4).asOWSColor,
                                   darkGradientColor2: UIColor(rgbHex: 0x142790).asOWSColor,
                                   angleRadians: parseAngleDegreesFromSpec(192))
        case .aquamarineGradient:
            // Spec name: Monstera
            return .themedGradient(lightGradientColor1: UIColor(rgbHex: 0x65CDAC).asOWSColor,
                                   lightGradientColor2: UIColor(rgbHex: 0x0A995A).asOWSColor,
                                   darkGradientColor1: UIColor(rgbHex: 0x236C54).asOWSColor,
                                   darkGradientColor2: UIColor(rgbHex: 0x065632).asOWSColor,
                                   angleRadians: parseAngleDegreesFromSpec(180))
        case .tropicalGradient:
            // Spec name: Bliss
            return .themedGradient(lightGradientColor1: UIColor(rgbHex: 0xD8E1FA).asOWSColor,
                                   lightGradientColor2: UIColor(rgbHex: 0xD6A4B5).asOWSColor,
                                   darkGradientColor1: UIColor(rgbHex: 0x8AA1E0).asOWSColor,
                                   darkGradientColor2: UIColor(rgbHex: 0xB65D7B).asOWSColor,
                                   angleRadians: parseAngleDegreesFromSpec(180))
        case .blueGradient:
            // Spec name: Sky
            return .themedGradient(lightGradientColor1: UIColor(rgbHex: 0xD8EBFD).asOWSColor,
                                   lightGradientColor2: UIColor(rgbHex: 0x9DCCFB).asOWSColor,
                                   darkGradientColor1: UIColor(rgbHex: 0xA0C4E9).asOWSColor,
                                   darkGradientColor2: UIColor(rgbHex: 0x478ACD).asOWSColor,
                                   angleRadians: parseAngleDegreesFromSpec(180))
        case .bisqueGradient:
            // Spec name: Peach
            return .themedGradient(lightGradientColor1: UIColor(rgbHex: 0xFFE5C2).asOWSColor,
                                   lightGradientColor2: UIColor(rgbHex: 0xFCAC92).asOWSColor,
                                   darkGradientColor1: UIColor(rgbHex: 0xEAC28A).asOWSColor,
                                   darkGradientColor2: UIColor(rgbHex: 0xBB6144).asOWSColor,
                                   angleRadians: parseAngleDegreesFromSpec(192))

        }
    }

    public var defaultChatColor: PaletteChatColor? {
        switch self {
        // Solid
        case .blush: return .crimson
        case .copper: return .vermilion
        case .zorba: return .burlap
        case .envy: return .forest
        case .sky: return .teal
        case .wildBlueYonder: return .blue
        case .lavender: return .violet
        case .shocking: return .plum
        case .gray: return .steel
        case .eden: return .wintergreen
        case .violet: return .indigo
        case .eggplant: return .taupe

        // Gradient
        case .starshipGradient: return .ember
        case .woodsmokeGradient: return .midnight
        case .coralGradient: return .infrared
        case .ceruleanGradient: return .lagoon
        case .roseGradient: return .fluorescent
        case .aquamarineGradient: return .basil
        case .tropicalGradient: return .sublime
        case .blueGradient: return .sea
        case .bisqueGradient: return .tangerine

        // Custom
        case .photo: return nil
        }
    }
}
