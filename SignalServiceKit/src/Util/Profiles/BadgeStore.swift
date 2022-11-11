//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Model object for a badge. Only information for the badge itself, nothing user-specific (expirations, visibility, etc.)
@objc
public class ProfileBadge: NSObject, Codable {
    public let id: String
    public let rawCategory: String
    public let localizedName: String
    public let localizedDescriptionFormatString: String
    let resourcePath: String

    let badgeVariant: BadgeVariant
    let localization: String

    public let duration: TimeInterval?

    // Nil until a badge is checked in to the BadgeStore
    @objc
    public fileprivate(set) var assets: BadgeAssets?

    private enum CodingKeys: String, CodingKey {
        // Skip encoding of `assets`
        case id, rawCategory, localizedName, localizedDescriptionFormatString, resourcePath, badgeVariant, localization, duration
    }

    public init(jsonDictionary: [String: Any]) throws {
        let params = ParamParser(dictionary: jsonDictionary)

        id = try params.required(key: "id")
        rawCategory = try params.required(key: "category")
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

    override public func isEqual(_ object: Any?) -> Bool {
        guard
            let other = object as? Self,
            type(of: self) == type(of: other)
        else {
            return false
        }

        return
            id == other.id &&
            rawCategory == other.rawCategory &&
            localizedName == other.localizedName &&
            localizedDescriptionFormatString == other.localizedDescriptionFormatString &&
            resourcePath == other.resourcePath &&
            badgeVariant == other.badgeVariant &&
            localization == other.localization &&
            duration == other.duration
            // Don't check assets -- it's essentially a derived property that doesn't
            // need to be included in equality checks.
    }
}

// MARK: - ProfileBadge assets

extension ProfileBadge {
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
}

// MARK: - ProfileBadge enums

extension ProfileBadge {
    /// Server defined category for the badge type
    enum Category: String, Codable {
        case donor
        case other
        case testing
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
            // TODO: Badges — Is this safe from an app extension? I'm pretty sure it isn't, but I'm
            // not seeing anything in the docs that indicates this is this case. Should double check this.
            switch UIScreen.main.scale {
            case 0..<1.5:
                owsAssertDebug(UIScreen.main.scale == 1.0, "Unrecognized scale: \(UIScreen.main.scale)")
                return .mdpi
            case 1.5..<2.5:
                owsAssertDebug(UIScreen.main.scale == 2.0, "Unrecognized scale: \(UIScreen.main.scale)")
                return .xhdpi
            case 2.5...:
                owsAssertDebug(UIScreen.main.scale == 3.0, "Unrecognized scale: \(UIScreen.main.scale)")
                return .xxhdpi
            default:
                owsFailDebug("Unrecognized scale: \(UIScreen.main.scale)")
                return .xhdpi
            }
        }
    }
}

// MARK: - ProfileBadge fake assets

#if TESTABLE_BUILD
extension ProfileBadge {
    public func _testingOnly_populateAssets() {
        assets = BadgeAssets(scale: badgeVariant.intendedScale,
                             remoteSourceUrl: remoteAssetUrl,
                             localAssetDirectory: localAssetDir)
    }
}
#endif

// MARK: - ProfileBadge<PersistableRecord>

extension ProfileBadge: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "model_ProfileBadgeTable"
}

// MARK: - BadgeStore

@objc
public class BadgeStore: NSObject {
    let lock = UnfairLock()
    var badgeCache = LRUCache<String, ProfileBadge>(maxSize: 5)
    // BadgeAssets have two roles: fetching assets we don't currently have and vending retrieved assets as UIImages
    // They're a reference type, so we're fine aliasing the assets into multiple ProfileBadges
    // We don't use an LRUCache since we don't want to clear out BadgeAssets that are mid-fetch and risk having
    // two instances of this class trying to fetch assets at the same time.
    var assetCache = [String: BadgeAssets]()

    // TODO: Badging — Memory warnings?

    func createOrUpdateBadge(_ newBadge: ProfileBadge, transaction writeTx: SDSAnyWriteTransaction) throws {
        try lock.withLock {
            // First, we check to see if we already have a cached badge that's equal to the new version
            // If so, we can just update the assets property and return
            if let cachedValue = badgeCache[newBadge.id], cachedValue == newBadge {
                Logger.debug("Badge already up-to-date")
                newBadge.assets = cachedValue.assets
                return
            }

            // Something changed, so we need to update our database copy
            try newBadge.save(writeTx.unwrapGrdbWrite.database)

            // Finally we update our cached badge and start preparing our assets
            firstly {
                populateAssets(newBadge)
            }.catch { error in
                owsFailDebug("Failed to populate assets on badge \(error)")
            }

            owsAssertDebug(newBadge.assets != nil)
            badgeCache[newBadge.id] = newBadge
        }
    }

    func fetchBadgeWithId(_ badgeId: String, readTx: SDSAnyReadTransaction) -> ProfileBadge? {
        do {
            return try lock.withLock {
                if let cachedBadge = badgeCache[badgeId] {
                    owsAssertDebug(cachedBadge.assets != nil)
                    return cachedBadge
                } else if let fetchedBadge = try ProfileBadge.filter(key: badgeId).fetchOne(readTx.unwrapGrdbRead.database) {
                    firstly {
                        populateAssets(fetchedBadge)
                    }.catch { error in
                        owsFailDebug("Failed to populate assets on badge \(error)")
                    }

                    owsAssertDebug(fetchedBadge.assets != nil)
                    badgeCache[fetchedBadge.id] = fetchedBadge
                    return fetchedBadge
                } else {
                    return nil
                }
            }
        } catch {
            owsFailDebug("Failed to fetch badge: \(error)")
            return nil
        }
    }

    public func populateAssetsOnBadge(_ badge: ProfileBadge) -> Promise<Void> {
        return lock.withLock {
            populateAssets(badge)
        }
    }

    private func populateAssets(_ badge: ProfileBadge) -> Promise<Void> {
        lock.assertOwner()

        let badgeAssets: BadgeAssets
        // We try and reuse any existing BadgeAssets instances if we have one cached
        if let cachedValue = badgeCache[badge.id], cachedValue.resourcePath == badge.resourcePath, let assets = cachedValue.assets {
            badgeAssets = assets
        } else if let cachedAssets = assetCache[badge.resourcePath] {
            badgeAssets = cachedAssets
        } else {
            badgeAssets = BadgeAssets(
                scale: badge.badgeVariant.intendedScale,
                remoteSourceUrl: badge.remoteAssetUrl,
                localAssetDirectory: badge.localAssetDir)
            assetCache[badge.resourcePath] = badgeAssets
        }
        badge.assets = badgeAssets

        return badgeAssets.prepareAssetsIfNecessary()
    }
}
