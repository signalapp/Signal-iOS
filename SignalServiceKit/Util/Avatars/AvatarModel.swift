//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct AvatarModel: Equatable {
    public let identifier: String
    public var type: AvatarType
    public var theme: AvatarTheme

    public init(identifier: String? = nil, type: AvatarType, theme: AvatarTheme) {
        if let identifier = identifier {
            if case .icon(let icon) = type { owsAssertDebug(identifier == icon.rawValue) }
            self.identifier = identifier
        } else {
            switch type {
            case .icon(let icon): self.identifier = icon.rawValue
            default: self.identifier = UUID().uuidString
            }
        }
        self.type = type
        self.theme = theme
    }
}

public enum AvatarType: Equatable {
    case image(URL)
    case icon(AvatarIcon)
    case text(String)

    public var isEditable: Bool {
        switch self {
        case .image: return false
        case .icon: return true
        case .text: return true
        }
    }

    public var isDeletable: Bool {
        switch self {
        case .image: return true
        case .icon: return false
        case .text: return true
        }
    }

    public static func == (lhs: AvatarType, rhs: AvatarType) -> Bool {
        switch (lhs, rhs) {
        case (.image(let lhs), .image(let rhs)):
            // We implement a custom "Equatable", since two URLs
            // are equatated with object equality, and even with
            // the same URL treated as different objects with the
            // compiler synthesized function.
            return lhs.path == rhs.path
        case (.icon(let lhs), .icon(let rhs)):
            return lhs == rhs
        case (.text(let lhs), .text(let rhs)):
            return lhs == rhs
        default: return false
        }
    }
}

public enum AvatarIcon: String, CaseIterable {
    case abstract01
    case abstract02
    case abstract03
    case cat
    case dinosaur
    case dog
    case fox
    case ghost
    case incognito
    case pig
    case sloth
    case tucan

    case heart
    case house
    case melon
    case drink
    case celebration
    case balloon
    case book
    case briefcase
    case sunset
    case surfboard
    case soccerball
    case football

    public var image: UIImage { UIImage(named: imageName)! }

    public var imageName: String { "avatar_\(rawValue)"}

    // todo: real names / final icons

    public static var defaultGroupIcons: [AvatarIcon] = [
        .heart,
        .house,
        .melon,
        .drink,
        .celebration,
        .balloon,
        .book,
        .briefcase,
        .sunset,
        .surfboard,
        .soccerball,
        .football
    ]

    public static var defaultProfileIcons: [AvatarIcon] = [
        .abstract01,
        .abstract02,
        .abstract03,
        .cat,
        .dog,
        .fox,
        .tucan,
        .sloth,
        .dinosaur,
        .pig,
        .incognito,
        .ghost
    ]
}

public enum AvatarTheme: String, CaseIterable {
    case A100
    case A110
    case A120
    case A130
    case A140
    case A150
    case A160
    case A170
    case A180
    case A190
    case A200
    case A210

    public var foregroundColor: UIColor {
        switch self {
        case .A100: return UIColor(rgbHex: 0x3838F5)
        case .A110: return UIColor(rgbHex: 0x1251D3)
        case .A120: return UIColor(rgbHex: 0x086DA0)
        case .A130: return UIColor(rgbHex: 0x067906)
        case .A140: return UIColor(rgbHex: 0x661AFF)
        case .A150: return UIColor(rgbHex: 0x9F00F0)
        case .A160: return UIColor(rgbHex: 0xB8057C)
        case .A170: return UIColor(rgbHex: 0xBE0404)
        case .A180: return UIColor(rgbHex: 0x836B01)
        case .A190: return UIColor(rgbHex: 0x7D6F40)
        case .A200: return UIColor(rgbHex: 0x4F4F6D)
        case .A210: return UIColor(rgbHex: 0x5C5C5C)
        }
    }

    public var backgroundColor: UIColor {
        switch self {
        case .A100: return UIColor(rgbHex: 0xE3E3FE)
        case .A110: return UIColor(rgbHex: 0xDDE7FC)
        case .A120: return UIColor(rgbHex: 0xD8E8F0)
        case .A130: return UIColor(rgbHex: 0xCDE4CD)
        case .A140: return UIColor(rgbHex: 0xEAE0FD)
        case .A150: return UIColor(rgbHex: 0xF5E3FE)
        case .A160: return UIColor(rgbHex: 0xF6D8EC)
        case .A170: return UIColor(rgbHex: 0xF5D7D7)
        case .A180: return UIColor(rgbHex: 0xFEF5D0)
        case .A190: return UIColor(rgbHex: 0xEAE6D5)
        case .A200: return UIColor(rgbHex: 0xD2D2DC)
        case .A210: return UIColor(rgbHex: 0xD7D7D9)
        }
    }
}

// MARK: - Avatar Colors

public extension AvatarTheme {
    static var `default`: AvatarTheme { .A100 }

    static func forThread(_ thread: TSThread) -> AvatarTheme {
        if let contactThread = thread as? TSContactThread {
            return forAddress(contactThread.contactAddress)
        } else if let groupThread = thread as? TSGroupThread {
            return forGroupId(groupThread.groupId)
        } else {
            owsFailDebug("Invalid thread.")
            return Self.default
        }
    }

    static func forGroupModel(_ groupModel: TSGroupModel) -> AvatarTheme {
        forGroupId(groupModel.groupId)
    }

    static func forGroupId(_ groupId: Data) -> AvatarTheme {
        forData(groupId)
    }

    static func forAddress(_ address: SignalServiceAddress) -> AvatarTheme {
        guard let seed = address.serviceIdentifier else {
            owsFailDebug("Missing serviceIdentifier.")
            return Self.default
        }
        return forSeed(seed)
    }

    static func forSeed(_ seed: String) -> AvatarTheme {
        guard let data = seed.data(using: .utf8) else {
            owsFailDebug("Invalid seed.")
            return Self.default
        }
        return forData(data)
    }

    static func forIcon(_ icon: AvatarIcon) -> AvatarTheme {
        switch icon {
        case .abstract01: return .A130
        case .abstract02: return .A120
        case .abstract03: return .A170
        case .cat: return .A190
        case .dog: return .A140
        case .fox: return .A190
        case .tucan: return .A120
        case .sloth: return .A160
        case .dinosaur: return .A130
        case .pig: return .A180
        case .incognito: return .A210
        case .ghost: return .A100
        case .heart: return .A180
        case .house: return .A120
        case .melon: return .A110
        case .drink: return .A170
        case .celebration: return .A100
        case .balloon: return .A210
        case .book: return .A100
        case .briefcase: return .A180
        case .sunset: return .A120
        case .surfboard: return .A110
        case .soccerball: return .A130
        case .football: return .A210
        }
    }

    private static func forData(_ data: Data) -> AvatarTheme {
        var hash: UInt = 0
        for value in data {
            // A primitive hashing function.
            // We only require it to be stable and fast.
            hash = hash.rotateLeft(3) ^ UInt(value)
        }
        let values = AvatarTheme.allCases
        guard let value = values[safe: Int(hash % UInt(values.count))] else {
            owsFailDebug("Could not determine avatar color.")
            return Self.default
        }
        return value
    }
}

// MARK: -

extension UInt {
    public static let is64bit = { UInt.bitWidth == UInt64.bitWidth }()
    public static let is32bit = { UInt.bitWidth == UInt32.bitWidth }()

    public static let highestBit: UInt = {
        if is32bit {
            return UInt(1).rotateLeft(31)
        } else if is64bit {
            return UInt(1).rotateLeft(63)
        } else {
            owsFail("Unexpected UInt width.")
        }
    }()

    // <<<
    public func rotateLeft(_ count: Int) -> UInt {
        let count = count % UInt.bitWidth
        return (self << count) | (self >> (UInt.bitWidth - count))
    }
}
