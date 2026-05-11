//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol MediaGalleryCollectionViewCell: UICollectionViewCell {
    var item: MediaGalleryCellItem? { get }
    var allowsMultipleSelection: Bool { get }
    func setAllowsMultipleSelection(_ allowed: Bool, animated: Bool)

    func makePlaceholder()
    func configure(item: MediaGalleryCellItem, spoilerState: SpoilerRenderState)
    func mediaPresentationContext(collectionView: UICollectionView, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext?
    func indexPathDidChange(_ indexPath: IndexPath, itemCount: Int)
}

enum MediaGalleryCellItem {
    case photoVideo(MediaGalleryCellItemPhotoVideo)
    case audio(MediaGalleryCellItemAudio)
    case otherFile(MediaGalleryCellItemOtherFile)

    var referencedAttachment: ReferencedAttachment? {
        switch self {
        case .photoVideo(let item):
            return item.galleryItem.referencedAttachment
        case .audio(let audioItem):
            return audioItem.referencedAttachment
        case .otherFile(let fileItem):
            return fileItem.referencedAttachment
        }
    }
}

extension MediaGalleryCellItem: Equatable {
    static func ==(lhs: MediaGalleryCellItem, rhs: MediaGalleryCellItem) -> Bool {
        switch (lhs, rhs) {
        case let (.photoVideo(lvalue), .photoVideo(rvalue)):
            return lvalue === rvalue
        case let (.audio(lvalue), .audio(rvalue)):
            return lvalue.referencedAttachment.reference.attachmentRowId == rvalue.referencedAttachment.reference.attachmentRowId
        case let (.otherFile(lvalue), .otherFile(rvalue)):
            return lvalue.referencedAttachment.reference.attachmentRowId == rvalue.referencedAttachment.reference.attachmentRowId
        case (.photoVideo, _), (.audio, _), (.otherFile, _):
            return false
        }
    }
}

struct MediaGalleryCellItemAudio {
    var message: TSMessage
    var interaction: TSInteraction
    var thread: TSThread
    var referencedAttachment: ReferencedAttachment
    var receivedAtDate: Date
    var isVoiceMessage: Bool
    var mediaCache: CVMediaCache
    var metadata: MediaMetadata

    var localizedString: String {
        if isVoiceMessage {
            return OWSLocalizedString(
                "MEDIA_GALLERY_A11Y_VOICE_MESSAGE",
                comment: "VoiceOver description for a voice messages in All Media",
            )
        } else {
            return OWSLocalizedString(
                "MEDIA_GALLERY_A11Y_AUDIO_FILE",
                comment: "VoiceOver description for a generic audio file in All Media",
            )
        }
    }
}

struct MediaGalleryCellItemOtherFile {
    var message: TSMessage
    var interaction: TSInteraction
    var thread: TSThread
    var referencedAttachment: ReferencedAttachment
    var receivedAtDate: Date
    var mediaCache: CVMediaCache
    var metadata: MediaMetadata

    var size: UInt64 {
        referencedAttachment.unencryptedByteCount() ?? 0
    }

    var localizedString: String {
        return OWSLocalizedString(
            "MEDIA_GALLERY_A11Y_OTHER_FILE",
            comment: "VoiceOver description for a generic non-audiovisual file in All Media",
        )
    }
}

class MediaGalleryCellItemPhotoVideo: PhotoGridItem {
    let galleryItem: MediaGalleryItem

    init(galleryItem: MediaGalleryItem) {
        self.galleryItem = galleryItem
    }

    var type: PhotoGridItemType {
        if galleryItem.isVideo {
            return .video(
                duration: galleryItem.referencedAttachment.asReferencedStream?.attachmentStream.cachedVideoDuration,
            )
        } else if galleryItem.isAnimated {
            return .animated
        } else {
            return .photo
        }
    }

    func asyncThumbnail(completion: @escaping (UIImage?) -> Void) {
        galleryItem.thumbnailImage(completion: completion)
    }

    var mediaMetadata: MediaMetadata? {
        return galleryItem.mediaMetadata
    }
}

extension MediaGalleryItem {
    var mediaMetadata: MediaMetadata? {
        return MediaMetadata(
            sender: sender?.name ?? "",
            abbreviatedSender: sender?.abbreviatedName ?? "",
            byteSize: Int(clamping: referencedAttachment.unencryptedByteCount() ?? 0),
            creationDate: receivedAtDate,
        )
    }
}
