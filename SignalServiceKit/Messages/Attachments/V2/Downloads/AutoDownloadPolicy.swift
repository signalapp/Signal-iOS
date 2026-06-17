//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum AutoDownloadPolicy {
    case never
    case preference(mediaType: MediaBandwidthPreferences.MediaType)
    case always

    public enum AttachmentContext {
        case avatar
        case body
        case link
        case reply
        case sticker
        case text
        case wallpaper
    }

    public enum Constants {
        public static let alwaysLimit = 100 * UInt64.kilobyte
        public static let neverLimit = 200 * UInt64.megabyte
    }

    public static func build(
        context: AttachmentContext,
        mimeType: String,
        renderingFlag: AttachmentReference.RenderingFlag,
        plaintextSize: UInt64,
    ) -> Self {
        let estimatedEncryptedSize = PaddingBucket.forUnpaddedPlaintextSize(plaintextSize)?.encryptedSize ?? .max
        guard estimatedEncryptedSize <= Constants.neverLimit else {
            return .never
        }
        switch context {
        case .avatar:
            return .always
        case .body:
            if MimeTypeUtil.isSupportedImageMimeType(mimeType) {
                return .preference(mediaType: .photo)
            }
            if MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
                return .preference(mediaType: .video)
            }
            if MimeTypeUtil.isSupportedAudioMimeType(mimeType) {
                if renderingFlag == .voiceMessage, estimatedEncryptedSize < Constants.alwaysLimit {
                    return .always
                }
                return .preference(mediaType: .audio)
            }
            return .preference(mediaType: .document)
        case .link:
            return .always
        case .reply:
            return .always
        case .sticker:
            if estimatedEncryptedSize < Constants.alwaysLimit {
                return .always
            }
            return .preference(mediaType: .photo)
        case .text:
            return .always
        case .wallpaper:
            return .always
        }
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
