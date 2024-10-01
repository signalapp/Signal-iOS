//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum MediaBandwidthPreferences {

    public static let mediaBandwidthPreferencesDidChange = Notification.Name("MediaBandwidthPreferencesDidChange")

    public enum Preference: UInt, Equatable, CaseIterable {
        case never
        case wifiOnly
        case wifiAndCellular

        public var sortKey: UInt {
            switch self {
            case .never:
                return 1
            case .wifiOnly:
                return 2
            case .wifiAndCellular:
                return 3
            }
        }
    }

    public enum MediaType: String, Equatable, CaseIterable {
        case photo
        case video
        case audio
        case document

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

        public var sortKey: UInt {
            switch self {
            case .photo:
                return 1
            case .video:
                return 2
            case .audio:
                return 3
            case .document:
                return 4
            }
        }
    }
}

public protocol MediaBandwidthPreferenceStore {

    func preference(
        for mediaDownloadType: MediaBandwidthPreferences.MediaType,
        tx: DBReadTransaction
    ) -> MediaBandwidthPreferences.Preference

    func autoDownloadableMediaTypes(tx: DBReadTransaction) -> Set<MediaBandwidthPreferences.MediaType>

    /// Which sources (e.g. transit, media tier) are capable of being downloaded given the current network
    /// state. (At time of writing, there is no user-level setting for this, but that could change.)
    func downloadableSources() -> Set<QueuedAttachmentDownloadRecord.SourceType>

    func set(
        _ mediaBandwidthPreference: MediaBandwidthPreferences.Preference,
        for mediaDownloadType: MediaBandwidthPreferences.MediaType,
        tx: DBWriteTransaction
    )

    func resetPreferences(tx: DBWriteTransaction)
}

extension MediaBandwidthPreferenceStore {

    public func loadPreferences(
        tx: DBReadTransaction
    ) -> [MediaBandwidthPreferences.MediaType: MediaBandwidthPreferences.Preference] {
        var result = [MediaBandwidthPreferences.MediaType: MediaBandwidthPreferences.Preference]()
        for mediaDownloadType in MediaBandwidthPreferences.MediaType.allCases {
            result[mediaDownloadType] = preference(
                for: mediaDownloadType,
                tx: tx
            )
        }
        return result
    }
}
