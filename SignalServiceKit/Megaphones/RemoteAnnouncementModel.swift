//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct RemoteAnnouncementModel: Codable {
    public enum CodingKeys: String, CodingKey {
        case manifest
        case translation
    }

    public private(set) var manifest: Manifest
    public private(set) var translation: Translation

    public var id: String {
        manifest.id
    }

    public init(manifest: Manifest, translation: Translation) {
        self.manifest = manifest
        self.translation = translation
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        manifest = try container.decode(RemoteAnnouncementModel.Manifest.self, forKey: .manifest)
        translation = try container.decode(RemoteAnnouncementModel.Translation.self, forKey: .translation)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(manifest, forKey: .manifest)
        try container.encode(translation, forKey: .translation)
    }
}

// MARK: - Manifest

extension RemoteAnnouncementModel {
    /// Represents metadata about this announcement
    public struct Manifest: Codable {
        /// A unique ID for this manifest.
        public let id: String

        /// Version representing the minimum app version for which this
        /// upgrade should be shown.
        public let minAppVersion: AppVersionNumber4

        /// A CSV string of `<country-code>:<parts-per-million>` pairs
        /// representing the fraction of users to which this megaphone should
        /// be shown, by country code.
        ///
        /// This is the same format used in remote-config country-code
        /// restrictions.
        public fileprivate(set) var countries: String?

        /// Represents an external web link that will be embedded in message
        fileprivate(set) var link: URL?

        /// Represents an action to be performed in response
        public fileprivate(set) var action: Action?

        public init(
            id: String,
            minAppVersion: AppVersionNumber4,
            countries: String?,
            link: URL?,
            action: Action?,
        ) {
            self.id = id
            self.minAppVersion = minAppVersion
            self.countries = countries
            self.link = link
            self.action = action
        }

        // MARK: Codable

        public enum CodingKeys: String, CodingKey {
            case id
            case minAppVersion
            case countries
            case link
            case action
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            id = try container.decode(String.self, forKey: .id)

            let minAppVersionString = try container.decode(String.self, forKey: .minAppVersion)
            minAppVersion = try AppVersionNumber4(AppVersionNumber(minAppVersionString))

            countries = try container.decode(String.self, forKey: .countries)
            link = try container.decode(URL.self, forKey: .link)
            action = try container.decodeIfPresent(Action.self, forKey: .action)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(id, forKey: .id)
            try container.encode(minAppVersion.wrappedValue.rawValue, forKey: .minAppVersion)

            if let countries {
                try container.encode(countries, forKey: .countries)
            }

            if let link {
                try container.encode(link, forKey: .link)
            }

            if let action {
                try container.encode(action, forKey: .action)
            }
        }
    }
}

// MARK: - Action

extension RemoteAnnouncementModel.Manifest {
    /// Identifies a known action to take in response to a known user
    /// interaction with this release note.
    public enum Action: Codable, Equatable {
        case unrecognized(actionId: String)
        case backupSettings

        public var actionId: String {
            switch self {
            case .unrecognized(let conditionalId):
                return conditionalId
            case .backupSettings:
                return "backupSettings"
            }
        }

        public init(fromActionId actionId: String) {
            self = {
                switch actionId {
                case "backupSettings":
                    return .backupSettings
                default:
                    return .unrecognized(actionId: actionId)
                }
            }()
        }

        // MARK: Codable

        private enum CodingKeys: String, CodingKey {
            case actionId
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let actionId = try container.decode(String.self, forKey: .actionId)
            self.init(fromActionId: actionId)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(actionId, forKey: .actionId)
        }
    }
}

// MARK: - Translation

extension RemoteAnnouncementModel {
    public static let mediaDirectory: URL = {
        let mediaSubdirectory: String = "AnnouncementMedia"
        return OWSFileSystem.appSharedDataDirectoryURL().appendingPathComponent(mediaSubdirectory)
    }()

    /// Represents a localized, user-presentable description of this announcement.
    public struct Translation: Codable {
        /// A unique ID for the announcement this translation corresponds to.
        /// Should match the ID for this translation's manifest, and must be a
        /// permissible file name.
        public let id: String

        /// Localized title for this announcement.
        public fileprivate(set) var title: String

        /// Localized body for this announcement.
        public fileprivate(set) var body: String

        /// Path to a remote media asset for this announcement.
        public let mediaRemoteUrlPath: String?

        public var hasImage: Bool

        /// Height and width of media to be presented
        public let mediaSize: CGSize?

        /// mime type of media to be presented
        public let mediaMimeType: String?

        /// Localized link text for this announcement
        public let linkText: String?

        /// Localized text to display on the call-to-action when this
        /// announcement is presented.
        public let callToActionText: String?

        public let bodyRanges: [BodyRange]?

        public init(
            id: String,
            title: String,
            body: String,
            mediaRemoteUrlPath: String?,
            mediaSize: CGSize?,
            mediaMimeType: String?,
            linkText: String?,
            callToActionText: String?,
            bodyRanges: [BodyRange]?,
        ) {
            self.id = id
            self.title = title
            self.body = body
            self.mediaRemoteUrlPath = mediaRemoteUrlPath
            self.mediaSize = mediaSize
            self.mediaMimeType = mediaMimeType
            self.linkText = linkText
            self.callToActionText = callToActionText
            self.hasImage = false // Will be set later when we download image.
            self.bodyRanges = bodyRanges
        }

        // MARK: Codable

        public enum CodingKeys: String, CodingKey {
            case id
            case title
            case body
            case mediaRemoteUrlPath
            case mediaSize
            case mediaMimeType
            case linkText
            case callToActionText
            case hasImage
            case bodyRanges
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            body = try container.decode(String.self, forKey: .body)

            mediaRemoteUrlPath = try container.decodeIfPresent(String.self, forKey: .mediaRemoteUrlPath)
            mediaSize = try container.decodeIfPresent(CGSize.self, forKey: .mediaSize)
            mediaMimeType = try container.decodeIfPresent(String.self, forKey: .mediaMimeType)
            linkText = try container.decodeIfPresent(String.self, forKey: .linkText)
            callToActionText = try container.decodeIfPresent(String.self, forKey: .callToActionText)
            hasImage = try container.decode(Bool.self, forKey: .hasImage)
            bodyRanges = try container.decodeIfPresent([BodyRange].self, forKey: .bodyRanges)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encode(body, forKey: .body)

            if let mediaRemoteUrlPath {
                try container.encode(mediaRemoteUrlPath, forKey: .mediaRemoteUrlPath)
            }

            if let mediaSize {
                try container.encode(mediaSize, forKey: .mediaSize)
            }

            if let mediaMimeType {
                try container.encode(mediaMimeType, forKey: .mediaMimeType)
            }

            if let linkText {
                try container.encode(linkText, forKey: .linkText)
            }

            if let callToActionText {
                try container.encode(callToActionText, forKey: .callToActionText)
            }

            try container.encode(hasImage, forKey: .hasImage)

            if let bodyRanges {
                try container.encode(bodyRanges, forKey: .bodyRanges)
            }
        }
    }
}

// MARK: - Parsing manifests

public extension RemoteAnnouncementModel.Manifest {
    private static let announcementsKey = "announcements"
    private static let uuidKey = "uuid"
    private static let countriesKey = "countries"
    private static let iosMinVersionKey = "iosMinVersion"
    private static let link = "link"
    private static let ctaIdKey = "ctaId"
    private static let includeBoostMessage = "includeBoostMessage"

    static func parseFrom(parser announcementArrayParser: ParamParser) throws -> [Self] {
        let individualAnnouncements: [[String: Any]] = try announcementArrayParser.required(key: Self.announcementsKey)

        return try individualAnnouncements.compactMap { announcementObject throws -> Self? in
            let announcementParser = ParamParser(announcementObject)

            guard
                let iosMinVersionString: String = try announcementParser.optional(key: Self.iosMinVersionKey),
                let iosMinVersion = try? AppVersionNumber4(AppVersionNumber(iosMinVersionString))
            else {
                Logger.warn("Invalid or missing iosMinVersion in remote announcement manifest")
                return nil
            }

            let uuid: String = try announcementParser.required(key: Self.uuidKey)

            let countries: String? = try announcementParser.optional(key: Self.countriesKey)
            let link: String? = try announcementParser.optional(key: Self.link)

            var linkUrl: URL?
            if let link {
                linkUrl = URL(string: link)
            }
            let ctaId: String? = try announcementParser.optional(key: Self.ctaIdKey)

            var action: Action?
            if let ctaId {
                action = Action(fromActionId: ctaId)
            }

            return RemoteAnnouncementModel.Manifest(
                id: uuid,
                minAppVersion: iosMinVersion,
                countries: countries,
                link: linkUrl,
                action: action,
            )
        }
    }
}

// MARK: - Parsing translations

public extension RemoteAnnouncementModel.Translation {
    struct BodyRange: Codable {
        private static let styleKey = "style"
        private static let startKey = "start"
        private static let lengthKey = "length"

        public let style: MessageBodyRanges.SingleStyle
        public let start: Int
        public let length: Int

        init?(params: [String: Any]) {
            guard
                let style: String = params[Self.styleKey] as? String,
                let start: Int = params[Self.startKey] as? Int,
                let length: Int = params[Self.lengthKey] as? Int
            else {
                return nil
            }

            self.start = start
            self.length = length

            if style == "bold" {
                self.style = .bold
            } else if style == "italic" {
                self.style = .italic
            } else if style == "spoiler" {
                self.style = .spoiler
            } else if style == "strikethrough" {
                self.style = .strikethrough
            } else if style == "mono" {
                self.style = .monospace
            } else {
                Logger.error("Invalid body range style: \(style)")
                return nil
            }
        }
    }

    private static let uuidKey = "uuid"
    private static let mediaHeightKey = "mediaHeight"
    private static let mediaWidthKey = "mediaWidth"
    private static let mediaKey = "media"
    private static let mediaContentTypeKey = "mediaContentType"
    private static let titleKey = "title"
    private static let bodyKey = "body"
    private static let linkTextKey = "linkText"
    private static let ctaTextKey = "callToActionText"
    private static let bodyRangesKey = "bodyRanges"

    static func parseFrom(parser: ParamParser) throws -> Self {
        let uuid: String = try parser.required(key: Self.uuidKey)
        let mediaHeightString: String? = try parser.optional(key: Self.mediaHeightKey)
        let mediaWidthString: String? = try parser.optional(key: Self.mediaWidthKey)

        var mediaSize: CGSize?
        if
            let mediaWidthString,
            let mediaHeightString,
            let mediaWidth = Float(mediaWidthString),
            let mediaHeight = Float(mediaHeightString)
        {
            mediaSize = CGSize(width: CGFloat(mediaWidth), height: CGFloat(mediaHeight))
        }

        let mediaUrl: String? = try parser.optional(key: Self.mediaKey)
        let mediaContentType: String? = try parser.optional(key: Self.mediaContentTypeKey)
        let title: String = try parser.required(key: Self.titleKey)
        let body: String = try parser.required(key: Self.bodyKey)
        let linkText: String? = try parser.optional(key: Self.linkTextKey)
        let ctaText: String? = try parser.optional(key: Self.ctaTextKey)
        let bodyRanges: [BodyRange]? = try (parser.optional(key: Self.bodyRangesKey) as [Any]?)?.compactMap {
            guard let bodyRangeDict = $0 as? [String: Any] else { return nil }
            return BodyRange(params: bodyRangeDict)
        }

        return RemoteAnnouncementModel.Translation(
            id: uuid,
            title: title,
            body: body,
            mediaRemoteUrlPath: mediaUrl,
            mediaSize: mediaSize,
            mediaMimeType: mediaContentType,
            linkText: linkText,
            callToActionText: ctaText,
            bodyRanges: bodyRanges,
        )
    }
}
