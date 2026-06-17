//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum MediaBandwidthPreferences {

    public static let mediaBandwidthPreferencesDidChange = Notification.Name("MediaBandwidthPreferencesDidChange")

    /// Order matters (CaseIterable shows these in the UI)
    /// Values matter (they are persisted to the database)
    public enum Preference: Int64, CaseIterable {
        case never = 0
        case wifiOnly = 1
        case wifiAndCellular = 2
    }

    /// Order matters (CaseIterable shows these in the UI)
    /// Values matter (they are persisted to the database)
    public enum MediaType: String, CaseIterable {
        case photo = "photo"
        case video = "video"
        case audio = "audio"
        case document = "document"

        public var defaultPreference: Preference {
            switch self {
            case .photo:
                return .wifiAndCellular
            case .video:
                return .wifiOnly
            case .audio:
                return .wifiAndCellular
            case .document:
                return .wifiOnly
            }
        }
    }
}

public struct MediaBandwidthPreferenceStore {

    private let kvStore: NewKeyValueStore

    public init() {
        self.kvStore = NewKeyValueStore(collection: "MediaBandwidthPreferences")
    }

    public func preference(
        for mediaDownloadType: MediaBandwidthPreferences.MediaType,
        tx: DBReadTransaction,
    ) -> MediaBandwidthPreferences.Preference {
        guard let rawValue = kvStore.fetchValue(Int64.self, forKey: mediaDownloadType.rawValue, tx: tx) else {
            return mediaDownloadType.defaultPreference
        }
        guard let value = MediaBandwidthPreferences.Preference(rawValue: rawValue) else {
            owsFailDebug("Invalid value: \(rawValue)")
            return mediaDownloadType.defaultPreference
        }
        return value
    }

    public func set(
        _ mediaBandwidthPreference: MediaBandwidthPreferences.Preference,
        for mediaDownloadType: MediaBandwidthPreferences.MediaType,
        tx: DBWriteTransaction,
    ) {
        kvStore.writeValue(
            mediaBandwidthPreference.rawValue,
            forKey: mediaDownloadType.rawValue,
            tx: tx,
        )

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(
                name: MediaBandwidthPreferences.mediaBandwidthPreferencesDidChange,
                object: nil,
            )
        }
    }

    public func resetPreferences(tx: DBWriteTransaction) {
        for mediaDownloadType in MediaBandwidthPreferences.MediaType.allCases {
            kvStore.removeValue(forKey: mediaDownloadType.rawValue, tx: tx)
        }
        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(
                name: MediaBandwidthPreferences.mediaBandwidthPreferencesDidChange,
                object: nil,
            )
        }
    }
}
