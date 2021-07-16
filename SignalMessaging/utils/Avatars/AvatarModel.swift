//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
}

public enum AvatarIcon: String, CaseIterable {
    case face1
    case face2
    case cat
    case fox

    public var image: UIImage { UIImage(named: imageName)! }

    public var imageName: String {
        switch self {
        case .face1: return "avatar-illustration-face1"
        case .face2: return "avatar-illustration-face2"
        case .cat: return "avatar-illustration-cat"
        case .fox: return "avatar-illustration-fox"
        }
    }

    // todo: real names / final icons

    public static var defaultGroupIcons: [AvatarIcon] = allCases

    public static var defaultProfileIcons: [AvatarIcon] = allCases
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
