//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum MediaBandwidthPreferences {

    public static let mediaBandwidthPreferencesDidChange = Notification.Name("MediaBandwidthPreferencesDidChange")

    /// Order matters (CaseIterable shows these in the UI)
    /// Values matter (they are persisted to the database)
    public enum Preference: UInt, CaseIterable {
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

public protocol MediaBandwidthPreferenceStore {

    func preference(
        for mediaDownloadType: MediaBandwidthPreferences.MediaType,
        tx: DBReadTransaction,
    ) -> MediaBandwidthPreferences.Preference

    func autoDownloadableMediaTypes(tx: DBReadTransaction) -> Set<MediaBandwidthPreferences.MediaType>

    func set(
        _ mediaBandwidthPreference: MediaBandwidthPreferences.Preference,
        for mediaDownloadType: MediaBandwidthPreferences.MediaType,
        tx: DBWriteTransaction,
    )

    func resetPreferences(tx: DBWriteTransaction)
}

extension MediaBandwidthPreferenceStore {

    public func loadPreferences(
        tx: DBReadTransaction,
    ) -> [MediaBandwidthPreferences.MediaType: MediaBandwidthPreferences.Preference] {
        var result = [MediaBandwidthPreferences.MediaType: MediaBandwidthPreferences.Preference]()
        for mediaDownloadType in MediaBandwidthPreferences.MediaType.allCases {
            result[mediaDownloadType] = preference(
                for: mediaDownloadType,
                tx: tx,
            )
        }
        return result
    }
}
