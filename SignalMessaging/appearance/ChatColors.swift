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

    var description: String {
        "[red: \(red), green: \(green), blue: \(blue)]"
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
    case solidColor(color: OWSColor)
    // For now, angle is in radians
    //
    // TODO: Finalize actual angle semantics.
    case gradient(gradientColor1: OWSColor,
                  gradientColor2: OWSColor,
                  angleRadians: CGFloat)

    private enum TypeKey: UInt, Codable {
        case solidColor = 0
        case gradient = 1
    }

    private enum CodingKeys: String, CodingKey {
        case typeKey
        case solidColor
        case gradientColor1
        case gradientColor2
        case angleRadians
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let typeKey = try container.decode(TypeKey.self, forKey: .typeKey)
        switch typeKey {
        case .solidColor:
            let color = try container.decode(OWSColor.self, forKey: .solidColor)
            self = .solidColor(color: color)
        case .gradient:
            let gradientColor1 = try container.decode(OWSColor.self, forKey: .gradientColor1)
            let gradientColor2 = try container.decode(OWSColor.self, forKey: .gradientColor2)
            let angleRadians = try container.decode(CGFloat.self, forKey: .angleRadians)
            self = .gradient(gradientColor1: gradientColor1,
                             gradientColor2: gradientColor2,
                             angleRadians: angleRadians)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .solidColor(let solidColor):
            try container.encode(TypeKey.solidColor, forKey: .typeKey)
            try container.encode(solidColor, forKey: .solidColor)
        case .gradient(let gradientColor1, let gradientColor2, let angleRadians):
            try container.encode(TypeKey.gradient, forKey: .typeKey)
            try container.encode(gradientColor1, forKey: .gradientColor1)
            try container.encode(gradientColor2, forKey: .gradientColor2)
            try container.encode(angleRadians, forKey: .angleRadians)
        }
    }

    public var appearance: ChatColorAppearance {
        switch self {
        case .solidColor(let solidColor):
            return .solidColor(color: solidColor)
        case .gradient(let gradientColor1, let gradientColor2, let angleRadians):
            return .gradient(color1: gradientColor1,
                             color2: gradientColor2,
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
        let color = OWSColor(red: CGFloat(0x2C) / CGFloat(0xff),
                             green: CGFloat(0x6B) / CGFloat(0xff),
                             blue: CGFloat(0xED) / CGFloat(0xff))
        return .solidColor(color: color)
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
        let color = OWSColor(red: 1, green: 0, blue: 0)
        return .solidColor(color: color)
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
            .solidColor(color: OWSColor(red: 0.5, green: 0.5, blue: 0.5)),
            .solidColor(color: OWSColor(red: 0, green: 0, blue: 1)),
            .solidColor(color: OWSColor(red: 0, green: 1, blue: 0)),
            .solidColor(color: OWSColor(red: 0, green: 1, blue: 0.5)),

            .gradient(gradientColor1: OWSColor(red: 0, green: 1, blue: 0),
                      gradientColor2: OWSColor(red: 0, green: 1, blue: 0.5),
                      angleRadians: CGFloat.pi * 0.25)
        ]
    }

    public static func customValues(transaction: SDSAnyReadTransaction) -> [ChatColorValue] {
        // TODO:
        [
            .solidColor(color: OWSColor(red: 0, green: 0, blue: 0))
        ]
    }
}
