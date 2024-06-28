//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation

public enum DisplayName {
    case nickname(ProfileName)
    case systemContactName(SystemContactName)
    case profileName(PersonNameComponents)
    case phoneNumber(E164)
    case username(String)
    case deletedAccount
    case unknown

    public struct SystemContactName {
        public let nameComponents: PersonNameComponents
        public let multipleAccountLabel: String?

        public init(nameComponents: PersonNameComponents, multipleAccountLabel: String?) {
            self.nameComponents = nameComponents
            self.multipleAccountLabel = multipleAccountLabel?.nilIfEmpty
        }

        public func resolvedValue(config: Config = .current(), useShortNameIfAvailable: Bool = false) -> String {
            return DisplayName.formatNameComponents(
                nameComponents,
                multipleAccountLabel: multipleAccountLabel,
                config: config,
                formatBlock: useShortNameIfAvailable ? OWSFormat.formatNameComponentsShort(_:) : OWSFormat.formatNameComponents(_:)
            ).filterForDisplay
        }
    }

    public var hasKnownValue: Bool {
        switch self {
        case .nickname, .systemContactName, .profileName, .phoneNumber, .username:
            return true
        case .deletedAccount, .unknown:
            return false
        }
    }

    public func resolvedValue(config: Config = .current(), useShortNameIfAvailable: Bool = false) -> String {
        switch self {
        case .nickname(let nickname):
            return Self.formatNameComponents(
                nickname.nameComponents,
                multipleAccountLabel: nil,
                config: config,
                formatBlock: useShortNameIfAvailable ? OWSFormat.formatNameComponentsShort(_:) : OWSFormat.formatNameComponents(_:)
            )
        case .systemContactName(let systemContactName):
            return systemContactName.resolvedValue(config: config, useShortNameIfAvailable: useShortNameIfAvailable)
        case .profileName(let nameComponents):
            return Self.formatNameComponents(
                nameComponents,
                multipleAccountLabel: nil,
                config: config,
                formatBlock: useShortNameIfAvailable ? OWSFormat.formatNameComponentsShort(_:) : OWSFormat.formatNameComponents(_:)
            ).filterForDisplay
        case .phoneNumber(let phoneNumber):
            return phoneNumber.stringValue
        case .username(let username):
            return username
        case .deletedAccount:
            return OWSLocalizedString("DELETED_USER", comment: "Label indicating a user who deleted their account.")
        case .unknown:
            return CommonStrings.unknownUser
        }
    }

    public struct Config {
        public let shouldUseSystemContactNicknames: Bool

        public static func current() -> Self {
            return Config(shouldUseSystemContactNicknames: SignalAccount.shouldUseNicknames())
        }
    }

    private static func formatNameComponents(
        _ nameComponents: PersonNameComponents,
        multipleAccountLabel: String?,
        config: Config,
        formatBlock: (PersonNameComponents) -> String
    ) -> String {
        let formattedName: String = {
            if config.shouldUseSystemContactNicknames, let nickname = nameComponents.nickname {
                return nickname
            } else {
                return formatBlock(nameComponents)
            }
        }()
        if let multipleAccountLabel {
            return "\(formattedName) (\(multipleAccountLabel))"
        } else {
            return formattedName
        }
    }

    public func comparableValue(config: ComparableValue.Config = .current()) -> ComparableValue {
        func formatForSorting(_ nameComponents: PersonNameComponents) -> String {
            let components = [
                config.shouldSortByGivenName ? nameComponents.givenName : nameComponents.familyName,
                config.shouldSortByGivenName ? nameComponents.familyName : nameComponents.givenName,
            ].compacted()
            if !components.isEmpty {
                return components.joined(separator: "\t")
            }
            return OWSFormat.formatNameComponents(nameComponents)
        }

        switch self {
        case .nickname(let nickname):
            return .nameValue(Self.formatNameComponents(
                nickname.nameComponents,
                multipleAccountLabel: nil,
                config: config.displayNameConfig,
                formatBlock: formatForSorting(_:)
            ))
        case .systemContactName(let systemContactName):
            return .nameValue(Self.formatNameComponents(
                systemContactName.nameComponents,
                multipleAccountLabel: systemContactName.multipleAccountLabel,
                config: config.displayNameConfig,
                formatBlock: formatForSorting(_:)
            ))
        case .profileName(let nameComponents):
            return .nameValue(Self.formatNameComponents(
                nameComponents,
                multipleAccountLabel: nil,
                config: config.displayNameConfig,
                formatBlock: formatForSorting(_:)
            ))
        case .phoneNumber(let phoneNumber):
            return .phoneNumber(phoneNumber.stringValue)
        case .username(let username):
            return .nameValue(username)
        case .unknown, .deletedAccount:
            return .other
        }
    }

    public enum ComparableValue {
        case nameValue(String)
        case phoneNumber(String)
        case other

        public func isLessThanOrNilIfEqual(_ otherValue: Self) -> Bool? {
            switch (self, otherValue) {
            case (.nameValue(let lhs), .nameValue(let rhs)):
                switch lhs.localizedCaseInsensitiveCompare(rhs) {
                case .orderedAscending:
                    return true
                case .orderedDescending:
                    return false
                case .orderedSame:
                    return nil
                }
            case (.nameValue, _):
                return true
            case (_, .nameValue):
                return false

            case (.phoneNumber(let lhs), .phoneNumber(let rhs)):
                return (lhs == rhs) ? nil : (lhs < rhs)
            case (.phoneNumber, _):
                return true
            case (_, .phoneNumber):
                return false

            case (.other, .other):
                return nil
            }
        }

        public struct Config {
            public let displayNameConfig: DisplayName.Config
            public let shouldSortByGivenName: Bool

            public static func current() -> Self {
                return Config(
                    displayNameConfig: .current(),
                    shouldSortByGivenName: CNContactsUserDefaults.shared().sortOrder == .givenName
                )
            }
        }
    }
}

public struct ComparableDisplayName {
    public let address: SignalServiceAddress
    public let displayName: DisplayName
    public let comparableValue: DisplayName.ComparableValue
    private let comparableIdentifier: String
    private let config: DisplayName.ComparableValue.Config

    public init(
        address: SignalServiceAddress,
        displayName: DisplayName,
        config: DisplayName.ComparableValue.Config
    ) {
        self.address = address
        self.displayName = displayName
        self.comparableValue = displayName.comparableValue(config: config)
        self.comparableIdentifier = address.stringForDisplay
        self.config = config
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        return (
            lhs.comparableValue.isLessThanOrNilIfEqual(rhs.comparableValue)
            ?? (lhs.comparableIdentifier < rhs.comparableIdentifier)
        )
    }

    public func resolvedValue(useShortNameIfAvailable: Bool = false) -> String {
        return displayName.resolvedValue(
            config: config.displayNameConfig,
            useShortNameIfAvailable: useShortNameIfAvailable
        )
    }
}

public class CollatableComparableDisplayName: NSObject {
    private let rawValue: ComparableDisplayName

    public init(_ rawValue: ComparableDisplayName) {
        self.rawValue = rawValue
    }

    @objc
    public func collationString() -> String {
        switch rawValue.comparableValue {
        case .nameValue(let stringValue):
            return stringValue
        case .phoneNumber(let stringValue):
            return stringValue
        case .other:
            return ""
        }
    }
}
