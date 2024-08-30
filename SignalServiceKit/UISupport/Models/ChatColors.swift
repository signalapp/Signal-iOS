//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents the chat color chosen for a particular scope.
///
/// Possible scopes (ordered by priority):
/// (1) Thread: Applies to a specific conversation.
/// (2) Global: Applies to all other conversations.
///
/// On its own, a `ChatColorSetting` may not contain enough information to
/// compute the color to use for a particular conversation. To compute the
/// color to use, you generally need the `ChatColorSetting` for both scopes,
/// the `Wallpaper` for both scopes (which may have their own preferred
/// color), and the default fallback.
public enum ChatColorSetting: Equatable {
    case auto
    case builtIn(PaletteChatColor)
    case custom(CustomChatColor.Key, CustomChatColor)

    public static func == (lhs: ChatColorSetting, rhs: ChatColorSetting) -> Bool {
        switch (lhs, rhs) {
        case (.auto, .auto):
            return true
        case (.builtIn(let lhs), .builtIn(let rhs)) where lhs.rawValue == rhs.rawValue:
            return true
        case (.custom(let lhs, _), .custom(let rhs, _)) where lhs.rawValue == rhs.rawValue:
            return true
        default:
            return false
        }
    }

    public var constantColor: ColorOrGradientSetting? {
        switch self {
        case .auto:
            return nil
        case .builtIn(let value):
            return value.colorSetting
        case .custom(_, let value):
            return value.colorSetting
        }
    }
}

public struct CustomChatColor: Codable {
    public struct Key: Hashable {
        public let rawValue: String

        public static func generateRandom() -> Self {
            return Key(rawValue: UUID().uuidString)
        }

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public let colorSetting: ColorOrGradientSetting
    public let creationTimestamp: UInt64

    public init(colorSetting: ColorOrGradientSetting, creationTimestamp: UInt64) {
        self.colorSetting = colorSetting
        self.creationTimestamp = creationTimestamp
    }

    private enum CodingKeys: String, CodingKey {
        case colorSetting = "setting"
        case creationTimestamp

        // Deprecated keys that may still exist in values stored in the database:
        // - "id"
        // - "isBuiltIn"
        // - "updateTimestamp"
    }
}

public enum PaletteChatColor: String, CaseIterable {
    // Default
    case ultramarine = "Ultramarine"

    // Solid Colors
    case crimson = "Crimson"
    case vermilion = "Vermilion"
    case burlap = "Burlap"
    case forest = "Forest"
    case wintergreen = "Wintergreen"
    case teal = "Teal"
    case blue = "Blue"
    case indigo = "Indigo"
    case violet = "Violet"
    case plum = "Plum"
    case taupe = "Taupe"
    case steel = "Steel"

    // Gradients
    case ember = "Ember"
    case midnight = "Midnight"
    case infrared = "Infrared"
    case lagoon = "Lagoon"
    case fluorescent = "Fluorescent"
    case basil = "Basil"
    case sublime = "Sublime"
    case sea = "Sea"
    case tangerine = "Tangerine"
}
