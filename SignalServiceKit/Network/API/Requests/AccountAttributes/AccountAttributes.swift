//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Account attributes set on the server via `updatePrimaryDeviceAttributesRequest` request,
/// as well as various registration requests.
public struct AccountAttributes: Codable {

    /// All Signal-iOS clients support voice
    public let voice: Bool = true

    /// All Signal-iOS clients support voice
    public let video: Bool = true

    /// Devices that don't support push must tell the server they fetch messages manually.
    public let isManualMessageFetchEnabled: Bool

    /// A randomly generated ID that is associated with the user's ACI that identifies
    /// a single registration and is sent to e.g. message recipients. If this changes, it tells
    /// you the sender has re-registered, and is cheaper to compare than doing full key comparison.
    public let registrationId: UInt32

    /// A randomly generated ID that is associated with the user's PNI that identifies
    /// a single registration and is sent to e.g. message recipients. If this changes, it tells
    /// you the sender has re-registered, and is cheaper to compare than doing full key comparison.
    public let pniRegistrationId: UInt32

    /// Base64-encoded SMKUDAccessKey generated from the user's profile key.
    public let unidentifiedAccessKey: String?

    /// Whether the user allows sealed sender messages to come from arbitrary senders.
    public let unrestrictedUnidentifiedAccess: Bool

    /// Reglock token derived from KBS master key, if reglock is enabled.
    /// hexadecimal encoed (e.g. use `Data.hexadecimalString`)
    ///
    /// NOTE: previously, we'd include the pin in this object if the reglock token
    /// was not included but a v1 pin was set. This new formal struct is only used with
    /// v2-compliant clients, so that is ignored.
    public let registrationLockToken: String?

    /// Password derived from the KBS master key that the user may be able to use to
    /// (re)register without needing to verify an code sent to their phone number.
    ///
    /// Is wiped with some frequency by the server to prevent stale-ness for abandoned
    /// accounts, clients should refresh it with some regularity.
    /// This happens on every app update, which is at most once every 90 days.
    /// base64 encoded (e.g. use `Data.base64EncodedString()`)
    public let registrationRecoveryPassword: String?

    /// The device name the user entered for a linked device, encrypted with the user's ACI key pair.
    /// Unused (nil) on primary device requests.
    public let encryptedDeviceName: String?

    /// Whether the user has opted to allow their account to be discoverable by phone number.
    public let discoverableByPhoneNumber: Bool

    public let capabilities: Capabilities

    public enum CodingKeys: String, CodingKey {
        case voice
        case video
        case isManualMessageFetchEnabled = "fetchesMessages"
        case registrationId
        case pniRegistrationId
        case unidentifiedAccessKey
        case unrestrictedUnidentifiedAccess
        case registrationLockToken = "registrationLock"
        case registrationRecoveryPassword = "recoveryPassword"
        case encryptedDeviceName = "name"
        case discoverableByPhoneNumber
        case capabilities
    }

    public init(
        isManualMessageFetchEnabled: Bool,
        registrationId: UInt32,
        pniRegistrationId: UInt32,
        unidentifiedAccessKey: String?,
        unrestrictedUnidentifiedAccess: Bool,
        reglockToken: String?,
        registrationRecoveryPassword: String?,
        encryptedDeviceName: String?,
        discoverableByPhoneNumber: PhoneNumberDiscoverability?,
        capabilities: Capabilities,
    ) {
        self.isManualMessageFetchEnabled = isManualMessageFetchEnabled
        self.registrationId = registrationId
        self.pniRegistrationId = pniRegistrationId
        self.unidentifiedAccessKey = unidentifiedAccessKey
        self.unrestrictedUnidentifiedAccess = unrestrictedUnidentifiedAccess
        self.registrationLockToken = reglockToken
        self.registrationRecoveryPassword = registrationRecoveryPassword
        self.encryptedDeviceName = encryptedDeviceName
        self.discoverableByPhoneNumber = discoverableByPhoneNumber.orAccountAttributeDefault.isDiscoverable
        self.capabilities = capabilities
    }

    public struct Capabilities: Codable {
        public let transfer = true
        public let hasSVRBackups: Bool
        public let spqr = true

        public enum CodingKeys: String, CodingKey {
            case transfer
            case hasSVRBackups = "storage"
            case spqr
        }

        public init(hasSVRBackups: Bool) {
            self.hasSVRBackups = hasSVRBackups
        }

        var requestParameters: [String: NSNumber] {
            let jsonData = try! JSONEncoder().encode(self)
            return try! JSONSerialization.jsonObject(with: jsonData) as! [String: NSNumber]
        }
    }
}
