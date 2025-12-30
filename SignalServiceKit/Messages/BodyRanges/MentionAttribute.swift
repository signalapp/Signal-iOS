//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

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

protocol MentionAttribute: Equatable, Hashable {

    /// Externally: identifies a single mention range, even if multiple mentions with
    /// the same uuid exist in the same message.
    ///
    /// Really this is just the original range of the mention, hashed. But that detail is
    /// irrelevant to everthing outside of this class.
    var id: MentionIDType { get }
    var mentionAci: Aci { get }
}

struct UnhydratedMentionAttribute: MentionAttribute {

    let id: MentionIDType
    let mentionAci: Aci

    static func fromOriginalRange(_ range: NSRange, mentionAci: Aci) -> Self {
        var hasher = Hasher()
        hasher.combine(range)
        let id = hasher.finalize()
        return .init(id: id, mentionAci: mentionAci)
    }

    private init(id: MentionIDType, mentionAci: Aci) {
        self.id = id
        self.mentionAci = mentionAci
    }
}

struct HydratedMentionAttribute: MentionAttribute {

    let id: MentionIDType
    let mentionAci: Aci
    /// Name without the prefix.
    let displayName: String

    static func fromOriginalRange(
        _ range: NSRange,
        mentionAci: Aci,
        displayName: String,
    ) -> Self {
        var hasher = Hasher()
        hasher.combine(range)
        let id = hasher.finalize()
        return .init(id: id, mentionAci: mentionAci, displayName: displayName)
    }

    private init(
        id: MentionIDType,
        mentionAci: Aci,
        displayName: String,
    ) {
        self.id = id
        self.mentionAci = mentionAci
        self.displayName = displayName
    }

    func applyAttributes(
        to string: NSMutableAttributedString,
        at range: NSRange,
        config: MentionDisplayConfiguration,
        isDarkThemeEnabled: Bool,
    ) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: config.font,
            .foregroundColor: config.foregroundColor.color(isDarkThemeEnabled: isDarkThemeEnabled),
        ]
        if let backgroundColor = config.backgroundColor {
            attributes[.backgroundColor] = backgroundColor.color(isDarkThemeEnabled: isDarkThemeEnabled)
        }
        string.addAttributes(attributes, range: range)
    }
}
