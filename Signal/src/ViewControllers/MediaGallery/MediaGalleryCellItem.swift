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

    var attachmentStream: ReferencedAttachmentStream? {
        switch self {
        case .photoVideo(let item):
            return item.galleryItem.attachmentStream
        case .audio(let audioItem):
            return audioItem.attachmentStream
        case .otherFile(let fileItem):
            return fileItem.attachmentStream
        }
    }
}

extension MediaGalleryCellItem: Equatable {
    public static func == (lhs: MediaGalleryCellItem, rhs: MediaGalleryCellItem) -> Bool {
        switch (lhs, rhs) {
        case let (.photoVideo(lvalue), .photoVideo(rvalue)):
            return lvalue === rvalue
        case let (.audio(lvalue), .audio(rvalue)):
            return lvalue.attachmentStream.reference.attachmentRowId == rvalue.attachmentStream.reference.attachmentRowId
        case let (.otherFile(lvalue), .otherFile(rvalue)):
            return lvalue.attachmentStream.reference.attachmentRowId == rvalue.attachmentStream.reference.attachmentRowId
        case (.photoVideo, _), (.audio, _), (.otherFile, _):
            return false
        }
    }
}

struct MediaGalleryCellItemAudio {
    var message: TSMessage
    var interaction: TSInteraction
    var thread: TSThread
    var attachmentStream: ReferencedAttachmentStream
    var receivedAtDate: Date
    var isVoiceMessage: Bool
    var mediaCache: CVMediaCache
    var metadata: MediaMetadata

    var size: UInt {
        UInt(attachmentStream.attachmentStream.unencryptedByteCount)
    }
    var duration: TimeInterval {
        switch attachmentStream.attachmentStream.contentType {
        case .audio(let duration, _):
            return duration
        default:
            return 0
        }
    }

    var localizedString: String {
        if isVoiceMessage {
            return OWSLocalizedString("MEDIA_GALLERY_A11Y_VOICE_MESSAGE",
                                      comment: "VoiceOver description for a voice messages in All Media")
        } else {
            return OWSLocalizedString("MEDIA_GALLERY_A11Y_AUDIO_FILE",
                                      comment: "VoiceOver description for a generic audio file in All Media")

        }
    }
}

struct MediaGalleryCellItemOtherFile {
    var message: TSMessage
    var interaction: TSInteraction
    var thread: TSThread
    var attachmentStream: ReferencedAttachmentStream
    var receivedAtDate: Date
    var mediaCache: CVMediaCache
    var metadata: MediaMetadata

    var size: UInt {
        UInt(attachmentStream.attachmentStream.unencryptedByteCount)
    }

    var localizedString: String {
        return OWSLocalizedString(
            "MEDIA_GALLERY_A11Y_OTHER_FILE",
            comment: "VoiceOver description for a generic non-audiovisual file in All Media"
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
            return .video(videoDurationPromise)
        } else if galleryItem.isAnimated {
            return .animated
        } else {
            return .photo
        }
    }

    var isFavorite: Bool { false }

    func asyncThumbnail(completion: @escaping (UIImage?) -> Void) {
        galleryItem.thumbnailImage(completion: completion)
    }

    private var videoDurationPromise: Promise<TimeInterval> {
        owsPrecondition(galleryItem.isVideo)
        let attachment = galleryItem.attachmentStream.attachmentStream
        switch attachment.contentType {
        case .file, .invalid, .image, .animatedImage, .audio:
            owsFailDebug("Non video type!")
            return .value(0)
        case .video(let duration, _, _):
            return .value(duration)
        }
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
            byteSize: Int(attachmentStream.attachmentStream.unencryptedByteCount),
            creationDate: receivedAtDate
        )
    }
}
