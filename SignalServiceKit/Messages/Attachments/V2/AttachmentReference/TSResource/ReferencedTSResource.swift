//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Just a simple structure holding a resource and a reference to it,
/// since that's something we need to do very often.
public class ReferencedTSResource {
    public let reference: TSResourceReference
    public let attachment: TSResource

    public init(reference: TSResourceReference, attachment: TSResource) {
        self.reference = reference
        self.attachment = attachment
    }

    public var asReferencedStream: ReferencedTSResourceStream? {
        guard let resourceStream = attachment.asResourceStream() else {
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
        guard let resourceBackupThumbnail = attachment.asResourceBackupThumbnail() else {
            return nil
        }
        return .init(reference: reference, attachmentBackupThumbnail: resourceBackupThumbnail)
    }

    public func previewText() -> String {
        switch (reference.concreteType, attachment.concreteType) {
        case (.v2(let reference), .v2(let attachment)):
            return ReferencedAttachment(reference: reference, attachment: attachment).previewText()
        case (.legacy(_), .legacy(let attachment)):
            return attachment.previewText()
        case (.v2, .legacy), (.legacy, .v2):
            owsFailDebug("Invalid combination!")
            return ""
        }
    }

    public func previewEmoji() -> String {
        switch (reference.concreteType, attachment.concreteType) {
        case (.v2(let reference), .v2(let attachment)):
            return ReferencedAttachment(reference: reference, attachment: attachment).previewEmoji()
        case (.legacy(_), .legacy(let attachment)):
            return attachment.previewEmoji()
        case (.v2, .legacy), (.legacy, .v2):
            owsFailDebug("Invalid combination!")
            return ""
        }
    }
}

public class ReferencedTSResourceStream: ReferencedTSResource {
    public let attachmentStream: TSResourceStream

    public init(reference: TSResourceReference, attachmentStream: TSResourceStream) {
        self.attachmentStream = attachmentStream
        super.init(reference: reference, attachment: attachmentStream)
    }
}

public class ReferencedTSResourcePointer: ReferencedTSResource {
    public let attachmentPointer: TSResourcePointer

    public init(reference: TSResourceReference, attachmentPointer: TSResourcePointer) {
        self.attachmentPointer = attachmentPointer
        super.init(reference: reference, attachment: attachmentPointer.resource)
    }
}

public class ReferencedTSResourceBackupThumbnail: ReferencedTSResource {
    public let attachmentBackupThumbnail: TSResourceBackupThumbnail

    public init(reference: TSResourceReference, attachmentBackupThumbnail: TSResourceBackupThumbnail) {
        self.attachmentBackupThumbnail = attachmentBackupThumbnail
        super.init(reference: reference, attachment: attachmentBackupThumbnail.resource)
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
        return .init(reference: reference, attachmentPointer: attachmentPointer.asResourcePointer)
    }
}

extension ReferencedAttachmentBackupThumbnail {

    var referencedTSResourceBackupThumbnail: ReferencedTSResourceBackupThumbnail {
        return .init(reference: reference, attachmentBackupThumbnail: attachmentBackupThumbnail)
    }
}
