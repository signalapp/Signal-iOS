//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum LinkPreviewError: Int, Error {
    /// A preview could not be generated from available input
    case noPreview
    /// A preview should have been generated, but something unexpected caused it to fail
    case invalidPreview
    /// A preview could not be generated due to an issue fetching a network resource
    case fetchFailure
    /// A preview could not be generated because the feature is disabled
    case featureDisabled
}

// MARK: - OWSLinkPreviewDraft

// This contains the info for a link preview "draft".
public class OWSLinkPreviewDraft: NSObject {

    public var url: URL
    public var urlString: String {
        return url.absoluteString
    }
    public var title: String?
    public var imageData: Data?
    public var imageMimeType: String?
    public var previewDescription: String?
    public var date: Date?

    public init(url: URL, title: String?, imageData: Data? = nil, imageMimeType: String? = nil) {
        self.url = url
        self.title = title
        self.imageData = imageData
        self.imageMimeType = imageMimeType
    }

    public var displayDomain: String? {
        return URL(string: urlString).flatMap(LinkPreviewHelper.displayDomain(forUrl:))
    }
}

// MARK: - OWSLinkPreview

@objc
public class OWSLinkPreview: MTLModel, Codable {

    @objc
    public var urlString: String?

    @objc
    public var title: String?

    // For Legacy image attachments only.
    @objc
    private var imageAttachmentId: String?

    @objc
    private var usesV2AttachmentReferenceValue: NSNumber?

    @objc
    public var previewDescription: String?

    @objc
    public var date: Date?

    public convenience init(urlString: String, title: String?, legacyImageAttachmentId: String?) {
        self.init(urlString: urlString, title: title, attachmentRef: .legacy(uniqueId: legacyImageAttachmentId))
    }

    internal init(urlString: String, title: String?, attachmentRef: AttachmentReference) {
        self.urlString = urlString
        self.title = title
        switch attachmentRef {
        case .legacy(let uniqueId):
            self.imageAttachmentId = uniqueId
            self.usesV2AttachmentReferenceValue = NSNumber(value: false)
        case .v2:
            self.imageAttachmentId = nil
            self.usesV2AttachmentReferenceValue = NSNumber(value: true)
        }

        super.init()
    }

    public override init() {
        super.init()
    }

    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    public var legacyImageAttachmentId: String? {
        return imageAttachmentId
    }

    internal var usesV2AttachmentReference: Bool {
        return usesV2AttachmentReferenceValue?.boolValue ?? false
    }

    @objc
    public class func isNoPreviewError(_ error: Error) -> Bool {
        guard let error = error as? LinkPreviewError else {
            return false
        }
        return error == .noPreview
    }

    public class func buildValidatedUnownedLinkPreview(
        fromInfo info: OWSLinkPreviewDraft,
        transaction: SDSAnyWriteTransaction
    ) throws -> (OWSLinkPreview, attachmentUniqueId: String?) {
        var attachmentUniqueId: String?
        let preview = try _buildValidatedLinkPreview(
            fromInfo: info,
            attachmentRefBuilder: { innerTx in
                let uniqueId = OWSLinkPreview.saveUnownedAttachmentIfPossible(
                    imageData: info.imageData,
                    imageMimeType: info.imageMimeType,
                    tx: innerTx
                )
                attachmentUniqueId = uniqueId
                return .legacy(uniqueId: uniqueId)
            },
            transaction: transaction
        )
        return (preview, attachmentUniqueId: attachmentUniqueId)
    }

    public class func buildValidatedLinkPreview(
        fromInfo info: OWSLinkPreviewDraft,
        messageRowId: Int64,
        transaction: SDSAnyWriteTransaction
    ) throws -> OWSLinkPreview {
        return try _buildValidatedLinkPreview(
            fromInfo: info,
            attachmentRefBuilder: { innerTx in
                return OWSLinkPreview.saveAttachmentIfPossible(
                    imageData: info.imageData,
                    imageMimeType: info.imageMimeType,
                    messageRowId: messageRowId,
                    tx: innerTx
                )
            },
            transaction: transaction
        )
    }

    public class func buildValidatedLinkPreview(
        fromInfo info: OWSLinkPreviewDraft,
        storyMessageRowId: Int64,
        transaction: SDSAnyWriteTransaction
    ) throws -> OWSLinkPreview {
        return try _buildValidatedLinkPreview(
            fromInfo: info,
            attachmentRefBuilder: { innerTx in
                return OWSLinkPreview.saveAttachmentIfPossible(
                    imageData: info.imageData,
                    imageMimeType: info.imageMimeType,
                    storyMessageRowId: storyMessageRowId,
                    tx: innerTx
                )
            },
            transaction: transaction
        )
    }

    private class func _buildValidatedLinkPreview(
        fromInfo info: OWSLinkPreviewDraft,
        attachmentRefBuilder: (SDSAnyWriteTransaction) -> AttachmentReference,
        transaction: SDSAnyWriteTransaction
    ) throws -> OWSLinkPreview {
        guard SSKPreferences.areLinkPreviewsEnabled(transaction: transaction) else {
            throw LinkPreviewError.featureDisabled
        }
        let attachmentRef = attachmentRefBuilder(transaction)

        let linkPreview = OWSLinkPreview(urlString: info.urlString, title: info.title, attachmentRef: attachmentRef)
        linkPreview.previewDescription = info.previewDescription
        linkPreview.date = info.date
        return linkPreview
    }

    public func buildProto(transaction: SDSAnyReadTransaction) throws -> SSKProtoPreview {
        guard let urlString = urlString else {
            Logger.error("Preview does not have url.")
            throw LinkPreviewError.invalidPreview
        }

        let builder = SSKProtoPreview.builder(url: urlString)

        if let title = title {
            builder.setTitle(title)
        }

        if let previewDescription = previewDescription {
            builder.setPreviewDescription(previewDescription)
        }

        if let attachmentProto = buildProtoAttachmentPointer(tx: transaction) {
            builder.setImage(attachmentProto)
        }

        if let date = date {
            builder.setDate(date.ows_millisecondsSince1970)
        }

        return try builder.build()
    }

    public var displayDomain: String? {
        urlString.flatMap(URL.init(string: )).flatMap(LinkPreviewHelper.displayDomain(forUrl:))
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case urlString
        case title
        case usesV2AttachmentReferenceValue
        case imageAttachmentId
        case previewDescription
        case date
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        let usesV2AttachmentReferenceValue = try container.decodeIfPresent(Int.self, forKey: .usesV2AttachmentReferenceValue)
        self.usesV2AttachmentReferenceValue = usesV2AttachmentReferenceValue.map(NSNumber.init(integerLiteral:))
        imageAttachmentId = try container.decodeIfPresent(String.self, forKey: .imageAttachmentId)
        previewDescription = try container.decodeIfPresent(String.self, forKey: .previewDescription)
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        super.init()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let urlString = urlString {
            try container.encode(urlString, forKey: .urlString)
        }
        if let title = title {
            try container.encode(title, forKey: .title)
        }
        try container.encode(usesV2AttachmentReferenceValue?.intValue, forKey: .usesV2AttachmentReferenceValue)
        if let imageAttachmentId = imageAttachmentId {
            try container.encode(imageAttachmentId, forKey: .imageAttachmentId)
        }
        if let previewDescription = previewDescription {
            try container.encode(previewDescription, forKey: .previewDescription)
        }
        if let date = date {
            try container.encode(date, forKey: .date)
        }
    }
}
