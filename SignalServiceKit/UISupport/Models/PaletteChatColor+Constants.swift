//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension PaletteChatColor {

    private static func parseAngleDegreesFromSpec(_ angleDegreesFromSpec: CGFloat) -> CGFloat {
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

    public var colorSetting: ColorOrGradientSetting {
        switch self {
        case .ultramarine:
            return .gradient(
                gradientColor1: OWSColor(red: 0.0196078431372549, green: 0.3215686274509804, blue: 0.9411764705882353),
                gradientColor2: OWSColor(red: 0.17254901960784313, green: 0.4196078431372549, blue: 0.9294117647058824),
                angleRadians: CGFloat.pi * 0
            )
        case .crimson:
            return .solidColor(color: OWSColor(red: 0.8117647058823529, green: 0.08627450980392157, blue: 0.24313725490196078))
        case .vermilion:
            return .solidColor(color: OWSColor(red: 0.7803921568627451, green: 0.24705882352941178, blue: 0.0392156862745098))
        case .burlap:
            return .solidColor(color: OWSColor(red: 0.43529411764705883, green: 0.41568627450980394, blue: 0.34509803921568627))
        case .forest:
            return .solidColor(color: OWSColor(red: 0.23137254901960785, green: 0.47058823529411764, blue: 0.27058823529411763))
        case .wintergreen:
            return .solidColor(color: OWSColor(red: 0.11372549019607843, green: 0.5254901960784314, blue: 0.38823529411764707))
        case .teal:
            return .solidColor(color: OWSColor(red: 0.027450980392156862, green: 0.49019607843137253, blue: 0.5725490196078431))
        case .blue:
            return .solidColor(color: OWSColor(red: 0.2, green: 0.4196078431372549, blue: 0.6392156862745098))
        case .indigo:
            return .solidColor(color: OWSColor(red: 0.3764705882352941, green: 0.34509803921568627, blue: 0.792156862745098))
        case .violet:
            return .solidColor(color: OWSColor(red: 0.6, green: 0.19607843137254902, blue: 0.7843137254901961))
        case .plum:
            return .solidColor(color: OWSColor(red: 0.6666666666666666, green: 0.21568627450980393, blue: 0.47843137254901963))
        case .taupe:
            return .solidColor(color: OWSColor(red: 0.5607843137254902, green: 0.3803921568627451, blue: 0.41568627450980394))
        case .steel:
            return .solidColor(color: OWSColor(red: 0.44313725490196076, green: 0.44313725490196076, blue: 0.4980392156862745))
        case .ember:
            return .gradient(
                gradientColor1: OWSColor(red: 0.8980392156862745, green: 0.48627450980392156, blue: 0.0),
                gradientColor2: OWSColor(red: 0.3686274509803922, green: 0.0, blue: 0.0),
                angleRadians: Self.parseAngleDegreesFromSpec(168)
            )
        case .midnight:
            return .gradient(
                gradientColor1: OWSColor(red: 0.17254901960784313, green: 0.17254901960784313, blue: 0.22745098039215686),
                gradientColor2: OWSColor(red: 0.47058823529411764, green: 0.47058823529411764, blue: 0.5686274509803921),
                angleRadians: Self.parseAngleDegreesFromSpec(180)
            )
        case .infrared:
            return .gradient(
                gradientColor1: OWSColor(red: 0.9647058823529412, green: 0.3333333333333333, blue: 0.3764705882352941),
                gradientColor2: OWSColor(red: 0.26666666666666666, green: 0.17254901960784313, blue: 0.9294117647058824),
                angleRadians: Self.parseAngleDegreesFromSpec(192)
            )
        case .lagoon:
            return .gradient(
                gradientColor1: OWSColor(red: 0.0, green: 0.25098039215686274, blue: 0.4),
                gradientColor2: OWSColor(red: 0.19607843137254902, green: 0.5254901960784314, blue: 0.49019607843137253),
                angleRadians: Self.parseAngleDegreesFromSpec(180)
            )
        case .fluorescent:
            return .gradient(
                gradientColor1: OWSColor(red: 0.9254901960784314, green: 0.07450980392156863, blue: 0.8666666666666667),
                gradientColor2: OWSColor(red: 0.10588235294117647, green: 0.21176470588235294, blue: 0.7764705882352941),
                angleRadians: Self.parseAngleDegreesFromSpec(192)
            )
        case .basil:
            return .gradient(
                gradientColor1: OWSColor(red: 0.1843137254901961, green: 0.5764705882352941, blue: 0.45098039215686275),
                gradientColor2: OWSColor(red: 0.027450980392156862, green: 0.45098039215686275, blue: 0.2627450980392157),
                angleRadians: Self.parseAngleDegreesFromSpec(180)
            )
        case .sublime:
            return .gradient(
                gradientColor1: OWSColor(red: 0.3843137254901961, green: 0.5058823529411764, blue: 0.8352941176470589),
                gradientColor2: OWSColor(red: 0.592156862745098, green: 0.26666666666666666, blue: 0.3764705882352941),
                angleRadians: Self.parseAngleDegreesFromSpec(180)
            )
        case .sea:
            return .gradient(
                gradientColor1: OWSColor(red: 0.28627450980392155, green: 0.5607843137254902, blue: 0.8313725490196079),
                gradientColor2: OWSColor(red: 0.17254901960784313, green: 0.4, blue: 0.6274509803921569),
                angleRadians: Self.parseAngleDegreesFromSpec(180)
            )
        case .tangerine:
            return .gradient(
                gradientColor1: OWSColor(red: 0.8588235294117647, green: 0.44313725490196076, blue: 0.2),
                gradientColor2: OWSColor(red: 0.5686274509803921, green: 0.07058823529411765, blue: 0.19215686274509805),
                angleRadians: Self.parseAngleDegreesFromSpec(192)
            )
        }
    }
}
