//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class MediaBandwidthPreferenceStoreMock: MediaBandwidthPreferenceStore {

    public init() {}

    public var store = [MediaBandwidthPreferences.MediaType: MediaBandwidthPreferences.Preference]()

    open func preference(
        for mediaDownloadType: MediaBandwidthPreferences.MediaType,
        tx: DBReadTransaction
    ) -> MediaBandwidthPreferences.Preference {
        return store[mediaDownloadType] ?? .wifiAndCellular
    }

    open func autoDownloadableMediaTypes(
        tx: DBReadTransaction
    ) -> Set<MediaBandwidthPreferences.MediaType> {
        return Set()
    }

    open func set(
        _ mediaBandwidthPreference: MediaBandwidthPreferences.Preference,
        for mediaDownloadType: MediaBandwidthPreferences.MediaType,
        tx: DBWriteTransaction
    ) {
        store[mediaDownloadType] = mediaBandwidthPreference
    }

    open func resetPreferences(tx: DBWriteTransaction) {
        store = [:]
    }
}

#endif
