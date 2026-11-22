//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

/// Represents a user's profile as fetched from the service.
///
/// All non-capability fields are encrypted, and if present should be decrypted
/// using this user's profile key.
public class SignalServiceProfile {
    private struct ValidationError: Error, CustomStringConvertible {
        let description: String
    }

    public let serviceId: ServiceId
    public let identityKey: IdentityKey
    public let profileNameEncrypted: Data?
    public let bioEncrypted: Data?
    public let bioEmojiEncrypted: Data?
    public let avatarUrlPath: String?
    public let paymentAddressEncrypted: Data?
    public let unidentifiedAccessVerifier: Data?
    public let hasUnrestrictedUnidentifiedAccess: Bool
    public let credential: Data?
    /// Metadata about the badges present on the profile, as pertains to the
    /// specific profile.
    public let profileBadgeUserInfos: [OWSUserProfileBadgeInfo]
    /// Info about the badges present on the profile, describing the badge
    /// object itself.
    public let profileBadges: [ProfileBadge]
    public let phoneNumberSharingEncrypted: Data?
    public let capabilities: [RecipientCapability: Bool]

    private init(
        serviceId: ServiceId,
        identityKey: IdentityKey,
        profileNameEncrypted: Data?,
        bioEncrypted: Data?,
        bioEmojiEncrypted: Data?,
        avatarUrlPath: String?,
        paymentAddressEncrypted: Data?,
        unidentifiedAccessVerifier: Data?,
        hasUnrestrictedUnidentifiedAccess: Bool,
        credential: Data?,
        badges: [(userInfo: OWSUserProfileBadgeInfo, badge: ProfileBadge)],
        phoneNumberSharingEncrypted: Data?,
        capabilities: [RecipientCapability: Bool],
    ) {
        self.serviceId = serviceId
        self.identityKey = identityKey
        self.profileNameEncrypted = profileNameEncrypted
        self.bioEncrypted = bioEncrypted
        self.bioEmojiEncrypted = bioEmojiEncrypted
        self.avatarUrlPath = avatarUrlPath
        self.paymentAddressEncrypted = paymentAddressEncrypted
        self.unidentifiedAccessVerifier = unidentifiedAccessVerifier
        self.hasUnrestrictedUnidentifiedAccess = hasUnrestrictedUnidentifiedAccess
        self.credential = credential
        self.profileBadgeUserInfos = badges.map(\.userInfo)
        self.profileBadges = badges.map(\.badge)
        self.phoneNumberSharingEncrypted = phoneNumberSharingEncrypted
        self.capabilities = capabilities
    }

    public static func fromResponse(serviceId: ServiceId, params: ParamParser) throws -> SignalServiceProfile {
        do {
            let identityKey = try IdentityKey(bytes: try params.requiredBase64EncodedData(key: "identityKey"))
            let profileNameEncrypted = try params.optionalBase64EncodedData(key: "name")
            let bioEncrypted = try params.optionalBase64EncodedData(key: "about")
            let bioEmojiEncrypted = try params.optionalBase64EncodedData(key: "aboutEmoji")
            let avatarUrlPath: String? = try params.optional(key: "avatar")
            let paymentAddressEncrypted = try params.optionalBase64EncodedData(key: "paymentAddress")
            let unidentifiedAccessVerifier = try params.optionalBase64EncodedData(key: "unidentifiedAccess")
            let hasUnrestrictedUnidentifiedAccess: Bool = try params.optional(key: "unrestrictedUnidentifiedAccess") ?? false
            let credential = try params.optionalBase64EncodedData(key: "credential")
            let badges: [(OWSUserProfileBadgeInfo, ProfileBadge)] = try parseBadges(params: params)
            let phoneNumberSharingEncrypted = try params.optionalBase64EncodedData(key: "phoneNumberSharing")
            let capabilities = try parseCapabilities(params: params)

            return SignalServiceProfile(
                serviceId: serviceId,
                identityKey: identityKey,
                profileNameEncrypted: profileNameEncrypted,
                bioEncrypted: bioEncrypted,
                bioEmojiEncrypted: bioEmojiEncrypted,
                avatarUrlPath: avatarUrlPath,
                paymentAddressEncrypted: paymentAddressEncrypted,
                unidentifiedAccessVerifier: unidentifiedAccessVerifier,
                hasUnrestrictedUnidentifiedAccess: hasUnrestrictedUnidentifiedAccess,
                credential: credential,
                badges: badges,
                phoneNumberSharingEncrypted: phoneNumberSharingEncrypted,
                capabilities: capabilities,
            )
        } catch let error {
            throw ValidationError(description: "Failed to parse profile JSON: \(error)")
        }
    }

    private static func parseBadges(params: ParamParser) throws -> [(OWSUserProfileBadgeInfo, ProfileBadge)] {
        if let badgeArray: [[String: Any]] = try params.optional(key: "badges") {
            return try badgeArray.compactMap { badgeDict in
                let badgeParams = ParamParser(badgeDict)
                let isVisible: Bool? = try badgeParams.optional(key: "visible")
                let expiration: TimeInterval? = try badgeParams.optional(key: "expiration")
                let expirationMills = expiration.flatMap { UInt64($0 * 1000) }

                let badge = try ProfileBadge(jsonDictionary: badgeDict)
                let badgeMetadata: OWSUserProfileBadgeInfo
                if let expirationMills, let isVisible {
                    badgeMetadata = OWSUserProfileBadgeInfo(badgeId: badge.id, expiration: expirationMills, isVisible: isVisible)
                } else {
                    badgeMetadata = OWSUserProfileBadgeInfo(badgeId: badge.id)
                }
                return (badgeMetadata, badge)
            }
        } else {
            return []
        }
    }

    private static func parseCapabilities(params: ParamParser) throws -> [RecipientCapability: Bool] {
        guard let capabilitiesDict: [String: Any] = try params.required(key: "capabilities") else {
            throw ValidationError(description: "Missing or invalid capabilities JSON!")
        }

        var result = [RecipientCapability: Bool]()
        let capabilitiesParser = ParamParser(capabilitiesDict)
        for capability in RecipientCapability.allCases where capability != .dummy {
            let isEnabled: Bool? = try? capabilitiesParser.optional(key: capability.rawValue)
            result[capability] = isEnabled
        }
        return result
    }
}
