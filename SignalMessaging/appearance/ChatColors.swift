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

public enum ChatColorAppearance: Equatable {
    case solidColor(color: OWSColor)
    case gradient(color1: OWSColor,
                  color2: OWSColor,
                  angleRadians: CGFloat)
}

// MARK: -

// TODO: We might end up renaming this to ChatColor
//       depending on how the design shakes out.
public enum ChatColorValue: Equatable, Codable {
//    case auto
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
//        case auto = 3
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
//        case .auto:
//            self = .auto
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
//        case .auto:
//            try container.encode(TypeKey.auto, forKey: .typeKey)
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

    public var appearance: ChatColorAppearance {
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

public class ChatColors {
    @available(*, unavailable, message: "Do not instantiate this class.")
    private init() {}

    private static let keyValueStore = SDSKeyValueStore(collection: "ChatColors")

    private static let defaultKey = "defaultKey"

    private static let noWallpaperAutoChatColor: ChatColorValue = {
        // UIColor.ows_accentBlue = 0x2C6BED
        .unthemedColor(color: .init(red: CGFloat(0x2C) / CGFloat(0xff),
                                    green: CGFloat(0x6B) / CGFloat(0xff),
                                    blue: CGFloat(0xED) / CGFloat(0xff)))
    }()

    public static func autoChatColor(forThread thread: TSThread?,
                                     transaction: SDSAnyReadTransaction) -> ChatColorValue {
        if let wallpaper = Wallpaper.get(for: thread, transaction: transaction) {
            return autoChatColor(forWallpaper: wallpaper)
        } else {
            return Self.noWallpaperAutoChatColor
        }
    }

    public static func autoChatColor(forWallpaper wallpaper: Wallpaper) -> ChatColorValue {
        // TODO:
        let defaultValue: ChatColorValue = .unthemedColor(color: .init(red: 1,
                                                                       green: 0,
                                                                       blue: 0))
        return defaultValue
    }

    // Returns nil for default/auto.
    public static func defaultChatColorSetting(transaction: SDSAnyReadTransaction) -> ChatColorValue? {
        getChatColor(key: defaultKey, transaction: transaction)
    }

    // TODO: When is this applied? Lazily?
    public static func defaultChatColorForRendering(transaction: SDSAnyReadTransaction) -> ChatColorValue {
        if let value = defaultChatColorSetting(transaction: transaction) {
            return value
        } else {
            return autoChatColor(forThread: nil, transaction: transaction)
        }
    }

    public static func setDefaultChatColor(_ value: ChatColorValue?,
                                           transaction: SDSAnyWriteTransaction) {
        setChatColor(key: defaultKey, value: value, transaction: transaction)
    }

    // Returns nil for default/auto.
    public static func chatColorSetting(thread: TSThread,
                                        transaction: SDSAnyReadTransaction) -> ChatColorValue? {
        getChatColor(key: thread.uniqueId, transaction: transaction)
    }

    public static func chatColorForRendering(thread: TSThread,
                                             transaction: SDSAnyReadTransaction) -> ChatColorValue {
        if let value = chatColorSetting(thread: thread, transaction: transaction) {
            return value
        } else {
            return autoChatColor(forThread: thread, transaction: transaction)
        }
    }

    public static func setChatColor(_ value: ChatColorValue?,
                                    thread: TSThread,
                                    transaction: SDSAnyWriteTransaction) {
        setChatColor(key: thread.uniqueId, value: value, transaction: transaction)
    }

    private static func getChatColor(key: String,
                                     transaction: SDSAnyReadTransaction) -> ChatColorValue? {
        if let value = { () -> ChatColorValue? in
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
            return nil
        }
    }

    public static let defaultChatColorDidChange = NSNotification.Name("defaultChatColorDidChange")
    public static let chatColorDidChange = NSNotification.Name("chatColorDidChange")
    public static let chatColorDidChangeThreadUniqueIdKey = "chatColorDidChangeThreadUniqueIdKey"

    private static func setChatColor(key: String,
                                     value: ChatColorValue?,
                                     transaction: SDSAnyWriteTransaction) {
        do {
            if let value = value {
                try keyValueStore.setCodable(value, key: key, transaction: transaction)
            } else {
                keyValueStore.removeValue(forKey: key, transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error)")
        }

        if key == defaultKey {
            NotificationCenter.default.postNotificationNameAsync(
                Self.defaultChatColorDidChange,
                object: nil,
                userInfo: nil
            )
        } else {
            NotificationCenter.default.postNotificationNameAsync(
                Self.chatColorDidChange,
                object: nil,
                userInfo: [
                    chatColorDidChangeThreadUniqueIdKey: key
                ]
            )
        }
    }

    // MARK: -

    public static var builtInValues: [ChatColorValue] {
        // TODO:
        [
            .unthemedColor(color: OWSColor(red: 0.5, green: 0.5, blue: 0.5)),
            .unthemedColor(color: OWSColor(red: 0, green: 0, blue: 1)),
            .unthemedColor(color: OWSColor(red: 0, green: 1, blue: 0)),

            .themedColors(lightThemeColor: OWSColor(red: 0, green: 1, blue: 0),
                          darkThemeColor: OWSColor(red: 0, green: 1, blue: 0.5)),

            .gradient(lightThemeColor1: OWSColor(red: 0, green: 1, blue: 0),
                      lightThemeColor2: OWSColor(red: 0, green: 1, blue: 0),
                      darkThemeColor1: OWSColor(red: 0, green: 1, blue: 0.5),
                      darkThemeColor2: OWSColor(red: 0, green: 1, blue: 0.5),
                      angleRadians: CGFloat.pi * 0.25)
        ]
    }

    public static func customValues(transaction: SDSAnyReadTransaction) -> [ChatColorValue] {
        // TODO:
        [
            .unthemedColor(color: OWSColor(red: 0, green: 0, blue: 0))
        ]
    }
}
