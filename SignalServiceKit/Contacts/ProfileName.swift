//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct ProfileName {
    public typealias NameComponent = OWSUserProfile.NameComponent

    public var givenNameComponent: NameComponent?
    public var familyNameComponent: NameComponent?

    public var givenName: String? {
        givenNameComponent?.stringValue.rawValue
    }

    public var familyName: String? {
        familyNameComponent?.stringValue.rawValue
    }

    public init?(nicknameRecord: NicknameRecord?) {
        guard let nicknameRecord else { return nil }
        self.init(
            givenName: nicknameRecord.givenName,
            familyName: nicknameRecord.familyName
        )
    }

    public init?(givenName: String?, familyName: String?) {
        switch Self.createNameFrom(givenName: givenName, familyName: familyName) {
        case .failure(_):
            return nil
        case .success(let profileName):
            self = profileName
        }
    }

    private init(givenName: NameComponent?, familyName: NameComponent?) {
        self.givenNameComponent = givenName
        self.familyNameComponent = familyName
    }

    public enum Failure: Error {
        case givenNameTooLong
        case familyNameTooLong
        case nameEmpty
    }

    public static func createNameFrom(
        givenName: String?,
        familyName: String?
    ) -> Result<ProfileName, Failure> {
        let givenNameComponent = givenName.flatMap(NameComponent.parse(truncating:))
        if let givenNameComponent, givenNameComponent.didTruncate {
            return .failure(.givenNameTooLong)
        }

        let familyNameComponent = familyName.flatMap(NameComponent.parse(truncating:))
        if let familyNameComponent, familyNameComponent.didTruncate {
            return .failure(.familyNameTooLong)
        }

        if givenNameComponent == nil && familyNameComponent == nil {
            return .failure(.nameEmpty)
        }

        return .success(.init(
            givenName: givenNameComponent?.nameComponent,
            familyName: familyNameComponent?.nameComponent
        ))
    }

    public var nameComponents: PersonNameComponents {
        var components = PersonNameComponents()
        components.givenName = self.givenName
        components.familyName = self.familyName
        return components
    }
}
