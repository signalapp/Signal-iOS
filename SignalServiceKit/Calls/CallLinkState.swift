//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalRingRTC

public struct CallLinkState {
    public let name: String?
    public let requiresAdminApproval: Bool
    public let revoked: Bool
    public let expiration: Date

    public enum Constants {
        public static let defaultRequiresAdminApproval = true
    }

    init(name: String?, requiresAdminApproval: Bool, revoked: Bool, expiration: Date) {
        self.name = name
        self.requiresAdminApproval = requiresAdminApproval
        self.revoked = revoked
        self.expiration = expiration
    }

    public init(_ rawValue: SignalRingRTC.CallLinkState) {
        self.name = rawValue.name.nilIfEmpty
        self.requiresAdminApproval = {
            switch rawValue.restrictions {
            case .adminApproval: return true
            case .none, .unknown: return false
            }
        }()
        self.revoked = rawValue.revoked
        self.expiration = rawValue.expiration
    }

    public var localizedName: String {
        return self.name ?? Self.defaultLocalizedName
    }

    public static var defaultLocalizedName: String {
        return CallStrings.signalCall
    }
}

extension Optional<CallLinkState> {
    public var localizedName: String {
        return self?.localizedName ?? CallLinkState.defaultLocalizedName
    }
}
