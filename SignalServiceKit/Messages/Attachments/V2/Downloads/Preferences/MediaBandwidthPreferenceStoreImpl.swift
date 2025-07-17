//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class MediaBandwidthPreferenceStoreImpl: MediaBandwidthPreferenceStore {

    private let kvStore: KeyValueStore
    private let reachabilityManager: SSKReachabilityManager

    public init(
        reachabilityManager: SSKReachabilityManager,
    ) {
        self.kvStore = KeyValueStore(collection: "MediaBandwidthPreferences")
        self.reachabilityManager = reachabilityManager
    }

    public func preference(
        for mediaDownloadType: MediaBandwidthPreferences.MediaType,
        tx: DBReadTransaction
    ) -> MediaBandwidthPreferences.Preference {
        guard let rawValue = kvStore.getUInt(mediaDownloadType.rawValue, transaction: tx) else {
            return mediaDownloadType.defaultPreference
        }
        guard let value = MediaBandwidthPreferences.Preference(rawValue: rawValue) else {
            owsFailDebug("Invalid value: \(rawValue)")
            return mediaDownloadType.defaultPreference
        }
        return value
    }

    public func autoDownloadableMediaTypes(tx: DBReadTransaction) -> Set<MediaBandwidthPreferences.MediaType> {
        let preferenceMap = loadPreferences(tx: tx)
        let hasWifiConnection = reachabilityManager.isReachable(via: .wifi)
        var result = Set<MediaBandwidthPreferences.MediaType>()
        for (mediaDownloadType, preference) in preferenceMap {
            switch preference {
            case .never:
                continue
            case .wifiOnly:
                if hasWifiConnection {
                    result.insert(mediaDownloadType)
                }
            case .wifiAndCellular:
                result.insert(mediaDownloadType)
            }
        }
        return result
    }

    public func downloadableSources() -> Set<QueuedAttachmentDownloadRecord.SourceType> {
        let hasWifiConnection = reachabilityManager.isReachable(via: .wifi)
        var set = Set<QueuedAttachmentDownloadRecord.SourceType>()
        QueuedAttachmentDownloadRecord.SourceType.allCases.forEach {
            switch $0 {
            case .transitTier:
                set.insert($0)
            case .mediaTierFullsize, .mediaTierThumbnail:
                if hasWifiConnection {
                    set.insert($0)
                }
            }
        }
        return set
    }

    public func set(
        _ mediaBandwidthPreference: MediaBandwidthPreferences.Preference,
        for mediaDownloadType: MediaBandwidthPreferences.MediaType,
        tx: DBWriteTransaction
    ) {
        kvStore.setUInt(
            mediaBandwidthPreference.rawValue,
            key: mediaDownloadType.rawValue,
            transaction: tx
        )

        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(
                name: MediaBandwidthPreferences.mediaBandwidthPreferencesDidChange,
                object: nil
            )
        }
    }

    public func resetPreferences(tx: DBWriteTransaction) {
        for mediaDownloadType in MediaBandwidthPreferences.MediaType.allCases {
            kvStore.removeValue(forKey: mediaDownloadType.rawValue, transaction: tx)
        }
        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(
                name: MediaBandwidthPreferences.mediaBandwidthPreferencesDidChange,
                object: nil
            )
        }
    }
}
