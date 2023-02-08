//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class SignalServiceProfile: NSObject {

    public enum ValidationError: Error {
        case invalid(description: String)
        case invalidIdentityKey(description: String)
        case invalidProfileName(description: String)
    }

    public let address: SignalServiceAddress
    public let identityKey: Data
    public let profileNameEncrypted: Data?
    public let bioEncrypted: Data?
    public let bioEmojiEncrypted: Data?
    public let avatarUrlPath: String?
    public let paymentAddressEncrypted: Data?
    public let unidentifiedAccessVerifier: Data?
    public let hasUnrestrictedUnidentifiedAccess: Bool
    public let supportsAnnouncementOnlyGroups: Bool
    public let supportsSenderKey: Bool
    public let supportsChangeNumber: Bool
    public let credential: Data?
    public let badges: [(OWSUserProfileBadgeInfo, ProfileBadge)]
    public let isStoriesCapable: Bool
    public let canReceiveGiftBadges: Bool

    public init(address: SignalServiceAddress?, responseObject: Any?) throws {
        guard let params = ParamParser(responseObject: responseObject) else {
            throw ValidationError.invalid(description: "invalid response: \(String(describing: responseObject))")
        }

        if let address = address {
            self.address = address
        } else if let uuidString: String = try params.required(key: "uuid") {
            self.address = SignalServiceAddress(uuidString: uuidString)
        } else {
            throw ValidationError.invalid(description: "response or input missing address")
        }

        let identityKeyWithType = try params.requiredBase64EncodedData(key: "identityKey")
        guard identityKeyWithType.count == kIdentityKeyLength else {
            throw ValidationError.invalidIdentityKey(description: "malformed identity key \(identityKeyWithType.hexadecimalString) with decoded length: \(identityKeyWithType.count)")
        }
        do {
            // `removeKeyType` is an objc category method only on NSData, so temporarily cast.
            self.identityKey = try (identityKeyWithType as NSData).removeKeyType() as Data
        } catch {
            // `removeKeyType` throws an SCKExceptionWrapperError, which, typically should
            // be unwrapped by any objc code calling this method.
            owsFailDebug("identify key had unexpected format")
            throw ValidationError.invalidIdentityKey(description: "malformed identity key \(identityKeyWithType.hexadecimalString) with data: \(identityKeyWithType)")
        }

        self.profileNameEncrypted = try params.optionalBase64EncodedData(key: "name")

        self.bioEncrypted = try params.optionalBase64EncodedData(key: "about")

        self.bioEmojiEncrypted = try params.optionalBase64EncodedData(key: "aboutEmoji")

        let avatarUrlPath: String? = try params.optional(key: "avatar")
        self.avatarUrlPath = avatarUrlPath

        self.paymentAddressEncrypted = try params.optionalBase64EncodedData(key: "paymentAddress")

        self.unidentifiedAccessVerifier = try params.optionalBase64EncodedData(key: "unidentifiedAccess")

        self.hasUnrestrictedUnidentifiedAccess = try params.optional(key: "unrestrictedUnidentifiedAccess") ?? false

        self.supportsAnnouncementOnlyGroups = Self.parseCapabilityFlag(capabilityKey: "announcementGroup",
                                                                       params: params,
                                                                       requireCapability: true)
        self.supportsSenderKey = Self.parseCapabilityFlag(capabilityKey: "senderKey",
                                                          params: params,
                                                          requireCapability: true)
        self.supportsChangeNumber = Self.parseCapabilityFlag(capabilityKey: "changeNumber",
                                                             params: params,
                                                             requireCapability: true)

        self.credential = try params.optionalBase64EncodedData(key: "credential")

        self.isStoriesCapable = Self.parseCapabilityFlag(capabilityKey: "stories", params: params, requireCapability: true)

        self.canReceiveGiftBadges = Self.parseCapabilityFlag(capabilityKey: "giftBadges", params: params, requireCapability: true)

        if RemoteConfig.donorBadgeDisplay,
           let badgeArray: [[String: Any]] = try params.optional(key: "badges") {
            self.badges = badgeArray.compactMap {
                do {
                    let badgeParams = ParamParser(dictionary: $0)
                    let isVisible: Bool? = try badgeParams.optional(key: "visible")
                    let expiration: TimeInterval? = try badgeParams.optional(key: "expiration")
                    let expirationMills = expiration.flatMap { UInt64($0 * 1000) }

                    let badge = try ProfileBadge(jsonDictionary: $0)
                    let badgeMetadata: OWSUserProfileBadgeInfo
                    if let expirationMills = expirationMills, let isVisible = isVisible {
                        badgeMetadata = OWSUserProfileBadgeInfo(badgeId: badge.id, expiration: expirationMills, isVisible: isVisible)
                    } else {
                        badgeMetadata = OWSUserProfileBadgeInfo(badgeId: badge.id)
                    }
                    return (badgeMetadata, badge)
                } catch {
                    owsFailDebug("Invalid badge: \(error)")
                    return nil
                }
            }
        } else {
            self.badges = []
        }
    }

    private static func parseCapabilityFlag(capabilityKey: String,
                                            params: ParamParser,
                                            requireCapability: Bool) -> Bool {
        do {
            let capabilitiesJson: Any? = try params.required(key: "capabilities")
            if let capabilities = ParamParser(responseObject: capabilitiesJson) {
                if let value: Bool = try capabilities.optional(key: capabilityKey) {
                    return value
                } else {
                    if requireCapability {
                        Logger.verbose("capabilitiesJson: \(String(describing: capabilitiesJson))")
                        owsFailDebug("Missing capability: \(capabilityKey).")
                    } else {
                        Logger.warn("Missing capability: \(capabilityKey).")
                    }
                    // The capability has been retired from the service.
                    return true
                }
            } else {
                owsFailDebug("Missing capabilities.")
                return true
            }
        } catch {
            owsFailDebug("Error: \(error)")
            return true
        }
    }
}
