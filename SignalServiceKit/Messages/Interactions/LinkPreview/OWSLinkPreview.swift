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

    public let url: URL
    public var urlString: String {
        return url.absoluteString
    }
    public let title: String?
    public let imageData: Data?
    public let imageMimeType: String?
    public let previewDescription: String?
    public let date: Date?

    public init(
        url: URL,
        title: String?,
        imageData: Data? = nil,
        imageMimeType: String? = nil,
        previewDescription: String? = nil,
        date: Date? = nil
    ) {
        self.url = url
        self.title = title
        self.imageData = imageData
        self.imageMimeType = imageMimeType
        self.previewDescription = previewDescription
        self.date = date
    }

    public var displayDomain: String? {
        return URL(string: urlString).flatMap(LinkPreviewHelper.displayDomain(forUrl:))
    }
}

// MARK: - OWSLinkPreview

@objc
public class OWSLinkPreview: MTLModel, Codable {

    public struct Metadata {
        public let urlString: String
        public let title: String?
        public let previewDescription: String?
        public let date: Date?
    }

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

    private init(
        urlString: String,
        title: String?,
        legacyImageAttachmentId: String?,
        usesV2AttachmentReference: Bool
    ) {
        self.urlString = urlString
        self.title = title
        self.imageAttachmentId = legacyImageAttachmentId
        self.usesV2AttachmentReferenceValue = NSNumber(value: usesV2AttachmentReference)

        super.init()
    }

    public static func withLegacyImageAttachment(
        urlString: String,
        title: String? = nil,
        attachmentId: String
    ) -> OWSLinkPreview {
        return .init(
            urlString: urlString,
            title: title,
            legacyImageAttachmentId: attachmentId,
            usesV2AttachmentReference: false
        )
    }

    public static func withLegacyImageAttachment(
        metadata: Metadata,
        attachmentId: String
    ) -> OWSLinkPreview {
        let linkPreview = OWSLinkPreview.withLegacyImageAttachment(
            urlString: metadata.urlString,
            title: metadata.title,
            attachmentId: attachmentId
        )
        linkPreview.previewDescription = metadata.previewDescription
        linkPreview.date = metadata.date
        return linkPreview
    }

    public static func withForeignReferenceImageAttachment(
        urlString: String,
        title: String? = nil
    ) -> OWSLinkPreview {
        return .init(
            urlString: urlString,
            title: title,
            legacyImageAttachmentId: nil,
            usesV2AttachmentReference: true
        )
    }

    public static func withForeignReferenceImageAttachment(
        metadata: Metadata,
        ownerType: TSResourceOwnerType
    ) -> OWSLinkPreview {
        let linkPreview = OWSLinkPreview.withoutImage(
            urlString: metadata.urlString,
            title: metadata.title,
            ownerType: ownerType
        )
        linkPreview.previewDescription = metadata.previewDescription
        linkPreview.date = metadata.date
        return linkPreview
    }

    public static func withoutImage(
        urlString: String,
        title: String? = nil,
        ownerType: TSResourceOwnerType,
        usesV2AttachmentReference: Bool = true
    ) -> OWSLinkPreview {
        /// In legacy-world, we put nil on the attachment id to mark this as not having an attachment
        /// In v2-world, the existence of an AttachmentReference is what determines if a link preview has an image or not.
        /// In either case, the legacy attachment id is nil, but fetching ends up different, so mark it down at write time.
        return .init(
            urlString: urlString,
            title: title,
            legacyImageAttachmentId: nil,
            usesV2AttachmentReference: usesV2AttachmentReference
        )
    }

    public static func withoutImage(
        metadata: Metadata,
        ownerType: TSResourceOwnerType
    ) -> OWSLinkPreview {
        let linkPreview = OWSLinkPreview.withoutImage(
            urlString: metadata.urlString,
            title: metadata.title,
            ownerType: ownerType
        )
        linkPreview.previewDescription = metadata.previewDescription
        linkPreview.date = metadata.date
        return linkPreview
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
