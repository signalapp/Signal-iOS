//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum GroupV2Access: UInt, Codable {
    case unknown = 0
    case any
    case member
    case administrator

    var description: String {
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

    public init(members: GroupV2Access,
                attributes: GroupV2Access) {
        self.members = members
        self.attributes = attributes

        super.init()
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
        return GroupAccess(members: .any, attributes: .any)
    }

    @objc
    public static var adminOnly: GroupAccess {
        return GroupAccess(members: .administrator, attributes: .administrator)
    }

    @objc
    public static var defaultForV1: GroupAccess {
        return allAccess
    }

    @objc
    public static var defaultForV2: GroupAccess {
        return GroupAccess(members: .member, attributes: .member)
    }

    public class func groupV2Access(forProtoAccess value: GroupsProtoAccessControlAccessRequired) -> GroupV2Access {
        switch value {
        case .any:
            return .any
        case .member:
            return .member
        case .administrator:
            return .administrator
        default:
            return .unknown
        }
    }

    public class func protoAccess(forGroupV2Access value: GroupV2Access) -> GroupsProtoAccessControlAccessRequired {
        switch value {
        case .any:
            return .any
        case .member:
            return .member
        case .administrator:
            return .administrator
        default:
            return .unknown
        }
    }

    public override var debugDescription: String {
        return "[members: \(members.description), attributes: \(attributes.description), ]"
    }
}
