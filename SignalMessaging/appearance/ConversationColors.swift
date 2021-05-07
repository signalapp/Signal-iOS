//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// We want a color model that...
//
// * ...can be safely, losslessly serialized.
// * ...is Equatable.
public struct OWSColor: Equatable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red.clamp01()
        self.green = green.clamp01()
        self.blue = blue.clamp01()
    }

    public var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

// MARK: -

public enum ConversationColorAppearance: Equatable {
    case solidColor(color: OWSColor)
    case gradient(color1: OWSColor,
                  color2: OWSColor,
                  angleRadians: CGFloat)
}

// MARK: -

// TODO: We might end up renaming this to ConversationColor
//       depending on how the design shakes out.
public enum ConversationColorValue: Equatable {
    case unthemedColor(color: OWSColor)
    case themedColors(lightThemeColor: OWSColor, darkThemeColor: OWSColor)
    // For now, angle is in radians
    //
    // TODO: Finalize actual angle semantics.
    case gradient(lightThemeColor1: OWSColor,
                  lightThemeColor2: OWSColor,
                  darkThemeColor1: OWSColor,
                  darkThemeColor2: OWSColor,
                  angleRadians: CGFloat)

    var appearance: ConversationColorAppearance {
        switch self {
        case .unthemedColor(let color):
            return .solidColor(color: color)
        case .themedColors(let lightThemeColor, let darkThemeColor):
            return .solidColor(color: Theme.isDarkThemeEnabled ? darkThemeColor : lightThemeColor)
        case .gradient(let lightThemeColor1,
                       let lightThemeColor2,
                       let darkThemeColor1,
                       let darkThemeColor2,
                       let angleRadians):
            return .gradient(color1: Theme.isDarkThemeEnabled ? darkThemeColor1 : lightThemeColor1,
                             color2: Theme.isDarkThemeEnabled ? darkThemeColor2 : lightThemeColor2,
                             angleRadians: angleRadians)
        }
    }
}

// MARK: -

// A round "swatch" that offers a preview of a conversation color option.
public class ConversationColorPreviewView: ManualLayoutViewWithLayer {
    private var conversationColorValue: ConversationColorValue

    public enum Mode {
        case circle
        case rectangle
    }
    private let mode: Mode

    public init(conversationColorValue: ConversationColorValue, mode: Mode) {
        self.conversationColorValue = conversationColorValue
        self.mode = mode

        super.init(name: "ConversationColorSwatchView")

        configure()

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .ThemeDidChange, object: nil)

        addLayoutBlock { view in
            guard let view = view as? ConversationColorPreviewView else { return }
            view.configure()
        }
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String) {
        owsFail("Do not use this initializer.")
    }

    @objc
    private func themeDidChange() {
        configure()
    }

    private struct State: Equatable {
        let size: CGSize
        let appearance: ConversationColorAppearance
    }
    private var state: State?

    private func configure() {
        let size = bounds.size
        let appearance = conversationColorValue.appearance
        let newState = State(size: size, appearance: appearance)
        // Exit early if the appearance and bounds haven't changed.
        guard state != newState else {
            return
        }
        self.state = newState

        switch mode {
        case .circle:
            self.layer.cornerRadius = size.smallerAxis
            self.clipsToBounds = true
        case .rectangle:
            self.layer.cornerRadius = 0
            self.clipsToBounds = false
        }

        switch appearance {
        case .solidColor(let color):
            backgroundColor = color.uiColor
        case .gradient(let color1, let color2, let angleRadians):
            // TODO:
            backgroundColor = color1.uiColor
        }
    }
}

// MARK: -

// public class ConversationColors {
// }
