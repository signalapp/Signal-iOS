//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum PhoneNumberDiscoverability {
    case everybody
    case nobody

    public var isDiscoverable: Bool { self == .everybody }

    /// Helpful for Storage Service operations that use the negative.
    public var isNotDiscoverableByPhoneNumber: Bool { !isDiscoverable }
}

public protocol PhoneNumberDiscoverabilityManager {
    typealias Constants = PhoneNumberDiscoverabilityManagerConstants

    func phoneNumberDiscoverability(tx: DBReadTransaction) -> PhoneNumberDiscoverability?

    func setPhoneNumberDiscoverability(
        _ phoneNumberDiscoverability: PhoneNumberDiscoverability,
        updateAccountAttributes: Bool,
        updateStorageService: Bool,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    )
}

extension Optional where Wrapped == PhoneNumberDiscoverability {
    public var orAccountAttributeDefault: PhoneNumberDiscoverability {
        return self ?? PhoneNumberDiscoverabilityManager.Constants.discoverabilityDuringRegistration
    }

    public var orDefault: PhoneNumberDiscoverability {
        return self ?? PhoneNumberDiscoverabilityManager.Constants.discoverabilityDefault
    }
}

public enum PhoneNumberDiscoverabilityManagerConstants {
    public static let discoverabilityDefault: PhoneNumberDiscoverability = .everybody

    // If PNP is enabled, users aren't discoverable during registration. If PNP
    // is disabled, users are always discoverable.
    fileprivate static let discoverabilityDuringRegistration: PhoneNumberDiscoverability = (
        FeatureFlags.phoneNumberPrivacy ? .nobody : .everybody
    )
}
