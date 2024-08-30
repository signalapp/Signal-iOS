//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

internal class MessageBackupChatStyleArchiver: MessageBackupProtoArchiver {

    private let chatColorSettingStore: ChatColorSettingStore
    private let dateProvider: DateProvider
    private let wallpaperStore: WallpaperStore

    init(
        chatColorSettingStore: ChatColorSettingStore,
        dateProvider: @escaping DateProvider,
        wallpaperStore: WallpaperStore
    ) {
        self.chatColorSettingStore = chatColorSettingStore
        self.dateProvider = dateProvider
        self.wallpaperStore = wallpaperStore
    }
}

// MARK: - Converters

// MARK: Wallpaper presets

fileprivate extension Wallpaper {

    func asBackupProto() -> BackupProto_ChatStyle.WallpaperPreset? {
        // These don't match names exactly because...well nobody knows why
        // the iOS enum names were defined this way. They're persisted to the
        // db now, so we just gotta keep the mapping.
        return switch self {
        case .blush: .solidBlush
        case .copper: .solidCopper
        case .zorba: .solidDust
        case .envy: .solidCeladon
        case .sky: .solidPacific
        case .wildBlueYonder: .solidFrost
        case .lavender: .solidLilac
        case .shocking: .solidPink
        case .gray: .solidSilver
        case .eden: .solidRainforest
        case .violet: .solidNavy
        case .eggplant: .solidEggplant
        case .starshipGradient: .gradientSunset
        case .woodsmokeGradient: .gradientNoir
        case .coralGradient: .gradientHeatmap
        case .ceruleanGradient: .gradientAqua
        case .roseGradient: .gradientIridescent
        case .aquamarineGradient: .gradientMonstera
        case .tropicalGradient: .gradientBliss
        case .blueGradient: .gradientSky
        case .bisqueGradient: .gradientPeach
        case .photo: nil
        }
    }
}

fileprivate extension BackupProto_ChatStyle.WallpaperPreset {

    func asWallpaper() -> Wallpaper? {
        // These don't match names exactly because...well nobody knows why
        // the iOS enum names were defined this way. They're persisted to the
        // db now, so we just gotta keep the mapping.
        return switch self {
        case .unknownWallpaperPreset: nil
        case .UNRECOGNIZED: nil
        case .solidBlush: .blush
        case .solidCopper: .copper
        case .solidDust: .zorba
        case .solidCeladon: .envy
        case .solidRainforest: .eden
        case .solidPacific: .sky
        case .solidFrost: .wildBlueYonder
        case .solidNavy: .violet
        case .solidLilac: .lavender
        case .solidPink: .shocking
        case .solidEggplant: .eggplant
        case .solidSilver: .gray
        case .gradientSunset: .starshipGradient
        case .gradientNoir: .woodsmokeGradient
        case .gradientHeatmap: .coralGradient
        case .gradientAqua: .ceruleanGradient
        case .gradientIridescent: .roseGradient
        case .gradientMonstera: .aquamarineGradient
        case .gradientBliss: .tropicalGradient
        case .gradientSky: .blueGradient
        case .gradientPeach: .bisqueGradient
        }
    }
}

// MARK: Bubble Color Presets

fileprivate extension PaletteChatColor {

    func asBackupProto() -> BackupProto_ChatStyle.BubbleColorPreset {
        return switch self {
        case .ultramarine: .solidUltramarine
        case .crimson: .solidCrimson
        case .vermilion: .solidVermilion
        case .burlap: .solidBurlap
        case .forest: .solidForest
        case .wintergreen: .solidWintergreen
        case .teal: .solidTeal
        case .blue: .solidBlue
        case .indigo: .solidIndigo
        case .violet: .solidViolet
        case .plum: .solidPlum
        case .taupe: .solidTaupe
        case .steel: .solidSteel
        case .ember: .gradientEmber
        case .midnight: .gradientMidnight
        case .infrared: .gradientInfrared
        case .lagoon: .gradientLagoon
        case .fluorescent: .gradientFluorescent
        case .basil: .gradientBasil
        case .sublime: .gradientSublime
        case .sea: .gradientSea
        case .tangerine: .gradientTangerine
        }
    }
}

fileprivate extension BackupProto_ChatStyle.BubbleColorPreset {

    func asPaletteChatColor() -> PaletteChatColor? {
        return switch self {
        case .unknownBubbleColorPreset: nil
        case .UNRECOGNIZED: nil
        case .solidUltramarine: .ultramarine
        case .solidCrimson: .crimson
        case .solidVermilion: .vermilion
        case .solidBurlap: .burlap
        case .solidForest: .forest
        case .solidWintergreen: .wintergreen
        case .solidTeal: .teal
        case .solidBlue: .blue
        case .solidIndigo: .indigo
        case .solidViolet: .violet
        case .solidPlum: .plum
        case .solidTaupe: .taupe
        case .solidSteel: .steel
        case .gradientEmber: .ember
        case .gradientMidnight: .midnight
        case .gradientInfrared: .infrared
        case .gradientLagoon: .lagoon
        case .gradientFluorescent: .fluorescent
        case .gradientBasil: .basil
        case .gradientSublime: .sublime
        case .gradientSea: .sea
        case .gradientTangerine: .tangerine
        }
    }
}

// MARK: OWSColor

extension OWSColor {

    func asRGBHex() -> UInt32 {
        return UInt32(red * 255) << 16 | UInt32(green * 255) << 8 | UInt32(blue * 255) << 0
    }

    static func fromRGBHex(_ value: UInt32) -> OWSColor {
        let red = CGFloat(((value >> 16) & 0xff)) / 255.0
        let green = CGFloat(((value >> 8) & 0xff)) / 255.0
        let blue = CGFloat(((value >> 0) & 0xff)) / 255.0
        return OWSColor(red: red, green: green, blue: blue)
    }
}
