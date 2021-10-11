//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

/// Model object for a badge. Only information for the badge itself, nothing user-specific (expirations, visibility, etc.)
@objc
public class ProfileBadge: NSObject, Codable {
    static let remoteAssetPrefix = URL(string: "https://updates2.signal.org/static/badges/")!

    let id: String
    let rawCategory: String
    let localizedName: String
    let localizedDescriptionFormatString: String
    let resourcePath: String

    var remoteResourceUrl: URL { URL(string: resourcePath, relativeTo: Self.remoteAssetPrefix)! }

    let badgeVariant: BadgeVariant
    let localization: String

    init(jsonDictionary: [String: Any]) throws {
        let params = ParamParser(dictionary: jsonDictionary)

        id = try params.required(key: "id")
        rawCategory = try params.required(key: "category")
        localizedName = try params.required(key: "name")
        localizedDescriptionFormatString = try params.required(key: "description")

        let preferredVariant = BadgeVariant.devicePreferred
        resourcePath = try params.required(key: preferredVariant.rawValue)
        badgeVariant = preferredVariant

        // TODO: Badges — Check with server to see if they'll return a Content-language
        // TODO: Badges — What about reordered languages? Maybe clear if any change?
        localization = Locale.preferredLanguages[0]
    }
}

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

        var intendedScale: Float {
            switch self {
            case .mdpi: return 1.0
            case .xhdpi: return 2.0
            case .xxhdpi: return 3.0
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

extension ProfileBadge: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "model_ProfileBadgeTable"
}




@objc
public class BadgeStore: NSObject {
    override init() {}

    // TODO: Badging — Caching?
    func createOrUpdateBadge(_ badge: ProfileBadge, transaction writeTx: SDSAnyWriteTransaction) throws {
        try badge.save(writeTx.unwrapGrdbWrite.database)
    }
}
