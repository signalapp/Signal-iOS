//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

struct ProfileName {
    typealias NameComponent = OWSUserProfile.NameComponent

    var givenNameComponent: NameComponent
    var familyNameComponent: NameComponent?

    var givenName: String {
        givenNameComponent.stringValue.rawValue
    }

    var familyName: String? {
        familyNameComponent?.stringValue.rawValue
    }

    init?(givenName: String?, familyName: String?) {
        switch Self.createNameFrom(givenName: givenName, familyName: familyName) {
        case .failure(_):
            return nil
        case .success(let profileName):
            self = profileName
        }
    }

    private init(givenName: NameComponent, familyName: NameComponent?) {
        self.givenNameComponent = givenName
        self.familyNameComponent = familyName
    }

    enum Failure: Error {
        case givenNameMissing
        case givenNameTooLong
        case familyNameTooLong
    }

    static func createNameFrom(
        givenName: String?,
        familyName: String?
    ) -> Result<ProfileName, Failure> {
        guard let (givenName, didTruncateGivenName) = givenName.flatMap(NameComponent.parse(truncating:)) else {
            return .failure(.givenNameMissing)
        }

        if didTruncateGivenName {
            return .failure(.givenNameTooLong)
        }

        let familyNameComponent = familyName.flatMap(NameComponent.parse(truncating:))
        if let familyNameComponent, familyNameComponent.didTruncate {
            return .failure(.familyNameTooLong)
        }

        return .success(.init(givenName: givenName, familyName: familyNameComponent?.nameComponent))
    }
}
