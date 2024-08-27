//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Wallpaper {
    public var asColorOrGradientSetting: ColorOrGradientSetting? {
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
            return .themedColor(
                lightThemeColor: OWSColor(
                    red: 0.8862745098039215,
                    green: 0.4117647058823529,
                    blue: 0.5137254901960784
                ),
                darkThemeColor: OWSColor(
                    red: 0.6549019607843137,
                    green: 0.12549019607843137,
                    blue: 0.23921568627450981
                )
            )
        case .copper:
            // Spec name: Copper
            return .themedColor(
                lightThemeColor: OWSColor(
                    red: 0.8745098039215686,
                    green: 0.5686274509803921,
                    blue: 0.44313725490196076
                ),
                darkThemeColor: OWSColor(
                    red: 0.5568627450980392,
                    green: 0.2,
                    blue: 0.06274509803921569
                )
            )
        case .zorba:
            // Spec name: Dust
            return .themedColor(
                lightThemeColor: OWSColor(
                    red: 0.6196078431372549,
                    green: 0.596078431372549,
                    blue: 0.5294117647058824
                ),
                darkThemeColor: OWSColor(
                    red: 0.3254901960784314,
                    green: 0.30980392156862746,
                    blue: 0.2549019607843137
                )
            )
        case .envy:
            // Spec name: Celadon
            return .themedColor(
                lightThemeColor: OWSColor(
                    red: 0.5372549019607843,
                    green: 0.6823529411764706,
                    blue: 0.5607843137254902
                ),
                darkThemeColor: OWSColor(
                    red: 0.21176470588235294,
                    green: 0.32941176470588235,
                    blue: 0.23137254901960785
                )
            )
        case .sky:
            // Spec name: Pacific
            return .themedColor(
                lightThemeColor: OWSColor(
                    red: 0.19607843137254902,
                    green: 0.7803921568627451,
                    blue: 0.8862745098039215
                ),
                darkThemeColor: OWSColor(
                    red: 0.01568627450980392,
                    green: 0.34509803921568627,
                    blue: 0.403921568627451
                )
            )
        case .wildBlueYonder:
            // Spec name: Frost
            return .themedColor(
                lightThemeColor: OWSColor(
                    red: 0.48627450980392156,
                    green: 0.6,
                    blue: 0.7137254901960784
                ),
                darkThemeColor: OWSColor(
                    red: 0.17254901960784313,
                    green: 0.30196078431372547,
                    blue: 0.42745098039215684
                )
            )
        case .lavender:
            // Spec name: Lilac
            return .themedColor(
                lightThemeColor: OWSColor(
                    red: 0.788235294117647,
                    green: 0.5333333333333333,
                    blue: 0.9058823529411765
                ),
                darkThemeColor: OWSColor(
                    red: 0.42745098039215684,
                    green: 0.11372549019607843,
                    blue: 0.5647058823529412
                )
            )
        case .shocking:
            // Spec name: Pink
            return .themedColor(
                lightThemeColor: OWSColor(
                    red: 0.8862745098039215,
                    green: 0.592156862745098,
                    blue: 0.7647058823529411
                ),
                darkThemeColor: OWSColor(
                    red: 0.4666666666666667,
                    green: 0.13333333333333333,
                    blue: 0.32941176470588235
                )
            )
        case .gray:
            // Spec name: Silver
            return .themedColor(
                lightThemeColor: OWSColor(
                    red: 0.6352941176470588,
                    green: 0.6352941176470588,
                    blue: 0.6666666666666666
                ),
                darkThemeColor: OWSColor(
                    red: 0.30980392156862746,
                    green: 0.30980392156862746,
                    blue: 0.34901960784313724
                )
            )
        case .eden:
            // Spec name: Rainforest
            return .themedColor(
                lightThemeColor: OWSColor(
                    red: 0.0784313725490196,
                    green: 0.3803921568627451,
                    blue: 0.2823529411764706
                ),
                darkThemeColor: OWSColor(
                    red: 0.07450980392156863,
                    green: 0.34509803921568627,
                    blue: 0.2549019607843137
                )
            )
        case .violet:
            // Spec name: Navy
            return .themedColor(
                lightThemeColor: OWSColor(
                    red: 0.25098039215686274,
                    green: 0.23137254901960785,
                    blue: 0.5686274509803921
                ),
                darkThemeColor: OWSColor(
                    red: 0.23137254901960785,
                    green: 0.21568627450980393,
                    blue: 0.5254901960784314
                )
            )
        case .eggplant:
            // Spec name: Eggplant
            return .themedColor(
                lightThemeColor: OWSColor(
                    red: 0.3843137254901961,
                    green: 0.25882352941176473,
                    blue: 0.28627450980392155
                ),
                darkThemeColor: OWSColor(
                    red: 0.34509803921568627,
                    green: 0.23529411764705882,
                    blue: 0.2549019607843137
                )
            )

        // Gradient
        case .starshipGradient:
            // Spec name: Sunset
            return .themedGradient(
                lightGradientColor1: OWSColor(
                    red: 0.9529411764705882,
                    green: 0.8627450980392157,
                    blue: 0.2784313725490196
                ),
                lightGradientColor2: OWSColor(
                    red: 0.8941176470588236,
                    green: 0.25098039215686274,
                    blue: 0.25098039215686274
                ),
                darkGradientColor1: OWSColor(
                    red: 0.9019607843137255,
                    green: 0.792156862745098,
                    blue: 0.058823529411764705
                ),
                darkGradientColor2: OWSColor(
                    red: 0.592156862745098,
                    green: 0.06666666666666667,
                    blue: 0.06666666666666667
                ),
                angleRadians: parseAngleDegreesFromSpec(168)
            )
        case .woodsmokeGradient:
            // Spec name: Noir
            return .themedGradient(
                lightGradientColor1: OWSColor(
                    red: 0.2627450980392157,
                    green: 0.2627450980392157,
                    blue: 0.33725490196078434
                ),
                lightGradientColor2: OWSColor(
                    red: 0.6470588235294118,
                    green: 0.6470588235294118,
                    blue: 0.7137254901960784
                ),
                darkGradientColor1: OWSColor(
                    red: 0.07058823529411765,
                    green: 0.07058823529411765,
                    blue: 0.09019607843137255
                ),
                darkGradientColor2: OWSColor(
                    red: 0.3254901960784314,
                    green: 0.3254901960784314,
                    blue: 0.396078431372549
                ),
                angleRadians: parseAngleDegreesFromSpec(180)
            )
        case .coralGradient:
            // Spec name: Heatmap
            return .themedGradient(
                lightGradientColor1: OWSColor(
                    red: 0.9607843137254902,
                    green: 0.2196078431372549,
                    blue: 0.26666666666666666
                ),
                lightGradientColor2: OWSColor(
                    red: 0.25882352941176473,
                    green: 0.21568627450980393,
                    blue: 0.5607843137254902
                ),
                darkGradientColor1: OWSColor(
                    red: 0.7137254901960784,
                    green: 0.12549019607843137,
                    blue: 0.16470588235294117
                ),
                darkGradientColor2: OWSColor(
                    red: 0.21176470588235294,
                    green: 0.17647058823529413,
                    blue: 0.4627450980392157
                ),
                angleRadians: parseAngleDegreesFromSpec(192)
            )
        case .ceruleanGradient:
            // Spec name: Aqua
            return .themedGradient(
                lightGradientColor1: OWSColor(
                    red: 0.0,
                    green: 0.5764705882352941,
                    blue: 0.9137254901960784
                ),
                lightGradientColor2: OWSColor(
                    red: 0.5019607843137255,
                    green: 0.8156862745098039,
                    blue: 0.7803921568627451
                ),
                darkGradientColor1: OWSColor(
                    red: 0.0,
                    green: 0.3803921568627451,
                    blue: 0.6
                ),
                darkGradientColor2: OWSColor(
                    red: 0.24705882352941178,
                    green: 0.6705882352941176,
                    blue: 0.6235294117647059
                ),
                angleRadians: parseAngleDegreesFromSpec(180)
            )
        case .roseGradient:
            // Spec name: Iridescent
            return .themedGradient(
                lightGradientColor1: OWSColor(
                    red: 0.9294117647058824,
                    green: 0.5098039215686274,
                    blue: 0.9019607843137255
                ),
                lightGradientColor2: OWSColor(
                    red: 0.21568627450980393,
                    green: 0.3254901960784314,
                    blue: 0.9019607843137255
                ),
                darkGradientColor1: OWSColor(
                    red: 0.6862745098039216,
                    green: 0.054901960784313725,
                    blue: 0.6431372549019608
                ),
                darkGradientColor2: OWSColor(
                    red: 0.0784313725490196,
                    green: 0.15294117647058825,
                    blue: 0.5647058823529412
                ),
                angleRadians: parseAngleDegreesFromSpec(192)
            )
        case .aquamarineGradient:
            // Spec name: Monstera
            return .themedGradient(
                lightGradientColor1: OWSColor(
                    red: 0.396078431372549,
                    green: 0.803921568627451,
                    blue: 0.6745098039215687
                ),
                lightGradientColor2: OWSColor(
                    red: 0.0392156862745098,
                    green: 0.6,
                    blue: 0.35294117647058826
                ),
                darkGradientColor1: OWSColor(
                    red: 0.13725490196078433,
                    green: 0.4235294117647059,
                    blue: 0.32941176470588235
                ),
                darkGradientColor2: OWSColor(
                    red: 0.023529411764705882,
                    green: 0.33725490196078434,
                    blue: 0.19607843137254902
                ),
                angleRadians: parseAngleDegreesFromSpec(180)
            )
        case .tropicalGradient:
            // Spec name: Bliss
            return .themedGradient(
                lightGradientColor1: OWSColor(
                    red: 0.8470588235294118,
                    green: 0.8823529411764706,
                    blue: 0.9803921568627451

                ),
                lightGradientColor2: OWSColor(
                    red: 0.8392156862745098,
                    green: 0.6431372549019608,
                    blue: 0.7098039215686275
                ),
                darkGradientColor1: OWSColor(
                    red: 0.5411764705882353,
                    green: 0.6313725490196078,
                    blue: 0.8784313725490196
                ),
                darkGradientColor2: OWSColor(
                    red: 0.7137254901960784,
                    green: 0.36470588235294116,
                    blue: 0.4823529411764706
                ),
                angleRadians: parseAngleDegreesFromSpec(180)
            )
        case .blueGradient:
            // Spec name: Sky
            return .themedGradient(
                lightGradientColor1: OWSColor(
                    red: 0.8470588235294118,
                    green: 0.9215686274509803,
                    blue: 0.9921568627450981
                ),
                lightGradientColor2: OWSColor(
                    red: 0.615686274509804,
                    green: 0.8,
                    blue: 0.984313725490196
                ),
                darkGradientColor1: OWSColor(
                    red: 0.6274509803921569,
                    green: 0.7686274509803922,
                    blue: 0.9137254901960784
                ),
                darkGradientColor2: OWSColor(
                    red: 0.2784313725490196,
                    green: 0.5411764705882353,
                    blue: 0.803921568627451
                ),
                angleRadians: parseAngleDegreesFromSpec(180)
            )
        case .bisqueGradient:
            // Spec name: Peach
            return .themedGradient(
                lightGradientColor1: OWSColor(
                    red: 1.0,
                    green: 0.8980392156862745,
                    blue: 0.7607843137254902
                ),
                lightGradientColor2: OWSColor(
                    red: 0.9882352941176471,
                    green: 0.6745098039215687,
                    blue: 0.5725490196078431
                ),
                darkGradientColor1: OWSColor(
                    red: 0.9176470588235294,
                    green: 0.7607843137254902,
                    blue: 0.5411764705882353
                ),
                darkGradientColor2: OWSColor(
                    red: 0.7333333333333333,
                    green: 0.3803921568627451,
                    blue: 0.26666666666666666
                ),
                angleRadians: parseAngleDegreesFromSpec(192)
            )
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
