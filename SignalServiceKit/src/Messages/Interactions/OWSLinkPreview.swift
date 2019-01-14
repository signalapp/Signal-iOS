//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSLinkPreview)
public class OWSLinkPreview: MTLModel {
    @objc
    public var urlString: String?

    @objc
    public var title: String?

    @objc
    public var attachmentId: String?

    @objc
    public init(urlString: String, title: String?, attachmentId: String?) {
        self.urlString = urlString
        self.title = title
        self.attachmentId = attachmentId

        super.init()
    }

    @objc
    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc
    public required init(dictionary dictionaryValue: [AnyHashable: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    @objc
    public required init?(dataMessage: SSKProtoDataMessage,
                          body: String?,
                          transaction: YapDatabaseReadWriteTransaction) {
        guard let previewProto = dataMessage.preview else {
            return nil
        }
        let urlString = previewProto.url

        guard URL(string: urlString) != nil else {
            owsFailDebug("Could not parse preview URL.")
            return nil
        }

        guard let body = body else {
            owsFailDebug("Preview for message without body.")
            return nil
        }
        let bodyComponents = body.components(separatedBy: .whitespacesAndNewlines)
        guard bodyComponents.contains(urlString) else {
            owsFailDebug("URL not present in body.")
            return nil
        }

        // TODO: Verify that url host is in whitelist.

        let title: String? = previewProto.title?.trimmingCharacters(in: .whitespacesAndNewlines)

        var imageAttachmentId: String?
        if let imageProto = previewProto.image {
            if let imageAttachmentPointer = TSAttachmentPointer(fromProto: imageProto, albumMessage: nil) {
                imageAttachmentPointer.save(with: transaction)
                imageAttachmentId = imageAttachmentPointer.uniqueId
            } else {
                owsFailDebug("Could not parse image proto.")
            }
        }

        var hasTitle = false
        if let titleValue = title {
            hasTitle = titleValue.count > 0
        }
        let hasImage = imageAttachmentId != nil
        if !hasTitle && !hasImage {
            owsFailDebug("Preview has neither title nor image.")
            return nil
        }

        self.urlString = urlString
        self.title = title
        self.attachmentId = imageAttachmentId

        super.init()
    }

    @objc
    public func removeAttachment(transaction: YapDatabaseReadWriteTransaction) {
        guard let attachmentId = attachmentId else {
            owsFailDebug("No attachment id.")
            return
        }
        guard let attachment = TSAttachment.fetch(uniqueId: attachmentId, transaction: transaction) else {
            owsFailDebug("Could not load attachment.")
            return
        }
        attachment.remove(with: transaction)
    }
}
