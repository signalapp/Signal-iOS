//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Just a simple structure holding a resource and a reference to it,
/// since that's something we need to do very often.
public class ReferencedTSResource {
    public let reference: TSResourceReference
    public let attachment: Attachment

    public init(reference: TSResourceReference, attachment: Attachment) {
        self.reference = reference
        self.attachment = attachment
    }

    public var asReferencedStream: ReferencedTSResourceStream? {
        guard let resourceStream = attachment.asStream() else {
            return nil
        }
        return .init(reference: reference, attachmentStream: resourceStream)
    }

    public var asReferencedPointer: ReferencedTSResourcePointer? {
        guard let resourcePointer = attachment.asTransitTierPointer() else {
            return nil
        }
        return .init(reference: reference, attachmentPointer: resourcePointer)
    }

    public var asReferencedBackupThumbnail: ReferencedTSResourceBackupThumbnail? {
        guard let resourceBackupThumbnail = attachment.asBackupThumbnail() else {
            return nil
        }
        return .init(reference: reference, attachmentBackupThumbnail: resourceBackupThumbnail)
    }

    public func previewText() -> String {
        let reference = reference.concreteType
        return ReferencedAttachment(reference: reference, attachment: attachment).previewText()
    }

    public func previewEmoji() -> String {
        let (reference, attachment) = (reference.concreteType, attachment)
        return ReferencedAttachment(reference: reference, attachment: attachment).previewEmoji()
    }
}

public class ReferencedTSResourceStream: ReferencedTSResource {
    public let attachmentStream: AttachmentStream

    public init(reference: TSResourceReference, attachmentStream: AttachmentStream) {
        self.attachmentStream = attachmentStream
        super.init(reference: reference, attachment: attachmentStream.attachment)
    }
}

public class ReferencedTSResourcePointer: ReferencedTSResource {
    public let attachmentPointer: AttachmentTransitPointer

    public init(reference: TSResourceReference, attachmentPointer: AttachmentTransitPointer) {
        self.attachmentPointer = attachmentPointer
        super.init(reference: reference, attachment: attachmentPointer.attachment)
    }
}

public class ReferencedTSResourceBackupThumbnail: ReferencedTSResource {
    public let attachmentBackupThumbnail: AttachmentBackupThumbnail

    public init(reference: TSResourceReference, attachmentBackupThumbnail: AttachmentBackupThumbnail) {
        self.attachmentBackupThumbnail = attachmentBackupThumbnail
        super.init(reference: reference, attachment: attachmentBackupThumbnail.attachment)
    }
}

extension ReferencedAttachment {

    var referencedTSResource: ReferencedTSResource {
        return .init(reference: reference, attachment: attachment)
    }
}

extension ReferencedAttachmentStream {

    var referencedTSResourceStream: ReferencedTSResourceStream {
        return .init(reference: reference, attachmentStream: attachmentStream)
    }
}

extension ReferencedAttachmentTransitPointer {

    var referencedTSResourcePointer: ReferencedTSResourcePointer {
        return .init(reference: reference, attachmentPointer: attachmentPointer)
    }
}

extension ReferencedAttachmentBackupThumbnail {

    var referencedTSResourceBackupThumbnail: ReferencedTSResourceBackupThumbnail {
        return .init(reference: reference, attachmentBackupThumbnail: attachmentBackupThumbnail)
    }
}
