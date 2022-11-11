//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct RemoteMegaphoneModel: Codable {
    public enum CodingKeys: String, CodingKey {
        case manifest
        case translation
    }

    public private(set) var manifest: Manifest
    public private(set) var translation: Translation

    public var id: String {
        manifest.id
    }

    init(manifest: Manifest, translation: Translation) {
        self.manifest = manifest
        self.translation = translation
    }

    // MARK: - Update with refetched

    /// Update select properties when this megaphone is re-fetched from the
    /// service. For example, translations may have been updated (or be for a
    /// new locale).
    ///
    /// The properties that are updated here match those that are updated on
    /// Android.
    ///
    /// Note that image URLs are not updated, and therefore once an image has
    /// been fetched and cached for this megaphone it is immutable - if this
    /// changes in the future, ensure that previously-fetched images are handled
    /// appropriately.
    mutating func update(withRefetched newMegaphone: RemoteMegaphoneModel) {
        guard id == newMegaphone.id else {
            owsFailDebug("Attempting to update remote megaphone, but IDs do not match! Current: \(id), new: \(newMegaphone.id)")
            return
        }

        manifest.priority = newMegaphone.manifest.priority
        manifest.countries = newMegaphone.manifest.countries

        manifest.conditionalCheck = newMegaphone.manifest.conditionalCheck
        manifest.primaryAction = newMegaphone.manifest.primaryAction
        manifest.primaryActionData = newMegaphone.manifest.primaryActionData
        manifest.secondaryAction = newMegaphone.manifest.secondaryAction
        manifest.secondaryActionData = newMegaphone.manifest.secondaryActionData

        translation.title = newMegaphone.translation.title
        translation.body = newMegaphone.translation.body
        translation.primaryActionText = newMegaphone.translation.primaryActionText
        translation.secondaryActionText = newMegaphone.translation.secondaryActionText
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        manifest = try container.decode(RemoteMegaphoneModel.Manifest.self, forKey: .manifest)
        translation = try container.decode(RemoteMegaphoneModel.Translation.self, forKey: .translation)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(manifest, forKey: .manifest)
        try container.encode(translation, forKey: .translation)
    }
}

// MARK: - Manifest

extension RemoteMegaphoneModel {
    /// Represents metadata about this megaphone, such as when it should be
    /// presented and what actions it should support.
    public struct Manifest: Codable {
        typealias EpochSeconds = UInt64

        /// A unique ID for this manifest.
        let id: String

        /// Priority of this megaphone relative to other remote megaphones.
        /// Higher numbers indicate greater priority.
        fileprivate(set) var priority: Int

        /// Version string representing the minimum app version for which this
        /// upgrade should be shown.
        let minAppVersion: String

        /// A CSV string of `<country-code>:<parts-per-million>` pairs
        /// representing the fraction of users to which this megaphone should
        /// be shown, by country code.
        ///
        /// This is the same format used in remote-config country-code
        /// restrictions.
        fileprivate(set) var countries: String

        /// Epoch time before which this megaphone should not be shown.
        let dontShowBefore: EpochSeconds

        /// Epoch time after which this megaphone should not be shown.
        let dontShowAfter: EpochSeconds

        /// Number of days after this megaphone is first presented that it
        /// should continue to be shown, if the user does not interact with it.
        let showForNumberOfDays: Int

        /// Represents a condition that must be satisfied in order for this
        /// megaphone to be presented.
        fileprivate(set) var conditionalCheck: ConditionalCheck?

        /// Represents an action to be performed in response to user selection
        /// of the "primary" call-to-action in the presented megaphone.
        public fileprivate(set) var primaryAction: Action?

        /// Represents data associated with the performance of the primary
        /// action.
        fileprivate(set) var primaryActionData: ActionData?

        /// Represents an action to be performed in response to user selection
        /// of the "secondary" call-to-action in the presented megaphone.
        public fileprivate(set) var secondaryAction: Action?

        /// Represents data associated with the performance of the seocndary
        /// action.
        fileprivate(set) var secondaryActionData: ActionData?

        init(
            id: String,
            priority: Int,
            minAppVersion: String,
            countries: String,
            dontShowBefore: EpochSeconds,
            dontShowAfter: EpochSeconds,
            showForNumberOfDays: Int,
            conditionalCheck: ConditionalCheck?,
            primaryAction: Action?,
            primaryActionData: ActionData?,
            secondaryAction: Action?,
            secondaryActionData: ActionData?
        ) {
            self.id = id
            self.priority = priority
            self.minAppVersion = minAppVersion
            self.countries = countries
            self.dontShowBefore = dontShowBefore
            self.dontShowAfter = dontShowAfter
            self.showForNumberOfDays = showForNumberOfDays
            self.conditionalCheck = conditionalCheck
            self.primaryAction = primaryAction
            self.primaryActionData = primaryActionData
            self.secondaryAction = secondaryAction
            self.secondaryActionData = secondaryActionData
        }

        // MARK: Codable

        public enum CodingKeys: String, CodingKey {
            case id
            case priority
            case minAppVersion
            case countries
            case dontShowBefore
            case dontShowAfter
            case showForNumberOfDays
            case conditionalCheck
            case primaryAction
            case primaryActionData
            case secondaryAction
            case secondaryActionData
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            id = try container.decode(String.self, forKey: .id)
            priority = try container.decode(Int.self, forKey: .priority)
            minAppVersion = try container.decode(String.self, forKey: .minAppVersion)
            countries = try container.decode(String.self, forKey: .countries)
            dontShowBefore = try container.decode(EpochSeconds.self, forKey: .dontShowBefore)
            dontShowAfter = try container.decode(EpochSeconds.self, forKey: .dontShowAfter)
            showForNumberOfDays = try container.decode(Int.self, forKey: .showForNumberOfDays)

            conditionalCheck = try container.decodeIfPresent(ConditionalCheck.self, forKey: .conditionalCheck)
            primaryAction = try container.decodeIfPresent(Action.self, forKey: .primaryAction)
            primaryActionData = try container.decodeIfPresent(ActionData.self, forKey: .primaryActionData)
            secondaryAction = try container.decodeIfPresent(Action.self, forKey: .secondaryAction)
            secondaryActionData = try container.decodeIfPresent(ActionData.self, forKey: .secondaryActionData)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(id, forKey: .id)
            try container.encode(priority, forKey: .priority)
            try container.encode(minAppVersion, forKey: .minAppVersion)
            try container.encode(countries, forKey: .countries)
            try container.encode(dontShowBefore, forKey: .dontShowBefore)
            try container.encode(dontShowAfter, forKey: .dontShowAfter)
            try container.encode(showForNumberOfDays, forKey: .showForNumberOfDays)

            if let conditionalCheck = conditionalCheck {
                try container.encode(conditionalCheck, forKey: .conditionalCheck)
            }

            if let primaryAction = primaryAction {
                try container.encode(primaryAction, forKey: .primaryAction)
            }

            if let primaryActionData = primaryActionData {
                try container.encode(primaryActionData, forKey: .primaryActionData)
            }

            if let secondaryAction = secondaryAction {
                try container.encode(secondaryAction, forKey: .secondaryAction)
            }

            if let secondaryActionData = secondaryActionData {
                try container.encode(secondaryActionData, forKey: .secondaryActionData)
            }
        }
    }
}

// MARK: - Conditional Check

extension RemoteMegaphoneModel.Manifest {
    /// Identifies a known conditional check that must be satisfied in order
    /// for this megaphone to be shown.
    enum ConditionalCheck: Codable {
        case standardDonate
        case internalUser
        case unrecognized(conditionalId: String)

        var conditionalId: String {
            switch self {
            case .standardDonate:
                return "standard_donate"
            case .internalUser:
                return "internal_user"
            case .unrecognized(let conditionalId):
                return conditionalId
            }
        }

        init(fromConditionalId conditionalId: String) {
            switch conditionalId {
            case Self.standardDonate.conditionalId:
                self = .standardDonate
            case Self.internalUser.conditionalId:
                self = .internalUser
            default:
                self = .unrecognized(conditionalId: conditionalId)
            }
        }

        // MARK: Codable

        private enum CodingKeys: String, CodingKey {
            case conditionalId
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let conditionalId = try container.decode(String.self, forKey: .conditionalId)
            self.init(fromConditionalId: conditionalId)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(conditionalId, forKey: .conditionalId)
        }
    }
}

// MARK: - Action

extension RemoteMegaphoneModel.Manifest {
    /// Identifies a known action to take in response to a known user
    /// interaction with this megaphone.
    public enum Action: Codable {
        case finish
        case donate
        case snooze
        case unrecognized(actionId: String)

        var actionId: String {
            switch self {
            case .finish:
                return "finish"
            case .donate:
                return "donate"
            case .snooze:
                return "snooze"
            case .unrecognized(let conditionalId):
                return conditionalId
            }
        }

        init(fromActionId actionId: String) {
            self = {
                switch actionId {
                case Self.finish.actionId:
                    return .finish
                case Self.donate.actionId:
                    return .donate
                case Self.snooze.actionId:
                    return .snooze
                default:
                    return .unrecognized(actionId: actionId)
                }
            }()
        }

        // MARK: Codable

        private enum CodingKeys: String, CodingKey {
            case actionId
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let actionId = try container.decode(String.self, forKey: .actionId)
            self.init(fromActionId: actionId)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(actionId, forKey: .actionId)
        }
    }
}

// MARK: - ActionData

extension RemoteMegaphoneModel.Manifest {
    enum ActionData: Codable {
        case snoozeDurationDays(days: [UInt])
        case unrecognized(actionDataId: String)

        private static let snoozeDurationDaysId: String = "snoozeDurationDays"

        static func parse(fromJson jsonObject: [String: Any]) throws -> Self? {
            let parser = ParamParser(dictionary: jsonObject)

            if let snoozeDurationDays: [UInt] = try parser.optional(key: snoozeDurationDaysId) {
                return .snoozeDurationDays(days: snoozeDurationDays)
            }

            return nil
        }

        // MARK: Codable

        private enum CodingKeys: String, CodingKey {
            case actionDataId
            case associatedData
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let actionDataId = try container.decode(String.self, forKey: .actionDataId)

            self = try { () throws in
                switch actionDataId {
                case Self.snoozeDurationDaysId:
                    let days = try container.decode([UInt].self, forKey: .associatedData)
                    return .snoozeDurationDays(days: days)
                default:
                    return .unrecognized(actionDataId: actionDataId)
                }
            }()
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            let (actionDataId, associatedData): (String, Encodable?) = {
                switch self {
                case .snoozeDurationDays(let days):
                    return (Self.snoozeDurationDaysId, days)
                case .unrecognized(let actionDataId):
                    return (actionDataId, nil)
                }
            }()

            try container.encode(actionDataId, forKey: .actionDataId)

            if let associatedData = associatedData {
                try container.encode(associatedData, forKey: .associatedData)
            }
        }
    }
}

// MARK: - Translation

extension RemoteMegaphoneModel {
    /// Represents a localized, user-presentable description of this megaphone.
    public struct Translation: Codable {
        /// A unique ID for the megaphone this translation corresponds to.
        /// Should match the ID for this translation's manifest, and must be a
        /// permissible file name.
        let id: String

        /// Localized title for this megaphone.
        public fileprivate(set) var title: String

        /// Localized body for this megaphone.
        public fileprivate(set) var body: String

        /// Path to a remote image asset for this megaphone.
        let imageRemoteUrlPath: String?

        /// File URL to a locally-stored image asset for this megaphone.
        public private(set) var imageLocalUrl: URL?

        /// Localized text to display on the "primary" call-to-action when this
        /// megaphone is presented.
        public fileprivate(set) var primaryActionText: String?

        /// Localized text to display on the "secondary" call-to-action when this
        /// megaphone is presented.
        public fileprivate(set) var secondaryActionText: String?

        private init(
            id: String,
            title: String,
            body: String,
            imageRemoteUrlPath: String?,
            imageLocalUrl: URL?,
            primaryActionText: String?,
            secondaryActionText: String?
        ) {
            self.id = id
            self.title = title
            self.body = body
            self.imageRemoteUrlPath = imageRemoteUrlPath
            self.imageLocalUrl = imageLocalUrl
            self.primaryActionText = primaryActionText
            self.secondaryActionText = secondaryActionText
        }

        mutating func setImageLocalUrl(_ url: URL) {
            imageLocalUrl = url
        }

        // MARK: Factories

        public static func makeWithoutLocalImage(
            id: String,
            title: String,
            body: String,
            imageRemoteUrlPath: String?,
            primaryActionText: String?,
            secondaryActionText: String?
        ) -> Translation {
            Translation(
                id: id,
                title: title,
                body: body,
                imageRemoteUrlPath: imageRemoteUrlPath,
                imageLocalUrl: nil,
                primaryActionText: primaryActionText,
                secondaryActionText: secondaryActionText
            )
        }

        // MARK: Codable

        public enum CodingKeys: String, CodingKey {
            case id
            case title
            case body
            case imageRemoteUrlPath
            case imageLocalUrl
            case primaryActionText
            case secondaryActionText
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            body = try container.decode(String.self, forKey: .body)

            imageRemoteUrlPath = try container.decodeIfPresent(String.self, forKey: .imageRemoteUrlPath)
            imageLocalUrl = try container.decodeIfPresent(URL.self, forKey: .imageLocalUrl)
            primaryActionText = try container.decodeIfPresent(String.self, forKey: .primaryActionText)
            secondaryActionText = try container.decodeIfPresent(String.self, forKey: .secondaryActionText)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(id, forKey: .id)
            try container.encode(title, forKey: .title)
            try container.encode(body, forKey: .body)

            if let imageRemoteUrlPath = imageRemoteUrlPath {
                try container.encode(imageRemoteUrlPath, forKey: .imageRemoteUrlPath)
            }

            if let imageLocalUrl = imageLocalUrl {
                try container.encode(imageLocalUrl, forKey: .imageLocalUrl)
            }

            if let primaryActionText = primaryActionText {
                try container.encode(primaryActionText, forKey: .primaryActionText)
            }

            if let secondaryActionText = secondaryActionText {
                try container.encode(secondaryActionText, forKey: .secondaryActionText)
            }
        }
    }
}
