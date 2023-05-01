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

// TODO[TextFormatting]: as part of send support changes, stop exposing
// this class and mention prefix.
public struct MentionAttribute: Equatable, Hashable {

    public static let mentionPrefix = "@"

    /// Externally: identifies a single mention range, even if multiple mentions with
    /// the same uuid exist in the same message.
    ///
    /// Really this is just the original range of the mention, hashed. But that detail is
    /// irrelevant to everthing outside of this class.
    internal let id: MentionIDType
    internal let mentionUuid: UUID

    private static let key = NSAttributedString.Key("OWSMention")
    private static let displayConfigKey = NSAttributedString.Key("OWSMention.displayConfig")

    internal static func extractFromAttributes(
        _ attrs: [NSAttributedString.Key: Any]
    ) -> (MentionAttribute, MentionDisplayConfiguration?)? {
        guard let attribute = (attrs[Self.key] as? MentionAttribute) else {
            return nil
        }
        return (attribute, attrs[Self.displayConfigKey] as? MentionDisplayConfiguration)
    }

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

    internal func applyAttributes(
        to string: NSMutableAttributedString,
        at range: NSRange,
        config: MentionDisplayConfiguration,
        isDarkThemeEnabled: Bool
    ) {
        var attributes: [NSAttributedString.Key: Any] = [
            Self.key: self,
            Self.displayConfigKey: config,
            .font: config.font,
            .foregroundColor: config.foregroundColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
        ]
        if let backgroundColor = config.backgroundColor {
            attributes[.backgroundColor] = backgroundColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
        }
        string.addAttributes(attributes, range: range)
    }
}
