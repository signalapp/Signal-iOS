//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// We want a color model that...
//
// * ...can be safely, losslessly serialized.
// * ...is Equatable.
public struct OWSColor: Equatable, Codable {
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
public enum ConversationColorValue: Equatable, Codable {
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

    private enum TypeKey: UInt, Codable {
        case unthemedColor = 0
        case themedColors = 1
        case gradient = 2
    }

    private enum CodingKeys: String, CodingKey {
        case typeKey
        case color
        case lightThemeColor1
        case darkThemeColor1
        case lightThemeColor2
        case darkThemeColor2
        case angleRadians
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let typeKey = try container.decode(TypeKey.self, forKey: .typeKey)
        switch typeKey {
        case .unthemedColor:
            let color = try container.decode(OWSColor.self, forKey: .color)
            self = .unthemedColor(color: color)
        case .themedColors:
            let lightThemeColor = try container.decode(OWSColor.self, forKey: .lightThemeColor1)
            let darkThemeColor = try container.decode(OWSColor.self, forKey: .darkThemeColor2)
            self = .themedColors(lightThemeColor: lightThemeColor, darkThemeColor: darkThemeColor)
        case .gradient:
            let lightThemeColor1 = try container.decode(OWSColor.self, forKey: .lightThemeColor1)
            let darkThemeColor1 = try container.decode(OWSColor.self, forKey: .darkThemeColor1)
            let lightThemeColor2 = try container.decode(OWSColor.self, forKey: .lightThemeColor2)
            let darkThemeColor2 = try container.decode(OWSColor.self, forKey: .darkThemeColor2)
            let angleRadians = try container.decode(CGFloat.self, forKey: .angleRadians)
            self = .gradient(lightThemeColor1: lightThemeColor1,
                             lightThemeColor2: lightThemeColor2,
                             darkThemeColor1: darkThemeColor1,
                             darkThemeColor2: darkThemeColor2,
                             angleRadians: angleRadians)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .unthemedColor(let color):
            try container.encode(TypeKey.unthemedColor, forKey: .typeKey)
            try container.encode(color, forKey: .color)
        case .themedColors(let lightThemeColor, let darkThemeColor):
            try container.encode(TypeKey.themedColors, forKey: .typeKey)
            try container.encode(lightThemeColor, forKey: .lightThemeColor1)
            try container.encode(darkThemeColor, forKey: .darkThemeColor1)
        case .gradient(let lightThemeColor1,
                       let lightThemeColor2,
                       let darkThemeColor1,
                       let darkThemeColor2,
                       let angleRadians):
            try container.encode(TypeKey.gradient, forKey: .typeKey)
            try container.encode(lightThemeColor1, forKey: .lightThemeColor1)
            try container.encode(darkThemeColor1, forKey: .darkThemeColor1)
            try container.encode(lightThemeColor2, forKey: .lightThemeColor2)
            try container.encode(darkThemeColor2, forKey: .darkThemeColor2)
            try container.encode(angleRadians, forKey: .angleRadians)
        }
    }

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

public class ConversationColors {
    @available(*, unavailable, message: "Do not instantiate this class.")
    private init() {}

    private static let keyValueStore = SDSKeyValueStore(collection: "ConversationColors")

    private static let defaultKey = "defaultKey"

    public static func defaultConversationColor(transaction: SDSAnyReadTransaction) -> ConversationColorValue {
        // TODO:
        let defaultValue: ConversationColorValue = .unthemedColor(color: .init(red: 1,
                                                                               green: 0,
                                                                               blue: 0))

        return getConversationColor(key: defaultKey, defaultValue: defaultValue, transaction: transaction)
    }

    public static func setDefaultConversationColor(_ value: ConversationColorValue,
                                                   transaction: SDSAnyWriteTransaction) {
        setConversationColor(key: defaultKey, value: value, transaction: transaction)
    }

    private static func getConversationColor(key: String,
                                             defaultValue: ConversationColorValue,
                                             transaction: SDSAnyReadTransaction) -> ConversationColorValue {
        if let value = { () -> ConversationColorValue? in
            do {
                return try keyValueStore.getCodableValue(forKey: key,
                                                         transaction: transaction)
            } catch {
                owsFailDebug("Error: \(error)")
                return nil
            }
        }() {
            return value
        } else {
            return defaultValue
        }
    }

    static let conversationColorDidChange = NSNotification.Name("conversationColorDidChange")
    static let conversationColorDidChangeThreadUniqueIdKey = "conversationColorDidChangeThreadUniqueIdKey"

    private static func setConversationColor(key: String,
                                             value: ConversationColorValue,
                                             transaction: SDSAnyWriteTransaction) {
        do {
            try keyValueStore.setCodable(value, key: key, transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
        }

        // TODO: Notifications.
        NotificationCenter.default.postNotificationNameAsync(
            Self.conversationColorDidChange,
            object: nil,
            userInfo: [
                conversationColorDidChangeThreadUniqueIdKey: key
            ]
        )
    }
}
