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

    private(set) var manifest: Manifest
    private(set) var translation: Translation

    var id: String {
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
    struct Manifest: Codable {
        typealias EpochSeconds = UInt64

        /// A unique ID for this manifest.
        let id: String

        /// Priority of this megaphone relative to other remote megaphones.
        /// Higher numbers indicate greater priority.
        fileprivate(set) var priority: Int

        /// Version string representing the minimum app version for which this
        /// upgrade should be shown.
        let minAppVersion: String

        // TODO: what does this represent and how do we use it?
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
        let conditionalCheck: ConditionalCheck?

        /// Represents an action to be performed in response to user selection
        /// of the "primary" call-to-action in the presented megaphone.
        let primaryAction: Action?

        /// Represents an action to be performed in response to user selection
        /// of the "secondary" call-to-action in the presented megaphone.
        let secondaryAction: Action?

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
            secondaryAction: Action?
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
            self.secondaryAction = secondaryAction
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
            case secondaryAction
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
            secondaryAction = try container.decodeIfPresent(Action.self, forKey: .secondaryAction)
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

            if let secondaryAction = secondaryAction {
                try container.encode(secondaryAction, forKey: .secondaryAction)
            }
        }
    }
}

// MARK: - Conditional Check

extension RemoteMegaphoneModel.Manifest {
    /// Identifies a known conditional check that must be satisfied in order
    /// for this megaphone to be shown.
    enum ConditionalCheck: Codable {
        case unrecognized(conditionalId: String)

        var conditionalId: String {
            switch self {
            case .unrecognized(let conditionalId):
                return conditionalId
            }
        }

        init(fromConditionalId conditionalId: String) {
            switch conditionalId {
            default:
                self = .unrecognized(conditionalId: conditionalId)
            }
        }

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
    enum Action: Codable {
        case unrecognized(actionId: String)

        var actionId: String {
            switch self {
            case .unrecognized(let conditionalId):
                return conditionalId
            }
        }

        init(fromActionId actionId: String) {
            switch actionId {
            default:
                self = .unrecognized(actionId: actionId)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case actionId
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let actionId = try container.decode(String.self, forKey: .actionId)
            self.init(fromActionId: actionId)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(actionId, forKey: .actionId)
        }
    }
}

// MARK: - Translation

extension RemoteMegaphoneModel {
    /// Represents a localized, user-presentable description of this megaphone.
    struct Translation: Codable {
        /// A unique ID for the megaphone this translation corresponds to.
        /// Should match the ID for this translation's manifest, and must be a
        /// permissible file name.
        let id: String

        /// Localized title for this megaphone.
        fileprivate(set) var title: String

        /// Localized body for this megaphone.
        fileprivate(set) var body: String

        /// Path to a remote image asset for this megaphone.
        let imageRemoteUrlPath: String?

        /// File URL to a locally-stored image asset for this megaphone.
        private(set) var imageLocalUrl: URL?

        /// Localized text to display on the "primary" call-to-action when this
        /// megaphone is presented.
        fileprivate(set) var primaryActionText: String?

        /// Localized text to display on the "secondary" call-to-action when this
        /// megaphone is presented.
        fileprivate(set) var secondaryActionText: String?

        init(
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
