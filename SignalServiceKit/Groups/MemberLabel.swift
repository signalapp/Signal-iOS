//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import UIKit

/// Used for rendering a member label in the UI.
/// Label is the full member label string, including an optional emoji.
public struct MemberLabelForRendering {
    public let label: String
    public let groupNameColor: UIColor

    public init(label: String, groupNameColor: UIColor) {
        self.label = label
        self.groupNameColor = groupNameColor
    }
}

public struct MemberLabel: Codable, Equatable {
    public let label: String
    public let labelEmoji: String?

    public init(label: String, labelEmoji: String?) {
        self.label = label
        self.labelEmoji = labelEmoji
    }

    public func labelForRendering() -> String {
        if let labelEmoji {
            return labelEmoji + " " + label
        }
        return label
    }
}
