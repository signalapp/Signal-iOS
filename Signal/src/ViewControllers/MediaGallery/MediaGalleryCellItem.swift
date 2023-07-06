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

    var attachmentStream: TSAttachmentStream? {
        switch self {
        case .photoVideo(let item):
            return item.galleryItem.attachmentStream
        case .audio(let audioItem):
            return audioItem.attachmentStream
        }
    }
}

extension MediaGalleryCellItem: Equatable {
    public static func == (lhs: MediaGalleryCellItem, rhs: MediaGalleryCellItem) -> Bool {
        switch (lhs, rhs) {
        case let (.photoVideo(lvalue), .photoVideo(rvalue)):
            return lvalue === rvalue
        case let (.audio(lvalue), .audio(rvalue)):
            return lvalue.attachmentStream == rvalue.attachmentStream
        case (.photoVideo, _), (.audio, _):
            return false
        }
    }
}

struct MediaGalleryCellItemAudio {
    var message: TSMessage
    var interaction: TSInteraction
    var thread: TSThread
    var attachmentStream: TSAttachmentStream
    var mediaCache: CVMediaCache
    var metadata: MediaMetadata

    var size: UInt {
        UInt(attachmentStream.byteCount)
    }
    var date: Date {
        attachmentStream.creationTimestamp
    }
    var duration: TimeInterval {
        attachmentStream.audioDurationSeconds()
    }

    enum AttachmentType {
        case file
        case voiceMessage
    }
    var attachmentType: AttachmentType {
        let isVoiceMessage = attachmentStream.isVoiceMessageIncludingLegacyMessages
        return isVoiceMessage ? .voiceMessage : .file
    }

    var localizedString: String {
        switch attachmentType {
        case .file:
            return "Audio file"  // ATTACHMENT_TYPE_AUDIO
        case .voiceMessage:
            return "Voice message"  // ATTACHMENT_TYPE_VOICE_MESSAGE
        }
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

    func asyncThumbnail(completion: @escaping (UIImage?) -> Void) -> UIImage? {
        return galleryItem.thumbnailImage(async: completion)
    }

    private var videoDurationPromise: Promise<TimeInterval> {
        owsAssert(galleryItem.isVideo)
        return VideoDurationHelper.shared.promisedDuration(attachment: galleryItem.attachmentStream)
    }
    var mediaMetadata: MediaMetadata? {
        return galleryItem.mediaMetadata
    }
}

extension MediaGalleryItem {
    var mediaMetadata: MediaMetadata? {
        let filename = attachmentStream.originalFilePath.map {
            ($0 as NSString).lastPathComponent as String
        }
        return MediaMetadata(
            sender: sender?.name ?? "",
            abbreviatedSender: sender?.abbreviatedName ?? "",
            filename: filename,
            byteSize: Int(attachmentStream.byteCount),
            creationDate: attachmentStream.creationTimestamp)
    }
}
