//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum LinkPreviewError: Error {
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
public class OWSLinkPreviewDraft: Equatable {

    public let url: URL
    public var urlString: String {
        return url.absoluteString
    }

    public let title: String?
    public let imageData: Data?
    public let imageMimeType: String?
    public let previewDescription: String?
    public let date: Date?

    public let isForwarded: Bool

    public init(
        url: URL,
        title: String?,
        imageData: Data? = nil,
        imageMimeType: String? = nil,
        previewDescription: String? = nil,
        date: Date? = nil,
        isForwarded: Bool,
    ) {
        self.url = url
        self.title = title
        self.imageData = imageData
        self.imageMimeType = imageMimeType
        self.previewDescription = previewDescription
        self.date = date
        self.isForwarded = isForwarded
    }

    public var displayDomain: String? {
        return URL(string: urlString).flatMap(LinkPreviewHelper.displayDomain(forUrl:))
    }

    /// Uses identity equatability even though comparing fields seems like it would make more sense because this
    /// object used to inherit from `NSObject` without overridding `isEqual(_)` so it would have inherited
    /// identity equatability.
    public static func ==(lhs: OWSLinkPreviewDraft, rhs: OWSLinkPreviewDraft) -> Bool {
        return lhs === rhs
    }
}

// MARK: - OWSLinkPreview

@objc
public final class OWSLinkPreview: NSObject, NSCoding, NSCopying, Codable {
    public init?(coder: NSCoder) {
        self.date = coder.decodeObject(of: NSDate.self, forKey: "date") as Date?
        self.previewDescription = coder.decodeObject(of: NSString.self, forKey: "previewDescription") as String?
        self.title = coder.decodeObject(of: NSString.self, forKey: "title") as String?
        self.urlString = coder.decodeObject(of: NSString.self, forKey: "urlString") as String?
    }

    public func encode(with coder: NSCoder) {
        if let date {
            coder.encode(date, forKey: "date")
        }
        if let previewDescription {
            coder.encode(previewDescription, forKey: "previewDescription")
        }
        if let title {
            coder.encode(title, forKey: "title")
        }
        if let urlString {
            coder.encode(urlString, forKey: "urlString")
        }
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(date)
        hasher.combine(previewDescription)
        hasher.combine(title)
        hasher.combine(urlString)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard type(of: self) == type(of: object) else { return false }
        guard self.date == object.date else { return false }
        guard self.previewDescription == object.previewDescription else { return false }
        guard self.title == object.title else { return false }
        guard self.urlString == object.urlString else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

    public struct Metadata {
        public let urlString: String
        public let title: String?
        public let previewDescription: String?
        public let date: Date?
    }

    public let urlString: String?
    public let title: String?
    public let previewDescription: String?
    public let date: Date?

    public init(
        urlString: String,
        title: String? = nil,
        previewDescription: String? = nil,
        date: Date? = nil,
    ) {
        self.urlString = urlString
        self.title = title
        self.previewDescription = previewDescription
        self.date = date

        super.init()
    }

    public convenience init(metadata: Metadata) {
        self.init(
            urlString: metadata.urlString,
            title: metadata.title,
            previewDescription: metadata.previewDescription,
            date: metadata.date,
        )
    }

    @objc
    public class func isNoPreviewError(_ error: Error) -> Bool {
        guard let error = error as? LinkPreviewError else {
            return false
        }
        return error == .noPreview
    }

    public var displayDomain: String? {
        urlString.flatMap(URL.init(string:)).flatMap(LinkPreviewHelper.displayDomain(forUrl:))
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
        previewDescription = try container.decodeIfPresent(String.self, forKey: .previewDescription)
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        super.init()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let urlString {
            try container.encode(urlString, forKey: .urlString)
        }
        if let title {
            try container.encode(title, forKey: .title)
        }
        if let previewDescription {
            try container.encode(previewDescription, forKey: .previewDescription)
        }
        if let date {
            try container.encode(date, forKey: .date)
        }
    }
}
