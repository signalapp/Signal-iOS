//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public struct AccountIdentityResponse: Decodable {
    public struct Entitlements: Decodable {
        private enum CodingKeys: String, CodingKey {
            case backup
            case badges
        }

        public struct BackupEntitlement: Decodable {
            private enum CodingKeys: String, CodingKey {
                case backupLevel
                case expirationSeconds
            }

            public let backupLevel: Int
            public let expirationSeconds: TimeInterval
        }

        public struct BadgeEntitlement: Decodable {
            private enum CodingKeys: String, CodingKey {
                case badgeId = "id"
                case isVisible = "visible"
                case expirationSeconds
            }

            public let badgeId: String
            public let isVisible: Bool
            public let expirationSeconds: TimeInterval
        }

        public let backup: BackupEntitlement?
        public let badges: [BadgeEntitlement]

        public init() {
            self.backup = nil
            self.badges = []
        }
    }

    public let localIdentifiers: LocalIdentifiers
    public let usernameHash: String?
    public let usernameLinkHandle: UUID?
    /// Whether the account has any data in SVR.
    public let storageCapable: Bool
    public let entitlements: Entitlements

    public init(
        localIdentifiers: LocalIdentifiers,
        usernameHash: String? = nil,
        usernameLinkHandle: UUID? = nil,
        storageCapable: Bool = false,
        entitlements: Entitlements = Entitlements(),
    ) {
        self.localIdentifiers = localIdentifiers
        self.usernameHash = usernameHash
        self.usernameLinkHandle = usernameLinkHandle
        self.storageCapable = storageCapable
        self.entitlements = entitlements
    }

    public enum CodingKeys: String, CodingKey {
        case aci = "uuid"
        case pni
        case number
        case authCredentialSalt
        case storageCapable
        case usernameHash
        case usernameLinkHandle
        case entitlements
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let aci = Aci(fromUUID: try container.decode(UUID.self, forKey: .aci))
        let accountType: LocalIdentifiers.AccountType
        if let phoneNumber = try container.decodeIfPresent(E164.self, forKey: .number) {
            let pni = Pni(fromUUID: try container.decode(UUID.self, forKey: .pni))
            accountType = .phoneNumberfull(phoneNumber: phoneNumber.stringValue, pni: pni)
        } else {
            let authCredentialSalt = try container.decode(AuthCredentialSalt.self, forKey: .authCredentialSalt)
            accountType = .phoneNumberless(authCredentialSalt)
        }
        self.localIdentifiers = LocalIdentifiers(aci: aci, accountType: accountType)
        self.usernameHash = try container.decodeIfPresent(String.self, forKey: .usernameHash)
        self.usernameLinkHandle = try container.decodeIfPresent(UUID.self, forKey: .usernameLinkHandle)
        self.storageCapable = try container.decode(Bool.self, forKey: .storageCapable)
        self.entitlements = try container.decode(Entitlements.self, forKey: .entitlements)
    }
}
