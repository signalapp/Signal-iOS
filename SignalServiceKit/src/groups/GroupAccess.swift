//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum GroupV2Access: UInt, Codable, CustomStringConvertible {
    case unknown = 0
    case any
    case member
    case administrator
    case unsatisfiable

    public static func access(forProtoAccess value: GroupsProtoAccessControlAccessRequired) -> GroupV2Access {
        switch value {
        case .any:
            return .any
        case .member:
            return .member
        case .administrator:
            return .administrator
        case .unsatisfiable:
            return .unsatisfiable
        default:
            return .unknown
        }
    }

    public var protoAccess: GroupsProtoAccessControlAccessRequired {
        switch self {
        case .any:
            return .any
        case .member:
            return .member
        case .administrator:
            return .administrator
        case .unsatisfiable:
            return .unsatisfiable
        default:
            return .unknown
        }
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        get {
            switch self {
            case .unknown:
                return "unknown"
            case .any:
                return "any"
            case .member:
                return "member"
            case .administrator:
                return "administrator"
            case .unsatisfiable:
                return "unsatisfiable"
            }
        }
    }
}

// MARK: -

// This class is immutable.
@objc
public class GroupAccess: MTLModel {
    @objc
    public var members: GroupV2Access = .unknown
    @objc
    public var attributes: GroupV2Access = .unknown
    @objc
    public var addFromInviteLink: GroupV2Access = .unknown

    public init(members: GroupV2Access,
                attributes: GroupV2Access,
                addFromInviteLink: GroupV2Access) {

        // Ensure we always have valid values.
        self.members = Self.filter(forMembers: members)
        self.attributes = Self.filter(forAttributes: attributes)
        self.addFromInviteLink = Self.filter(forAddFromInviteLink: addFromInviteLink)

        super.init()
    }

    public static func filter(forMembers value: GroupV2Access) -> GroupV2Access {
        switch value {
        case .member, .administrator:
            return value
        default:
            owsFailDebug("Invalid access level: \(value)")
            return .unknown
        }
    }

    public static func filter(forAttributes value: GroupV2Access) -> GroupV2Access {
        switch value {
        case .member, .administrator:
            return value
        default:
            owsFailDebug("Invalid access level: \(value)")
            return .unknown
        }
    }

    public static func filter(forAddFromInviteLink value: GroupV2Access) -> GroupV2Access {
        switch value {
        case .unknown:
            // .unknown is valid for groups created before group links were added.
            return value
        case .unsatisfiable, .administrator, .any:
            return value
        default:
            owsFailDebug("Invalid access level: \(value)")
            return .unknown
        }
    }

    @objc
    public override init() {
        super.init()
    }

    @objc
    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    @objc
    public static var allAccess: GroupAccess {
        return GroupAccess(members: .member, attributes: .member, addFromInviteLink: .any)
    }

    @objc
    public static var adminOnly: GroupAccess {
        return GroupAccess(members: .administrator, attributes: .administrator, addFromInviteLink: .administrator)
    }

    @objc
    public static var defaultForV1: GroupAccess {
        return GroupAccess(members: .member, attributes: .member, addFromInviteLink: .unsatisfiable)
    }

    @objc
    public static var defaultForV2: GroupAccess {
        return GroupAccess(members: .member, attributes: .member, addFromInviteLink: .unsatisfiable)
    }

    public override var debugDescription: String {
        return "[members: \(members), attributes: \(attributes), addFromInviteLink: \(addFromInviteLink), ]"
    }
}

// MARK: -

@objc
public extension GroupAccess {
    var canJoinFromInviteLink: Bool {
        // TODO: Should this include .member?
        (addFromInviteLink == .any ||
            addFromInviteLink == .administrator)
    }
}
