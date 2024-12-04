//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class StoryThumbnailView: UIView {
    enum Attachment: Equatable {
        case file(ReferencedAttachment)
        case text(PreloadedTextAttachment)
        case missing

        static func from(_ storyMessage: StoryMessage, transaction: SDSAnyReadTransaction) -> Self {
            switch storyMessage.attachment {
            case .media:
                guard
                    let attachment = storyMessage.fileAttachment(tx: transaction)
                else {
                    owsFailDebug("Unexpectedly missing attachment for story")
                    return .missing
                }
                return .file(attachment)
            case .text(let attachment):
                return .text(.from(attachment, storyMessage: storyMessage, tx: transaction))
            }
        }

        static func == (lhs: StoryThumbnailView.Attachment, rhs: StoryThumbnailView.Attachment) -> Bool {
            switch (lhs, rhs) {
            case (.file(let lhsAttachment), .file(let rhsAttachment)):
                return lhsAttachment.attachment.id == rhsAttachment.attachment.id
                    && lhsAttachment.reference.hasSameOwner(as: rhsAttachment.reference)
            case (.text(let lhsTextAttachment), .text(let rhsTextAttachment)):
                return lhsTextAttachment == rhsTextAttachment
            case (.missing, .missing):
                return true
            case (.file, _), (.text, _), (.missing, _):
                return false
            }
        }
    }

    init(attachment: Attachment, interactionIdentifier: InteractionSnapshotIdentifier, spoilerState: SpoilerRenderState) {
        super.init(frame: .zero)

        layer.cornerRadius = 12
        clipsToBounds = true

        switch attachment {
        case .file(let attachment):
            if let stream = attachment.attachment.asStream() {
                let imageView = buildThumbnailImageView(stream: stream)
                addSubview(imageView)
                imageView.autoPinEdgesToSuperviewEdges()
            } else if let pointer = attachment.attachment.asTransitTierPointer() {
                let pointerView = UIView()

                if let blurHashImageView = buildBlurHashImageViewIfAvailable(pointer: pointer) {
                    pointerView.addSubview(blurHashImageView)
                    blurHashImageView.autoPinEdgesToSuperviewEdges()
                }

                addSubview(pointerView)
                pointerView.autoPinEdgesToSuperviewEdges()
            } else {
                owsFailDebug("Unexpected attachment type \(type(of: attachment))")
            }
        case .text(let attachment):
            let textThumbnailView = TextAttachmentView(
                attachment: attachment,
                interactionIdentifier: interactionIdentifier,
                spoilerState: spoilerState
            ).asThumbnailView()
            addSubview(textThumbnailView)
            textThumbnailView.autoPinEdgesToSuperviewEdges()
        case .missing:
            // TODO: error state
            break
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildThumbnailImageView(stream: AttachmentStream) -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.layer.allowsEdgeAntialiasing = true

        applyThumbnailImage(to: imageView, for: stream)

        return imageView
    }

    private static let thumbnailCache = LRUCache<SignalServiceKit.Attachment.IDType, UIImage>(maxSize: 64, shouldEvacuateInBackground: true)
    private func applyThumbnailImage(to imageView: UIImageView, for stream: AttachmentStream) {
        if let thumbnailImage = Self.thumbnailCache[stream.id] {
            imageView.image = thumbnailImage
        } else {
            Task {
                guard let thumbnailImage = await stream.thumbnailImage(quality: .small) else {
                    owsFailDebug("Failed to generate thumbnail")
                    return
                }
                imageView.image = thumbnailImage
                Self.thumbnailCache.setObject(thumbnailImage, forKey: stream.id)
            }
        }
    }

    private func buildBlurHashImageViewIfAvailable(pointer: AttachmentTransitPointer) -> UIView? {
        guard let blurHash = pointer.attachment.blurHash, let blurHashImage = BlurHash.image(for: blurHash) else {
            return nil
        }
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        imageView.layer.allowsEdgeAntialiasing = true
        imageView.image = blurHashImage
        return imageView
    }
}
