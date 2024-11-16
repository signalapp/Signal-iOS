//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Stores the `ChatColorSetting` for each thread and the global scope. The
/// setting may be a pointer to a `CustomChatColor`.
///
/// The keys in this store are thread unique ids _OR_ "defaultKey". The
/// values are either `PaletteChatColor.rawValue` or `CustomChatColor.Key`.
public class ChatColorSettingStore {
    private let settingStore: KeyValueStore
    /// The keys in this store are `CustomChatColor.Key`. The values are
    /// `CustomChatColor`s.
    private let customColorsStore: KeyValueStore

    private let wallpaperStore: WallpaperStore

    public init(
        wallpaperStore: WallpaperStore
    ) {
        self.settingStore = KeyValueStore(collection: "chatColorSettingStore")
        self.customColorsStore = KeyValueStore(collection: "customColorsStore.3")
        self.wallpaperStore = wallpaperStore
    }

    public func fetchAllScopeKeys(tx: DBReadTransaction) -> [String] {
        return settingStore.allKeys(transaction: tx)
    }

    public func fetchRawSetting(for scopeKey: String, tx: DBReadTransaction) -> String? {
        return settingStore.getString(scopeKey, transaction: tx)
    }

    public func setRawSetting(_ rawValue: String?, for scopeKey: String, tx: DBWriteTransaction) {
        settingStore.setString(rawValue, key: scopeKey, transaction: tx)
    }

    public func resetAllSettings(tx: DBWriteTransaction) {
        settingStore.removeAll(transaction: tx)
        postChatColorsDidChangeNotification(for: nil, tx: tx)
    }

    public enum Constants {
        fileprivate static let globalKey = "defaultKey"
        public static let defaultColor: PaletteChatColor = .ultramarine
    }

    public func fetchCustomValues(tx: DBReadTransaction) -> [(key: CustomChatColor.Key, value: CustomChatColor)] {
        var customChatColors = [(key: CustomChatColor.Key, value: CustomChatColor)]()
        for key in customColorsStore.allKeys(transaction: tx) {
            let colorKey = CustomChatColor.Key(rawValue: key)
            guard let colorValue = fetchCustomValue(for: colorKey, tx: tx) else { continue }
            customChatColors.append((colorKey, colorValue))
        }
        return customChatColors.sorted(by: { $0.value.creationTimestamp < $1.value.creationTimestamp })
    }

    public func fetchCustomValue(for key: CustomChatColor.Key, tx: DBReadTransaction) -> CustomChatColor? {
        do {
            return try customColorsStore.getCodableValue(forKey: key.rawValue, transaction: tx)
        } catch {
            owsFailDebug("Couldn't decode custom color: \(error)")
            return nil
        }
    }

    public func upsertCustomValue(_ value: CustomChatColor, for key: CustomChatColor.Key, tx: DBWriteTransaction) {
        do {
            try customColorsStore.setCodable(value, key: key.rawValue, transaction: tx)
        } catch {
            owsFailDebug("Couldn't save custom color: \(error)")
        }
        postChatColorsDidChangeNotification(for: nil, tx: tx)
    }

    public func deleteCustomValue(for key: CustomChatColor.Key, tx: DBWriteTransaction) {
        customColorsStore.removeValue(forKey: key.rawValue, transaction: tx)
        postChatColorsDidChangeNotification(for: nil, tx: tx)
    }

    /// Returns the number of conversations that use a given value.
    public func usageCount(of colorKey: CustomChatColor.Key, tx: DBReadTransaction) -> Int {
        var count: Int = 0
        for scopeKey in self.fetchAllScopeKeys(tx: tx) {
            if colorKey.rawValue == self.fetchRawSetting(for: scopeKey, tx: tx) {
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
    public func resolvedChatColor(
        for thread: TSThread?,
        previewWallpaper: Wallpaper? = nil,
        tx: DBReadTransaction
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
    public func autoChatColor(for thread: TSThread?, tx: DBReadTransaction) -> ColorOrGradientSetting {
        return autoChatColor(for: thread, previewWallpaper: nil, tx: tx)
    }

    private func autoChatColor(
        for thread: TSThread?,
        previewWallpaper: Wallpaper?,
        tx: DBReadTransaction
    ) -> ColorOrGradientSetting {
        // If we're editing the color for a specific thread, then we'll prefer the
        // globally-selected value instead of both the thread-specific and global
        // wallpaper values.
        if thread != nil, let globalColor = chatColorSetting(for: nil, tx: tx).constantColor {
            return globalColor
        }
        let resolvedWallpaper = previewWallpaper ?? wallpaperStore.fetchWallpaperForRendering(
            for: thread?.uniqueId,
            tx: tx
        )
        if let wallpaperColor = resolvedWallpaper?.defaultChatColor {
            return wallpaperColor.colorSetting
        }
        return Constants.defaultColor.colorSetting
    }

    public func hasChatColorSetting(for thread: TSThread?, tx: DBReadTransaction) -> Bool {
        let persistenceKey: String = thread?.uniqueId ?? Constants.globalKey
        return self.fetchRawSetting(for: persistenceKey, tx: tx) != nil
    }

    /// The currently-chosen setting for a particular scope.
    ///
    /// This doesn't always contain enough information to render a color on the
    /// screen. For example, a user may choose `.auto`, in which case you need
    /// to run additional logic to determine which color corresponds to `.auto`.
    public func chatColorSetting(for thread: TSThread?, tx: DBReadTransaction) -> ChatColorSetting {
        let persistenceKey: String = thread?.uniqueId ?? Constants.globalKey
        guard let valueId = self.fetchRawSetting(for: persistenceKey, tx: tx) else {
            return .auto
        }
        if let paletteChatColor = PaletteChatColor(rawValue: valueId) {
            return .builtIn(paletteChatColor)
        }
        let customColorKey = CustomChatColor.Key(rawValue: valueId)
        if let customChatColor = fetchCustomValue(for: customColorKey, tx: tx) {
            return .custom(customColorKey, customChatColor)
        }
        // This isn't necessarily an error. A user might apply a custom chat color
        // value to a conversation (or the global default), then delete the custom
        // chat color value. In that case, all references to the value should
        // behave as "auto" (the default).
        return .auto
    }

    public static let chatColorsDidChangeNotification = NSNotification.Name("chatColorsDidChange")

    public func setChatColorSetting(
        _ value: ChatColorSetting,
        for thread: TSThread?,
        tx: DBWriteTransaction
    ) {
        self.setRawSetting({ () -> String? in
            switch value {
            case .auto:
                return nil
            case .builtIn(let paletteChatColor):
                return paletteChatColor.rawValue
            case .custom(let colorKey, _):
                return colorKey.rawValue
            }
        }(), for: thread?.uniqueId ?? Constants.globalKey, tx: tx)
        postChatColorsDidChangeNotification(for: thread, tx: tx)
    }

    private func postChatColorsDidChangeNotification(for thread: TSThread?, tx: DBWriteTransaction) {
        let threadUniqueId = thread?.uniqueId
        tx.addAsyncCompletion(on: DispatchQueue.main) {
            NotificationCenter.default.post(name: Self.chatColorsDidChangeNotification, object: threadUniqueId)
        }
    }
}
