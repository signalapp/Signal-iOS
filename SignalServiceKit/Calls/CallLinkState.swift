//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalRingRTC

public struct CallLinkState {
    public let name: String?
    public let restrictions: SignalRingRTC.CallLinkState.Restrictions
    public let revoked: Bool
    public let expiration: Date

    public enum Constants {
        public static let defaultRequiresAdminApproval = true
    }

    init(name: String?, restrictions: SignalRingRTC.CallLinkState.Restrictions, revoked: Bool, expiration: Date) {
        self.name = name
        self.restrictions = restrictions
        self.revoked = revoked
        self.expiration = expiration
    }

    public init(_ rawValue: SignalRingRTC.CallLinkState) {
        self.name = rawValue.name.nilIfEmpty
        self.restrictions = rawValue.restrictions
        self.revoked = rawValue.revoked
        self.expiration = rawValue.expiration
    }

    public var requiresAdminApproval: Bool {
        switch self.restrictions {
        case .adminApproval, .unknown:
            return true
        case .none:
            return false
        }
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
