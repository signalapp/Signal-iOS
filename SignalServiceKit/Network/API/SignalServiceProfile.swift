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

    public struct Capabilities {
        public let deleteSync: Bool
        public let storageServiceRecordIkm: Bool
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
    public let badges: [(OWSUserProfileBadgeInfo, ProfileBadge)]
    public let phoneNumberSharingEncrypted: Data?

    public let capabilities: Capabilities

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
        badges: [(OWSUserProfileBadgeInfo, ProfileBadge)],
        phoneNumberSharingEncrypted: Data?,
        capabilities: Capabilities
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
        self.badges = badges
        self.phoneNumberSharingEncrypted = phoneNumberSharingEncrypted
        self.capabilities = capabilities
    }

    public static func fromResponse(serviceId: ServiceId, responseObject: Any?) throws -> SignalServiceProfile {
        guard let params = ParamParser(responseObject: responseObject) else {
            throw ValidationError(description: "Invalid response JSON!")
        }

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
            let capabilities: Capabilities = try parseCapabilities(params: params)

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
                capabilities: capabilities
            )
        } catch let error {
            throw ValidationError(description: "Failed to parse profile JSON: \(error)")
        }
    }

    private static func parseBadges(params: ParamParser) throws -> [(OWSUserProfileBadgeInfo, ProfileBadge)] {
        if let badgeArray: [[String: Any]] = try params.optional(key: "badges") {
            return try badgeArray.compactMap { badgeDict in
                let badgeParams = ParamParser(dictionary: badgeDict)
                let isVisible: Bool? = try badgeParams.optional(key: "visible")
                let expiration: TimeInterval? = try badgeParams.optional(key: "expiration")
                let expirationMills = expiration.flatMap { UInt64($0 * 1000) }

                let badge = try ProfileBadge(jsonDictionary: badgeDict)
                let badgeMetadata: OWSUserProfileBadgeInfo
                if let expirationMills = expirationMills, let isVisible = isVisible {
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

    private static func parseCapabilities(params: ParamParser) throws -> Capabilities {
        guard
            let capabilitiesJson: Any? = try params.required(key: "capabilities"),
            let capabilitiesParser = ParamParser(responseObject: capabilitiesJson)
        else {
            throw ValidationError(description: "Missing or invalid capabilities JSON!")
        }

        return Capabilities(
            deleteSync: parseCapabilityFlag(
                capabilitiesParser: capabilitiesParser,
                capabilityKey: AccountAttributes.Capabilities.CodingKeys.deleteSyncSendSupport.rawValue
            ),
            storageServiceRecordIkm: parseCapabilityFlag(
                capabilitiesParser: capabilitiesParser,
                capabilityKey: AccountAttributes.Capabilities.CodingKeys.storageServiceRecordIkm.rawValue
            )
        )
    }

    /// Parse a boolean capability with the given key from the given parser.
    /// - Important
    /// If the capability is missing (or weirdly fails to parse), we assume it
    /// was removed from the service and is therefore default-true.
    private static func parseCapabilityFlag(
        capabilitiesParser: ParamParser,
        capabilityKey: String
    ) -> Bool {
        do {
            guard let capabilityFlag: Bool = try capabilitiesParser.optional(key: capabilityKey) else {
                owsFailDebug("Missing capability \(capabilityKey)! Assuming retired from service, and therefore hardcoded-on.")
                return true
            }

            return capabilityFlag
        } catch {
            owsFailDebug("Failed to parse capability \(capabilityKey)! Hardcoding to true.")
            return true
        }
    }
}
