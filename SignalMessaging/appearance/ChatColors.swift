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

    public var asUIColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }

    var description: String {
        "[red: \(red), green: \(green), blue: \(blue)]"
    }
}

// MARK: -

public enum ChatColorAppearance: Equatable, Codable {
    case solidColor(color: OWSColor)
    // If angleRadians = 0, gradientColor1 is N.
    // If angleRadians = PI / 2, gradientColor1 is E.
    // etc.
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
}

// MARK: -

// TODO: We might end up renaming this to ChatColor
//       depending on how the design shakes out.
public struct ChatColorValue: Equatable, Codable {
    public let id: String
    public let appearance: ChatColorAppearance
    public let isBuiltIn: Bool
    public let creationTimestamp: UInt64
    public let updateTimestamp: UInt64

    public init(id: String,
                appearance: ChatColorAppearance,
                isBuiltIn: Bool = false,
                creationTimestamp: UInt64 = NSDate.ows_millisecondTimeStamp()) {
        self.id = id
        self.appearance = appearance
        self.isBuiltIn = isBuiltIn
        self.creationTimestamp = creationTimestamp
        self.updateTimestamp = NSDate.ows_millisecondTimeStamp()
    }

    public static var randomId: String {
        UUID().uuidString
    }

    public static var placeholderValue: ChatColorValue {
        ChatColors.noWallpaperAutoChatColor
    }

    // MARK: - Equatable

    public static func == (lhs: ChatColorValue, rhs: ChatColorValue) -> Bool {
        // Ignore timestamps, etc.
        (lhs.id == rhs.id) && (lhs.appearance == rhs.appearance)
    }
}

// MARK: -

@objc
public class ChatColors: NSObject, Dependencies {
    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(warmCaches),
            name: .WarmCaches,
            object: nil
        )
    }

    // The cache should contain all current values at all times.
    @objc
    private func warmCaches() {
        var valueCache = [String: ChatColorValue]()

        // Load built-in colors.
        for value in Self.builtInValues {
            guard valueCache[value.id] == nil else {
                owsFailDebug("Duplicate value: \(value.id).")
                continue
            }
            valueCache[value.id] = value
        }

        // Load custom colors.
        Self.databaseStorage.read { transaction in
            let keys = Self.customColorsStore.allKeys(transaction: transaction)
            for key in keys {
                func loadValue() -> ChatColorValue? {
                    do {
                        return try Self.customColorsStore.getCodableValue(forKey: key, transaction: transaction)
                    } catch {
                        owsFailDebug("Error: \(error)")
                        return nil
                    }
                }
                guard let value = loadValue() else {
                    owsFailDebug("Missing value: \(key)")
                    continue
                }
                guard valueCache[value.id] == nil else {
                    owsFailDebug("Duplicate value: \(value.id).")
                    continue
                }
                valueCache[value.id] = value
            }
        }

        Self.unfairLock.withLock {
            self.valueCache = valueCache
        }
    }

    // Represents the current "chat color" setting for a given thread
    // or the default.  "Custom chat colors" have a lifecycle independent
    // from the conversations/global defaults which use them.
    //
    // The keys in this store are thread unique ids _OR_ defaultKey (String).
    // The values are ChatColorValue.id (String).
    private static let chatColorSettingStore = SDSKeyValueStore(collection: "chatColorSettingStore")

    // The keys in this store are ChatColorValue.id (String).
    // The values are ChatColorValues.
    private static let customColorsStore = SDSKeyValueStore(collection: "customColorsStore.2")

    private static let defaultKey = "defaultKey"

    private static let unfairLock = UnfairLock()
    private var valueCache = [String: ChatColorValue]()

    public func upsertCustomValue(_ value: ChatColorValue, transaction: SDSAnyWriteTransaction) {
        Self.unfairLock.withLock {
            self.valueCache[value.id] = value
            do {
                try Self.customColorsStore.setCodable(value, key: value.id, transaction: transaction)
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        fireCustomChatColorValueDidChange()
    }

    public func deleteCustomValue(_ value: ChatColorValue, transaction: SDSAnyWriteTransaction) {
        Self.unfairLock.withLock {
            self.valueCache.removeValue(forKey: value.id)
            Self.customColorsStore.removeValue(forKey: value.id, transaction: transaction)
        }
        fireCustomChatColorValueDidChange()
    }

    private func fireCustomChatColorValueDidChange() {
        NotificationCenter.default.postNotificationNameAsync(
            Self.customChatColorValueDidChange,
            object: nil,
            userInfo: nil
        )
    }

    private func value(forValueId valueId: String) -> ChatColorValue? {
        Self.unfairLock.withLock {
            self.valueCache[valueId]
        }
    }

    private var allValues: [ChatColorValue] {
        Self.unfairLock.withLock {
            Array(self.valueCache.values)
        }
    }

    public var allValuesSorted: [ChatColorValue] {
        allValues.sorted { (left, right) -> Bool in
            left.creationTimestamp < right.creationTimestamp
        }
    }
    public static var allValuesSorted: [ChatColorValue] { Self.chatColors.allValuesSorted }

    public static let noWallpaperAutoChatColor: ChatColorValue = {
        let color = UIColor.ows_accentBlue.asOWSColor
        return ChatColorValue(id: "noWallpaperAuto", appearance: .solidColor(color: color))
    }()

    public static func autoChatColor(forThread thread: TSThread?,
                                     transaction: SDSAnyReadTransaction) -> ChatColorValue {
        if let wallpaper = Wallpaper.get(for: thread, transaction: transaction),
           wallpaper != .photo {
            return autoChatColor(forWallpaper: wallpaper)
        } else {
            return Self.noWallpaperAutoChatColor
        }
    }

    public static func autoChatColor(forWallpaper wallpaper: Wallpaper) -> ChatColorValue {
        // TODO: Derive actual value from wallpaper.
        let color = OWSColor(red: 1, green: 0, blue: 0)
        return ChatColorValue(id: wallpaper.rawValue, appearance: .solidColor(color: color))
    }

    // Returns nil for default/auto.
    public static func defaultChatColorSetting(transaction: SDSAnyReadTransaction) -> ChatColorValue? {
        chatColorSetting(key: defaultKey, transaction: transaction)
    }

    public static func defaultChatColorForRendering(transaction: SDSAnyReadTransaction) -> ChatColorValue {
        if let value = defaultChatColorSetting(transaction: transaction) {
            return value
        } else {
            return autoChatColor(forThread: nil, transaction: transaction)
        }
    }

    public static func setDefaultChatColorSetting(_ value: ChatColorValue?,
                                           transaction: SDSAnyWriteTransaction) {
        setChatColorSetting(key: defaultKey, value: value, transaction: transaction)
    }

    // Returns nil for default/auto.
    public static func chatColorSetting(thread: TSThread,
                                        transaction: SDSAnyReadTransaction) -> ChatColorValue? {
        chatColorSetting(key: thread.uniqueId, transaction: transaction)
    }

    public static func chatColorForRendering(thread: TSThread,
                                             transaction: SDSAnyReadTransaction) -> ChatColorValue {
        if let value = chatColorSetting(thread: thread, transaction: transaction) {
            return value
        } else {
            return autoChatColor(forThread: thread, transaction: transaction)
        }
    }

    public static func setChatColorSetting(_ value: ChatColorValue?,
                                           thread: TSThread,
                                           transaction: SDSAnyWriteTransaction) {
        setChatColorSetting(key: thread.uniqueId, value: value, transaction: transaction)
    }

    // Returns nil for default/auto.
    private static func chatColorSetting(key: String,
                                         transaction: SDSAnyReadTransaction) -> ChatColorValue? {
        guard let valueId = Self.chatColorSettingStore.getString(key, transaction: transaction) else {
            return nil
        }
        guard let value = Self.chatColors.value(forValueId: valueId) else {
            // This isn't necessarily an error.  A user might apply a custom
            // chat color value to a conversation (or the global default),
            // then delete the custom chat color value.  In that case, all
            // references to the value should behave as "auto" (the default).
            Logger.warn("Missing value: \(valueId).")
            return nil
        }
        return value
    }

    public static let defaultChatColorSettingDidChange = NSNotification.Name("defaultChatColorSettingDidChange")
    public static let chatColorSettingDidChange = NSNotification.Name("chatColorSettingDidChange")
    public static let chatColorSettingDidChangeThreadUniqueIdKey = "chatColorSettingDidChangeThreadUniqueIdKey"
    public static let customChatColorValueDidChange = NSNotification.Name("customChatColorValueDidChange")

    private static func setChatColorSetting(key: String,
                                            value: ChatColorValue?,
                                            transaction: SDSAnyWriteTransaction) {
        if let value = value {
            // Ensure the value is already in the cache.
            if nil == Self.chatColors.value(forValueId: value.id) {
                owsFailDebug("Unknown value: \(value.id).")
            }

            Self.chatColorSettingStore.setString(value.id, key: key, transaction: transaction)
        } else {
            Self.chatColorSettingStore.removeValue(forKey: key, transaction: transaction)
        }

        if key == defaultKey {
            NotificationCenter.default.postNotificationNameAsync(
                Self.defaultChatColorSettingDidChange,
                object: nil,
                userInfo: nil
            )
        } else {
            NotificationCenter.default.postNotificationNameAsync(
                Self.chatColorSettingDidChange,
                object: nil,
                userInfo: [
                    chatColorSettingDidChangeThreadUniqueIdKey: key
                ]
            )
        }
    }

    public static func resetAllSettings(transaction: SDSAnyWriteTransaction) {
        Self.chatColorSettingStore.removeAll(transaction: transaction)
    }

    // MARK: -

    private static var builtInValues: [ChatColorValue] {
        // TODO: Apply values from design.
        return [
            // We use fixed timestamps to ensure that built-in values
            // appear before custom values and to control their relative ordering.
            ChatColorValue(id: "a",
                           appearance: .solidColor(color: OWSColor(red: 0.5, green: 0.5, blue: 0.5)),
                           isBuiltIn: true,
                           creationTimestamp: 1),
            ChatColorValue(id: "b",
                           appearance: .solidColor(color: OWSColor(red: 0, green: 0, blue: 1)),
                           isBuiltIn: true,
                           creationTimestamp: 2),
            ChatColorValue(id: "c",
                           appearance: .solidColor(color: OWSColor(red: 0, green: 1, blue: 0)),
                           isBuiltIn: true,
                           creationTimestamp: 3),
            ChatColorValue(id: "d",
                           appearance: .solidColor(color: OWSColor(red: 0, green: 1, blue: 0.5)),
                           isBuiltIn: true,
                           creationTimestamp: 4),
            ChatColorValue(id: "e",
                           appearance: .gradient(gradientColor1: OWSColor(red: 1, green: 0, blue: 0),
                                                 gradientColor2: OWSColor(red: 0, green: 1, blue: 0),
                                                 angleRadians: CGFloat.pi * 0.25),
                           isBuiltIn: true,
                           creationTimestamp: 5)
        ]
    }
}

// MARK: -

public extension UIColor {
    var asOWSColor: OWSColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        self.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return OWSColor(red: red.clamp01(), green: green.clamp01(), blue: blue.clamp01())
    }
}
