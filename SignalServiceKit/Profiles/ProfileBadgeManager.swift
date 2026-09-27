//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Model object for a badge. Only information for the badge itself, nothing user-specific (expirations, visibility, etc.)
public class ProfileBadge:
    Codable,
    FetchableRecord,
    PersistableRecord,
    Equatable
{
    public static let databaseTableName = "model_ProfileBadgeTable"

    public let id: String
    public let category: Category
    public let localizedName: String
    public let localizedDescriptionFormatString: String
    /// - Note
    /// At the time of writing, this is set by the server to the sha256 of the
    /// badge's image.
    let resourcePath: String

    let badgeVariant: BadgeVariant
    let localization: String

    public let duration: TimeInterval?

    public var assets: BadgeAssets {
        BadgeAssets(
            scale: badgeVariant.intendedScale,
            remoteSourceUrl: remoteAssetUrl,
            localAssetDirectory: localAssetDir,
        )
    }

    private enum CodingKeys: String, CodingKey {
        // Skip encoding of `assets`
        case id
        case category = "rawCategory"
        case localizedName
        case localizedDescriptionFormatString
        case resourcePath
        case badgeVariant
        case localization
        case duration
    }

    public init(jsonDictionary: [String: Any]) throws {
        let params = ParamParser(jsonDictionary)

        id = try params.required(key: "id")
        category = Category(rawValue: try params.required(key: "category"))
        localizedName = try params.required(key: "name")
        localizedDescriptionFormatString = try params.required(key: "description")

        let preferredVariant = BadgeVariant.devicePreferred
        let spriteArray: [String] = try params.required(key: "sprites6")
        guard spriteArray.count == 6 else { throw OWSAssertionError("Invalid number of sprites") }

        resourcePath = spriteArray[preferredVariant.sprite6Index]
        badgeVariant = preferredVariant

        // TODO: Badges — Check with server to see if they'll return a Content-language
        // TODO: Badges — What about reordered languages? Maybe clear if any change?
        localization = Locale.preferredLanguages[0]

        duration = try params.optional(key: "duration")
    }

    public required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        category = try values.decode(Category.self, forKey: .category)
        localizedName = try values.decode(String.self, forKey: .localizedName)
        localizedDescriptionFormatString = try values.decode(String.self, forKey: .localizedDescriptionFormatString)
        resourcePath = try values.decode(String.self, forKey: .resourcePath)
        badgeVariant = try values.decode(BadgeVariant.self, forKey: .badgeVariant)
        localization = try values.decode(String.self, forKey: .localization)
        duration = try values.decodeIfPresent(TimeInterval.self, forKey: .duration)
    }

    public static func ==(lhs: ProfileBadge, rhs: ProfileBadge) -> Bool {
        return lhs.id == rhs.id &&
            lhs.category == rhs.category &&
            lhs.localizedName == rhs.localizedName &&
            lhs.localizedDescriptionFormatString == rhs.localizedDescriptionFormatString &&
            lhs.resourcePath == rhs.resourcePath &&
            lhs.badgeVariant == rhs.badgeVariant &&
            lhs.localization == rhs.localization &&
            lhs.duration == rhs.duration
        // Don't check assets -- it's essentially a derived property that doesn't
        // need to be included in equality checks.
    }

    // MARK: - Assets

    static let remoteAssetPrefix = URL(string: "https://updates2.signal.org/static/badges/")!
    static let localAssetPrefix = URL(fileURLWithPath: "ProfileBadges", isDirectory: true, relativeTo: OWSFileSystem.appSharedDataDirectoryURL())

    var remoteAssetUrl: URL {
        let encoded = resourcePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? resourcePath
        return Self.remoteAssetPrefix.appendingPathComponent(encoded)
    }

    var localAssetDir: URL {
        let extensionIndex = resourcePath.firstIndex(of: ".") ?? resourcePath.endIndex
        let trimmedPath = resourcePath.prefix(upTo: extensionIndex)
        return Self.localAssetPrefix.appendingPathComponent(String(trimmedPath), isDirectory: true)
    }

    // MARK: -

    /// Server defined category for the badge type
    public enum Category: String, Codable {
        case donor
        case other

        /// Creates a category from a raw string.
        ///
        /// Unrecognized strings are converted to `.other`. This includes
        /// `"testing"`, which can be returned by the server in staging.
        public init(rawValue: String) {
            switch rawValue.lowercased() {
            case "donor": self = .donor
            default: self = .other
            }
        }
    }

    /// The badge image variant that the spritSheetUrl points to
    /// Currently only used for device pixel scale
    enum BadgeVariant: String, Codable {
        case mdpi
        case xhdpi
        case xxhdpi

        var intendedScale: Int {
            switch self {
            case .mdpi: return 1
            case .xhdpi: return 2
            case .xxhdpi: return 3
            }
        }

        var sprite6Index: Int {
            switch self {
            case .mdpi: return 1
            case .xhdpi: return 3
            case .xxhdpi: return 4
            }
        }

        static var devicePreferred: BadgeVariant {
            let displayScale = UITraitCollection.current.displayScale
            switch displayScale {
            case 0..<1.5:
                owsAssertDebug(displayScale == 1.0, "Unrecognized scale: \(displayScale)")
                return .mdpi
            case 1.5..<2.5:
                owsAssertDebug(displayScale == 2.0, "Unrecognized scale: \(displayScale)")
                return .xhdpi
            case 2.5...:
                owsAssertDebug(displayScale == 3.0, "Unrecognized scale: \(displayScale)")
                return .xxhdpi
            default:
                owsFailDebug("Unrecognized scale: \(displayScale)")
                return .xhdpi
            }
        }
    }
}

// MARK: - ProfileBadgeManager

public class ProfileBadgeManager {
    private let taskQueue: KeyedConcurrentTaskQueue<String>

    init() {
        self.taskQueue = KeyedConcurrentTaskQueue(concurrentLimitPerKey: 1)
    }

    // MARK: -

    public func createOrUpdateBadge(
        _ newBadge: ProfileBadge,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try newBadge.save(tx.database)
        }
    }

    public func fetchBoostBadge(
        id: BoostBadgeIds,
        tx: DBReadTransaction,
    ) -> ProfileBadge? {
        return fetchBadgeWithId(id.rawValue, tx: tx)
    }

    public func fetchSubscriptionBadge(
        id: SubscriptionBadgeIds,
        tx: DBReadTransaction,
    ) -> ProfileBadge? {
        return fetchBadgeWithId(id.rawValue, tx: tx)
    }

    public func fetchGiftBadge(
        id: GiftBadgeIds,
        tx: DBReadTransaction,
    ) -> ProfileBadge? {
        fetchBadgeWithId(id.rawValue, tx: tx)
    }

    public func fetchBadgeWithId(
        _ badgeId: String,
        tx: DBReadTransaction,
    ) -> ProfileBadge? {
        return failIfThrows {
            try ProfileBadge
                .filter(key: badgeId)
                .fetchOne(tx.database)
        }
    }

    // MARK: -

    public func fetchAssetsIfNecessary(forBadge badge: ProfileBadge) async throws {
        try await taskQueue.runWithThrowingTask(forKey: badge.resourcePath) {
            try await BadgeAssetsFetcher(badgeAssets: badge.assets)
                .fetchAssetsIfNecessary()
        }
    }
}
