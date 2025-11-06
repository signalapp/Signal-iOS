//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents the image quality setting for a specific conversation.
/// This is a simple toggle: use the system default quality, or send originals with metadata.
public enum ImageQualitySetting: String, Codable {
    case `default` // Use system default quality
    case original // Send original quality with metadata

    /// Returns the corresponding ImageQualityLevel for this setting.
    /// For `.default`, returns nil and caller should use system default.
    public func qualityLevel() -> ImageQualityLevel? {
        switch self {
        case .default:
            return nil
        case .original:
            return .original
        }
    }
}

/// Stores the `ImageQualitySetting` for each thread.
///
/// The keys in this store are thread unique ids. The values are `ImageQualitySetting` raw values.
public class ImageQualitySettingStore {
    private let settingStore: KeyValueStore

    public init() {
        self.settingStore = KeyValueStore(collection: "imageQualitySettingStore")
    }

    // MARK: - Fetch Settings

    /// Fetch the image quality setting for a specific thread.
    /// Returns `.default` if no setting has been explicitly set.
    public func fetchSetting(for thread: TSThread, tx: DBReadTransaction) -> ImageQualitySetting {
        guard let rawValue = settingStore.getString(thread.uniqueId, transaction: tx) else {
            return .default
        }
        return ImageQualitySetting(rawValue: rawValue) ?? .default
    }

    /// Fetch the resolved quality level for a thread, taking into account
    /// the thread setting and system defaults.
    public func resolvedQualityLevel(for thread: TSThread, tx: DBReadTransaction) -> ImageQualityLevel {
        let threadSetting = fetchSetting(for: thread, tx: tx)

        // If thread has an explicit setting, use it
        if let qualityLevel = threadSetting.qualityLevel() {
            return qualityLevel
        }

        // Fall back to system default quality
        return ImageQualityLevel.resolvedQuality(tx: tx)
    }

    // MARK: - Set Settings

    /// Set the image quality setting for a specific thread.
    /// Pass `.default` to clear the thread-specific setting.
    public func setSetting(
        _ setting: ImageQualitySetting,
        for thread: TSThread,
        tx: DBWriteTransaction
    ) {
        if setting == .default {
            settingStore.removeValue(forKey: thread.uniqueId, transaction: tx)
        } else {
            settingStore.setString(setting.rawValue, key: thread.uniqueId, transaction: tx)
        }

        postSettingDidChangeNotification(for: thread, tx: tx)
    }

    // MARK: - Notifications

    public static let imageQualitySettingDidChangeNotification = NSNotification.Name("imageQualitySettingDidChange")

    private func postSettingDidChangeNotification(for thread: TSThread?, tx: DBWriteTransaction) {
        let threadUniqueId = thread?.uniqueId
        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(
                name: Self.imageQualitySettingDidChangeNotification,
                object: threadUniqueId
            )
        }
    }

    // MARK: - Utility

    /// Returns all thread IDs that have an explicit image quality setting.
    public func fetchAllThreadsWithSettings(tx: DBReadTransaction) -> [String] {
        return settingStore.allKeys(transaction: tx)
    }

    /// Reset all settings (useful for testing or troubleshooting).
    public func resetAllSettings(tx: DBWriteTransaction) {
        settingStore.removeAll(transaction: tx)
        postSettingDidChangeNotification(for: nil, tx: tx)
    }
}

