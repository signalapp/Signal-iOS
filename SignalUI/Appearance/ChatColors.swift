//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Represents the chat color chosen for a particular scope.
///
/// Possible scopes (ordered by priority):
/// (1) Thread: Applies to a specific conversation.
/// (2) Global: Applies to all other conversations.
///
/// On its own, a `ChatColorSetting` may not contain enough information to
/// compute the color to use for a particular conversation. To compute the
/// color to use, you generally need the `ChatColorSetting` for both scopes,
/// the `Wallpaper` for both scopes (which may have their own preferred
/// color), and the default fallback.
public enum ChatColorSetting: Equatable {
    case auto
    case builtIn(PaletteChatColor)
    case custom(CustomChatColor.Key, CustomChatColor)

    public var constantColor: ColorOrGradientSetting? {
        switch self {
        case .auto:
            return nil
        case .builtIn(let value):
            return value.colorSetting
        case .custom(_, let value):
            return value.colorSetting
        }
    }

    public static func == (lhs: ChatColorSetting, rhs: ChatColorSetting) -> Bool {
        switch (lhs, rhs) {
        case (.auto, .auto):
            return true
        case (.builtIn(let lhs), .builtIn(let rhs)) where lhs.rawValue == rhs.rawValue:
            return true
        case (.custom(let lhs, _), .custom(let rhs, _)) where lhs.rawValue == rhs.rawValue:
            return true
        default:
            return false
        }
    }
}

public struct CustomChatColor: Codable {
    public struct Key {
        public let rawValue: String

        public static func generateRandom() -> Self {
            return Key(rawValue: UUID().uuidString)
        }
    }

    public let colorSetting: ColorOrGradientSetting
    public let creationTimestamp: UInt64

    public init(colorSetting: ColorOrGradientSetting, creationTimestamp: UInt64) {
        self.colorSetting = colorSetting
        self.creationTimestamp = creationTimestamp
    }

    private enum CodingKeys: String, CodingKey {
        case colorSetting = "setting"
        case creationTimestamp

        // Deprecated keys that may still exist in values stored in the database:
        // - "id"
        // - "isBuiltIn"
        // - "updateTimestamp"
    }
}

// MARK: -

public class ChatColors: Dependencies {
    public enum Constants {
        fileprivate static let globalKey = "defaultKey"
        public static let defaultColor: PaletteChatColor = .ultramarine
    }

    public init() {
        SwiftSingletons.register(self)
    }

    /// The keys in this store are `CustomChatColor.Key`. The values are
    /// `CustomChatColor`s.
    private static let customColorsStore = SDSKeyValueStore(collection: "customColorsStore.3")

    public func fetchCustomValues(tx: SDSAnyReadTransaction) -> [(key: CustomChatColor.Key, value: CustomChatColor)] {
        var customChatColors = [(key: CustomChatColor.Key, value: CustomChatColor)]()
        for key in Self.customColorsStore.allKeys(transaction: tx) {
            let colorKey = CustomChatColor.Key(rawValue: key)
            guard let colorValue = Self.fetchCustomValue(for: colorKey, tx: tx) else { continue }
            customChatColors.append((colorKey, colorValue))
        }
        return customChatColors.sorted(by: { $0.value.creationTimestamp < $1.value.creationTimestamp })
    }

    public static func fetchCustomValue(for key: CustomChatColor.Key, tx: SDSAnyReadTransaction) -> CustomChatColor? {
        do {
            return try customColorsStore.getCodableValue(forKey: key.rawValue, transaction: tx)
        } catch {
            owsFailDebug("Couldn't decode custom color: \(error)")
            return nil
        }
    }

    public func upsertCustomValue(_ value: CustomChatColor, for key: CustomChatColor.Key, tx: SDSAnyWriteTransaction) {
        do {
            try Self.customColorsStore.setCodable(value, key: key.rawValue, transaction: tx)
        } catch {
            owsFailDebug("Couldn't save custom color: \(error)")
        }
        Self.postChatColorsDidChangeNotification(for: nil, tx: tx)
    }

    public func deleteCustomValue(for key: CustomChatColor.Key, tx: SDSAnyWriteTransaction) {
        Self.customColorsStore.removeValue(forKey: key.rawValue, transaction: tx)
        Self.postChatColorsDidChangeNotification(for: nil, tx: tx)
    }

    /// Returns the number of conversations that use a given value.
    public static func usageCount(of colorKey: CustomChatColor.Key, tx: SDSAnyReadTransaction) -> Int {
        let chatColorSettingStore = DependenciesBridge.shared.chatColorSettingStore
        var count: Int = 0
        for scopeKey in chatColorSettingStore.fetchAllScopeKeys(tx: tx.asV2Read) {
            if colorKey.rawValue == chatColorSettingStore.fetchRawSetting(for: scopeKey, tx: tx.asV2Read) {
                count += 1
            }
        }
        return count
    }

    /// The color that should actually be used when rendering messages.
    ///
    /// - Parameters:
    ///   - previewWallpaper: If provided, use this `Wallpaper` rather than the
    ///   one that's currently assigned. This is useful if you want to preview
    ///   the rendered color when selecting `Wallpaper`. (The logic is more
    ///   complicated than checking the color for the `Wallpaper` since it may
    ///   be overridden by an explicit color that takes precedence.)
    ///
    /// - Returns: The color to use for outgoing message bubbles.
    public static func resolvedChatColor(
        for thread: TSThread?,
        previewWallpaper: Wallpaper? = nil,
        tx: SDSAnyReadTransaction
    ) -> ColorOrGradientSetting {
        if let threadColor = chatColorSetting(for: thread, tx: tx).constantColor {
            return threadColor
        }
        return autoChatColor(for: thread, previewWallpaper: previewWallpaper, tx: tx)
    }

    /// The color that should be rendered in the "auto" bubble in the chat color editor.
    ///
    /// For the global scope, this will either be the wallpaper color or the
    /// default fallback.
    ///
    /// For the thread scope, this might be the global color, global wallpaper,
    /// thread wallpaper, or default fallback.
    public static func autoChatColor(for thread: TSThread?, tx: SDSAnyReadTransaction) -> ColorOrGradientSetting {
        return autoChatColor(for: thread, previewWallpaper: nil, tx: tx)
    }

    private static func autoChatColor(
        for thread: TSThread?,
        previewWallpaper: Wallpaper?,
        tx: SDSAnyReadTransaction
    ) -> ColorOrGradientSetting {
        // If we're editing the color for a specific thread, then we'll prefer the
        // globally-selected value instead of both the thread-specific and global
        // wallpaper values.
        if thread != nil, let globalColor = chatColorSetting(for: nil, tx: tx).constantColor {
            return globalColor
        }
        let resolvedWallpaper = previewWallpaper ?? Wallpaper.wallpaperForRendering(for: thread, transaction: tx)
        if let wallpaperColor = resolvedWallpaper?.defaultChatColor {
            return wallpaperColor.colorSetting
        }
        return Constants.defaultColor.colorSetting
    }

    /// The currently-chosen setting for a particular scope.
    ///
    /// This doesn't always contain enough information to render a color on the
    /// screen. For example, a user may choose `.auto`, in which case you need
    /// to run additional logic to determine which color corresponds to `.auto`.
    public static func chatColorSetting(for thread: TSThread?, tx: SDSAnyReadTransaction) -> ChatColorSetting {
        let chatColorSettingStore = DependenciesBridge.shared.chatColorSettingStore
        let persistenceKey: String = thread?.uniqueId ?? Constants.globalKey
        guard let valueId = chatColorSettingStore.fetchRawSetting(for: persistenceKey, tx: tx.asV2Read) else {
            return .auto
        }
        if let paletteChatColor = PaletteChatColor(rawValue: valueId) {
            return .builtIn(paletteChatColor)
        }
        let customColorKey = CustomChatColor.Key(rawValue: valueId)
        if let customChatColor = Self.fetchCustomValue(for: customColorKey, tx: tx) {
            return .custom(customColorKey, customChatColor)
        }
        // This isn't necessarily an error. A user might apply a custom chat color
        // value to a conversation (or the global default), then delete the custom
        // chat color value. In that case, all references to the value should
        // behave as "auto" (the default).
        return .auto
    }

    public static let chatColorsDidChangeNotification = NSNotification.Name("chatColorsDidChange")

    public static func setChatColorSetting(_ value: ChatColorSetting, for thread: TSThread?, tx: SDSAnyWriteTransaction) {
        let chatColorSettingStore = DependenciesBridge.shared.chatColorSettingStore
        chatColorSettingStore.setRawSetting({ () -> String? in
            switch value {
            case .auto:
                return nil
            case .builtIn(let paletteChatColor):
                return paletteChatColor.rawValue
            case .custom(let colorKey, _):
                return colorKey.rawValue
            }
        }(), for: thread?.uniqueId ?? Constants.globalKey, tx: tx.asV2Write)
        postChatColorsDidChangeNotification(for: thread, tx: tx)
    }

    public static func resetAllSettings(transaction tx: SDSAnyWriteTransaction) {
        DependenciesBridge.shared.chatColorSettingStore.resetAllSettings(tx: tx.asV2Write)
        postChatColorsDidChangeNotification(for: nil, tx: tx)
    }

    private static func postChatColorsDidChangeNotification(for thread: TSThread?, tx: SDSAnyWriteTransaction) {
        let threadUniqueId = thread?.uniqueId
        tx.addAsyncCompletionOnMain {
            NotificationCenter.default.post(name: chatColorsDidChangeNotification, object: threadUniqueId)
        }
    }

    // MARK: -
}

public enum PaletteChatColor: String, CaseIterable {
    // Default
    case ultramarine = "Ultramarine"

    // Solid Colors
    case crimson = "Crimson"
    case vermilion = "Vermilion"
    case burlap = "Burlap"
    case forest = "Forest"
    case wintergreen = "Wintergreen"
    case teal = "Teal"
    case blue = "Blue"
    case indigo = "Indigo"
    case violet = "Violet"
    case plum = "Plum"
    case taupe = "Taupe"
    case steel = "Steel"

    // Gradients
    case ember = "Ember"
    case midnight = "Midnight"
    case infrared = "Infrared"
    case lagoon = "Lagoon"
    case fluorescent = "Fluorescent"
    case basil = "Basil"
    case sublime = "Sublime"
    case sea = "Sea"
    case tangerine = "Tangerine"

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
                gradientColor1: UIColor(rgbHex: 0x0552F0).asOWSColor,
                gradientColor2: UIColor(rgbHex: 0x2C6BED).asOWSColor,
                angleRadians: CGFloat.pi * 0
            )
        case .crimson:
            return .solidColor(color: UIColor(rgbHex: 0xCF163E).asOWSColor)
        case .vermilion:
            return .solidColor(color: UIColor(rgbHex: 0xC73F0A).asOWSColor)
        case .burlap:
            return .solidColor(color: UIColor(rgbHex: 0x6F6A58).asOWSColor)
        case .forest:
            return .solidColor(color: UIColor(rgbHex: 0x3B7845).asOWSColor)
        case .wintergreen:
            return .solidColor(color: UIColor(rgbHex: 0x1D8663).asOWSColor)
        case .teal:
            return .solidColor(color: UIColor(rgbHex: 0x077D92).asOWSColor)
        case .blue:
            return .solidColor(color: UIColor(rgbHex: 0x336BA3).asOWSColor)
        case .indigo:
            return .solidColor(color: UIColor(rgbHex: 0x6058CA).asOWSColor)
        case .violet:
            return .solidColor(color: UIColor(rgbHex: 0x9932C8).asOWSColor)
        case .plum:
            return .solidColor(color: UIColor(rgbHex: 0xAA377A).asOWSColor)
        case .taupe:
            return .solidColor(color: UIColor(rgbHex: 0x8F616A).asOWSColor)
        case .steel:
            return .solidColor(color: UIColor(rgbHex: 0x71717F).asOWSColor)
        case .ember:
            return .gradient(
                gradientColor1: UIColor(rgbHex: 0xE57C00).asOWSColor,
                gradientColor2: UIColor(rgbHex: 0x5E0000).asOWSColor,
                angleRadians: Self.parseAngleDegreesFromSpec(168)
            )
        case .midnight:
            return .gradient(
                gradientColor1: UIColor(rgbHex: 0x2C2C3A).asOWSColor,
                gradientColor2: UIColor(rgbHex: 0x787891).asOWSColor,
                angleRadians: Self.parseAngleDegreesFromSpec(180)
            )
        case .infrared:
            return .gradient(
                gradientColor1: UIColor(rgbHex: 0xF65560).asOWSColor,
                gradientColor2: UIColor(rgbHex: 0x442CED).asOWSColor,
                angleRadians: Self.parseAngleDegreesFromSpec(192)
            )
        case .lagoon:
            return .gradient(
                gradientColor1: UIColor(rgbHex: 0x004066).asOWSColor,
                gradientColor2: UIColor(rgbHex: 0x32867D).asOWSColor,
                angleRadians: Self.parseAngleDegreesFromSpec(180)
            )
        case .fluorescent:
            return .gradient(
                gradientColor1: UIColor(rgbHex: 0xEC13DD).asOWSColor,
                gradientColor2: UIColor(rgbHex: 0x1B36C6).asOWSColor,
                angleRadians: Self.parseAngleDegreesFromSpec(192)
            )
        case .basil:
            return .gradient(
                gradientColor1: UIColor(rgbHex: 0x2F9373).asOWSColor,
                gradientColor2: UIColor(rgbHex: 0x077343).asOWSColor,
                angleRadians: Self.parseAngleDegreesFromSpec(180)
            )
        case .sublime:
            return .gradient(
                gradientColor1: UIColor(rgbHex: 0x6281D5).asOWSColor,
                gradientColor2: UIColor(rgbHex: 0x974460).asOWSColor,
                angleRadians: Self.parseAngleDegreesFromSpec(180)
            )
        case .sea:
            return .gradient(
                gradientColor1: UIColor(rgbHex: 0x498FD4).asOWSColor,
                gradientColor2: UIColor(rgbHex: 0x2C66A0).asOWSColor,
                angleRadians: Self.parseAngleDegreesFromSpec(180)
            )
        case .tangerine:
            return .gradient(
                gradientColor1: UIColor(rgbHex: 0xDB7133).asOWSColor,
                gradientColor2: UIColor(rgbHex: 0x911231).asOWSColor,
                angleRadians: Self.parseAngleDegreesFromSpec(192)
            )
        }
    }
}

// MARK: -

public extension ChatColors {

    // Represents the "message sender" to "group name color" mapping
    // for a given CVC load.
    struct GroupNameColors {
        fileprivate let colorMap: [SignalServiceAddress: UIColor]
        // TODO: Pending design.
        fileprivate let defaultColor: UIColor

        public func color(for address: SignalServiceAddress) -> UIColor {
            colorMap[address] ?? defaultColor
        }

        fileprivate static var defaultColors: GroupNameColors {
            GroupNameColors(colorMap: [:], defaultColor: Theme.primaryTextColor)
        }
    }

    static func groupNameColors(forThread thread: TSThread) -> GroupNameColors {
        guard let groupThread = thread as? TSGroupThread else {
            return .defaultColors
        }
        let groupMembership = groupThread.groupMembership
        let values = Self.groupNameColorValues
        let isDarkThemeEnabled = Theme.isDarkThemeEnabled
        var lastIndex: Int = 0
        var colorMap = [SignalServiceAddress: UIColor]()
        let addresses = Array(groupMembership.fullMembers).stableSort()
        for (index, address) in addresses.enumerated() {
            let valueIndex = index % values.count
            guard let value = values[safe: valueIndex] else {
                owsFailDebug("Invalid values.")
                return .defaultColors
            }
            colorMap[address] = value.color(isDarkThemeEnabled: isDarkThemeEnabled)
            lastIndex = index
        }
        let defaultValueIndex = (lastIndex + 1) % values.count
        guard let defaultValue = values[safe: defaultValueIndex] else {
            owsFailDebug("Invalid values.")
            return .defaultColors
        }
        let defaultColor = defaultValue.color(isDarkThemeEnabled: isDarkThemeEnabled)
        return GroupNameColors(colorMap: colorMap, defaultColor: defaultColor)
    }

    private static var defaultGroupNameColor: UIColor {
        let isDarkThemeEnabled = Theme.isDarkThemeEnabled
        return Self.groupNameColorValues.first!.color(isDarkThemeEnabled: isDarkThemeEnabled)
    }

    fileprivate struct GroupNameColorValue {
        let lightTheme: UIColor
        let darkTheme: UIColor

        func color(isDarkThemeEnabled: Bool) -> UIColor {
            isDarkThemeEnabled ? darkTheme : lightTheme
        }
    }

    // In descending order of contrast with the other values.
    fileprivate static let groupNameColorValues: [GroupNameColorValue] = [
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x006DA3),
                            darkTheme: UIColor(rgbHex: 0x00A7FA)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x007A3D),
                            darkTheme: UIColor(rgbHex: 0x00B85C)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xC13215),
                            darkTheme: UIColor(rgbHex: 0xFF6F52)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xB814B8),
                            darkTheme: UIColor(rgbHex: 0xF65AF6)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x5B6976),
                            darkTheme: UIColor(rgbHex: 0x8BA1B6)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x3D7406),
                            darkTheme: UIColor(rgbHex: 0x5EB309)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xCC0066),
                            darkTheme: UIColor(rgbHex: 0xF76EB2)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x2E51FF),
                            darkTheme: UIColor(rgbHex: 0x8599FF)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x9C5711),
                            darkTheme: UIColor(rgbHex: 0xD5920B)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x007575),
                            darkTheme: UIColor(rgbHex: 0x00B2B2)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xD00B4D),
                            darkTheme: UIColor(rgbHex: 0xFF6B9C)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x8F2AF4),
                            darkTheme: UIColor(rgbHex: 0xBF80FF)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xD00B0B),
                            darkTheme: UIColor(rgbHex: 0xFF7070)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x067906),
                            darkTheme: UIColor(rgbHex: 0x0AB80A)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x5151F6),
                            darkTheme: UIColor(rgbHex: 0x9494FF)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x866118),
                            darkTheme: UIColor(rgbHex: 0xD68F00)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x067953),
                            darkTheme: UIColor(rgbHex: 0x00B87A)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xA20CED),
                            darkTheme: UIColor(rgbHex: 0xCF7CF8)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x4B7000),
                            darkTheme: UIColor(rgbHex: 0x74AD00)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xC70A88),
                            darkTheme: UIColor(rgbHex: 0xF76EC9)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xB34209),
                            darkTheme: UIColor(rgbHex: 0xF57A3D)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x06792D),
                            darkTheme: UIColor(rgbHex: 0x0AB844)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x7A3DF5),
                            darkTheme: UIColor(rgbHex: 0xAF8AF9)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x6B6B24),
                            darkTheme: UIColor(rgbHex: 0xA4A437)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xD00B2C),
                            darkTheme: UIColor(rgbHex: 0xF77389)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x2D7906),
                            darkTheme: UIColor(rgbHex: 0x42B309)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xAF0BD0),
                            darkTheme: UIColor(rgbHex: 0xE06EF7)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x32763E),
                            darkTheme: UIColor(rgbHex: 0x4BAF5C)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x2662D9),
                            darkTheme: UIColor(rgbHex: 0x7DA1E8)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x76681E),
                            darkTheme: UIColor(rgbHex: 0xB89B0A)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x067462),
                            darkTheme: UIColor(rgbHex: 0x09B397)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x6447F5),
                            darkTheme: UIColor(rgbHex: 0xA18FF9)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x5E6E0C),
                            darkTheme: UIColor(rgbHex: 0x8FAA09)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x077288),
                            darkTheme: UIColor(rgbHex: 0x00AED1)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0xC20AA3),
                            darkTheme: UIColor(rgbHex: 0xF75FDD)),
        GroupNameColorValue(lightTheme: UIColor(rgbHex: 0x2D761E),
                            darkTheme: UIColor(rgbHex: 0x43B42D))
    ]
}
