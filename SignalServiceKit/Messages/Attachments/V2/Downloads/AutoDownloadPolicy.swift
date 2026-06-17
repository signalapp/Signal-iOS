//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum AutoDownloadPolicy {
    case always
    case preference(mediaType: MediaBandwidthPreferences.MediaType)

    public static func forMimeType(_ mimeType: String, renderingFlag: AttachmentReference.RenderingFlag) -> Self {
        if MimeTypeUtil.isSupportedImageMimeType(mimeType) {
            return .preference(mediaType: .photo)
        }
        if MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
            return .preference(mediaType: .video)
        }
        if MimeTypeUtil.isSupportedAudioMimeType(mimeType) {
            if renderingFlag == .voiceMessage {
                return .always
            }
            return .preference(mediaType: .audio)
        }
        return .preference(mediaType: .document)
    }

    public static func canAutoDownload(
        mediaType: MediaBandwidthPreferences.MediaType,
        preferenceStore: MediaBandwidthPreferenceStore,
        isReachableViaWiFi: () -> Bool,
        tx: DBReadTransaction,
    ) -> Bool {
        let preference = preferenceStore.preference(for: mediaType, tx: tx)
        switch preference {
        case .never:
            return false
        case .wifiOnly:
            return isReachableViaWiFi()
        case .wifiAndCellular:
            return true
        }
    }
}
