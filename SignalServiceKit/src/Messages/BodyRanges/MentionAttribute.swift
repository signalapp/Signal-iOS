//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public typealias MentionIDType = Int

// Note that this struct gets put into NSAttributedString,
// so we want it to mostly contain simple types and not
// hold references to other objects, as a string holding
// a reference to the outside world is very likely to cause
// surprises.
public struct MentionDisplayConfiguration: Equatable {
    public let font: UIFont
    public let foregroundColor: ThemedColor
    public let backgroundColor: ThemedColor?

    public init(font: UIFont, foregroundColor: ThemedColor, backgroundColor: ThemedColor?) {
        self.font = font
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }
}

public enum Mention {
    public static let prefix = "@"
}

internal protocol MentionAttribute: Equatable, Hashable {

    /// Externally: identifies a single mention range, even if multiple mentions with
    /// the same uuid exist in the same message.
    ///
    /// Really this is just the original range of the mention, hashed. But that detail is
    /// irrelevant to everthing outside of this class.
    var id: MentionIDType { get }
    var mentionUuid: UUID { get }
}

internal struct UnhydratedMentionAttribute: MentionAttribute {

    internal let id: MentionIDType
    internal let mentionUuid: UUID

    internal static func fromOriginalRange(_ range: NSRange, mentionUuid: UUID) -> Self {
        var hasher = Hasher()
        hasher.combine(range)
        let id = hasher.finalize()
        return .init(id: id, mentionUuid: mentionUuid)
    }

    private init(id: MentionIDType, mentionUuid: UUID) {
        self.id = id
        self.mentionUuid = mentionUuid
    }
}

internal struct HydratedMentionAttribute: MentionAttribute {

    internal let id: MentionIDType
    internal let mentionUuid: UUID
    /// Name without the prefix.
    internal let displayName: String

    internal static func fromOriginalRange(
        _ range: NSRange,
        mentionUuid: UUID,
        displayName: String
    ) -> Self {
        var hasher = Hasher()
        hasher.combine(range)
        let id = hasher.finalize()
        return .init(id: id, mentionUuid: mentionUuid, displayName: displayName)
    }

    private init(
        id: MentionIDType,
        mentionUuid: UUID,
        displayName: String
    ) {
        self.id = id
        self.mentionUuid = mentionUuid
        self.displayName = displayName
    }

    internal func applyAttributes(
        to string: NSMutableAttributedString,
        at range: NSRange,
        config: MentionDisplayConfiguration,
        isDarkThemeEnabled: Bool
    ) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: config.font,
            .foregroundColor: config.foregroundColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
        ]
        if let backgroundColor = config.backgroundColor {
            attributes[.backgroundColor] = backgroundColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
        }
        string.addAttributes(attributes, range: range)
    }
}
