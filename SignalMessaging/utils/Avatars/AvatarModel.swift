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
    case theme1
    case theme2
    case theme3
    case theme4
    case theme5
    case theme6
    case theme7
    case theme8
    case theme9
    case theme10
    case theme11
    case theme12

    // TODO: final colors + names

    public var foregroundColor: UIColor {
        switch self {
        case .theme1: return UIColor(rgbHex: 0x2E51FF)
        case .theme2: return UIColor(rgbHex: 0x006DA3)
        case .theme3: return UIColor(rgbHex: 0x077D92)
        case .theme4: return UIColor(rgbHex: 0x067906)
        case .theme5: return UIColor(rgbHex: 0x8F2AF4)
        case .theme6: return UIColor(rgbHex: 0xCC0066)
        case .theme7: return UIColor(rgbHex: 0xB814B8)
        case .theme8: return UIColor(rgbHex: 0xC13215)
        case .theme9: return UIColor(rgbHex: 0xA19A58)
        case .theme10: return UIColor(rgbHex: 0x6B6B24)
        case .theme11: return UIColor(rgbHex: 0x5B6976)
        case .theme12: return UIColor(rgbHex: 0x848484)
        }
    }

    public var backgroundColor: UIColor {
        switch self {
        case .theme1: return UIColor(rgbHex: 0xDEE3FF)
        case .theme2: return UIColor(rgbHex: 0xC2DCE9)
        case .theme3: return UIColor(rgbHex: 0xC3E0E5)
        case .theme4: return UIColor(rgbHex: 0xC3DFC3)
        case .theme5: return UIColor(rgbHex: 0xE4CCFC)
        case .theme6: return UIColor(rgbHex: 0xF3C2DA)
        case .theme7: return UIColor(rgbHex: 0xEEC7EE)
        case .theme8: return UIColor(rgbHex: 0xF0CEC7)
        case .theme9: return UIColor(rgbHex: 0xFCF6C4)
        case .theme10: return UIColor(rgbHex: 0xDBDBCA)
        case .theme11: return UIColor(rgbHex: 0xD8DBDE)
        case .theme12: return UIColor(rgbHex: 0xEDEDED)
        }
    }
}

// MARK: - Avatar Colors

public extension AvatarTheme {
    static var `default`: AvatarTheme { .theme1 }

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
