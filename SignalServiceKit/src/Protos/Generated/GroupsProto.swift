//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum GroupsProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - GroupsProtoMemberRole

public enum GroupsProtoMemberRole: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case unknown // 0
    case `default` // 1
    case administrator // 2
    case UNRECOGNIZED(Int)

    public init() {
        self = .unknown
    }

    public init?(rawValue: Int) {
        switch rawValue {
            case 0: self = .unknown
            case 1: self = .`default`
            case 2: self = .administrator
            default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
            case .unknown: return 0
            case .`default`: return 1
            case .administrator: return 2
            case .UNRECOGNIZED(let i): return i
        }
    }
}

private func GroupsProtoMemberRoleWrap(_ value: GroupsProtos_Member.Role) -> GroupsProtoMemberRole {
    switch value {
    case .unknown: return .unknown
    case .default: return .default
    case .administrator: return .administrator
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

private func GroupsProtoMemberRoleUnwrap(_ value: GroupsProtoMemberRole) -> GroupsProtos_Member.Role {
    switch value {
    case .unknown: return .unknown
    case .default: return .default
    case .administrator: return .administrator
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

// MARK: - GroupsProtoMember

public class GroupsProtoMember: NSObject {

    // MARK: - GroupsProtoMemberBuilder

    public class func builder() -> GroupsProtoMemberBuilder {
        return GroupsProtoMemberBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoMemberBuilder {
        let builder = GroupsProtoMemberBuilder()
        if let _value = userID {
            builder.setUserID(_value)
        }
        if let _value = role {
            builder.setRole(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = presentation {
            builder.setPresentation(_value)
        }
        if hasJoinedAtVersion {
            builder.setJoinedAtVersion(joinedAtVersion)
        }
        return builder
    }

    public class GroupsProtoMemberBuilder: NSObject {

        private var proto = GroupsProtos_Member()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setUserID(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.userID = valueParam
        }

        public func setUserID(_ valueParam: Data) {
            proto.userID = valueParam
        }

        public func setRole(_ valueParam: GroupsProtoMemberRole) {
            proto.role = GroupsProtoMemberRoleUnwrap(valueParam)
        }

        @available(swift, obsoleted: 1.0)
        public func setProfileKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.profileKey = valueParam
        }

        public func setProfileKey(_ valueParam: Data) {
            proto.profileKey = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setPresentation(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.presentation = valueParam
        }

        public func setPresentation(_ valueParam: Data) {
            proto.presentation = valueParam
        }

        public func setJoinedAtVersion(_ valueParam: UInt32) {
            proto.joinedAtVersion = valueParam
        }

        public func build() throws -> GroupsProtoMember {
            return try GroupsProtoMember.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoMember.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_Member

    public var userID: Data? {
        guard hasUserID else {
            return nil
        }
        return proto.userID
    }
    public var hasUserID: Bool {
        return proto.userID.count > 0
    }

    public var role: GroupsProtoMemberRole? {
        guard hasRole else {
            return nil
        }
        return GroupsProtoMemberRoleWrap(proto.role)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedRole: GroupsProtoMemberRole {
        if !hasRole {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Member.role.")
        }
        return GroupsProtoMemberRoleWrap(proto.role)
    }
    public var hasRole: Bool {
        return true
    }

    public var profileKey: Data? {
        guard hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    public var hasProfileKey: Bool {
        return proto.profileKey.count > 0
    }

    public var presentation: Data? {
        guard hasPresentation else {
            return nil
        }
        return proto.presentation
    }
    public var hasPresentation: Bool {
        return proto.presentation.count > 0
    }

    public var joinedAtVersion: UInt32 {
        return proto.joinedAtVersion
    }
    public var hasJoinedAtVersion: Bool {
        return true
    }

    private init(proto: GroupsProtos_Member) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoMember {
        let proto = try GroupsProtos_Member(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_Member) throws -> GroupsProtoMember {
        // MARK: - Begin Validation Logic for GroupsProtoMember -

        // MARK: - End Validation Logic for GroupsProtoMember -

        let result = GroupsProtoMember(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoMember {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoMember.GroupsProtoMemberBuilder {
    public func buildIgnoringErrors() -> GroupsProtoMember? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoAccessControlAccessRequired

public enum GroupsProtoAccessControlAccessRequired: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case unknown // 0
    case any // 1
    case member // 2
    case administrator // 3
    case UNRECOGNIZED(Int)

    public init() {
        self = .unknown
    }

    public init?(rawValue: Int) {
        switch rawValue {
            case 0: self = .unknown
            case 1: self = .any
            case 2: self = .member
            case 3: self = .administrator
            default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
            case .unknown: return 0
            case .any: return 1
            case .member: return 2
            case .administrator: return 3
            case .UNRECOGNIZED(let i): return i
        }
    }
}

private func GroupsProtoAccessControlAccessRequiredWrap(_ value: GroupsProtos_AccessControl.AccessRequired) -> GroupsProtoAccessControlAccessRequired {
    switch value {
    case .unknown: return .unknown
    case .any: return .any
    case .member: return .member
    case .administrator: return .administrator
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

private func GroupsProtoAccessControlAccessRequiredUnwrap(_ value: GroupsProtoAccessControlAccessRequired) -> GroupsProtos_AccessControl.AccessRequired {
    switch value {
    case .unknown: return .unknown
    case .any: return .any
    case .member: return .member
    case .administrator: return .administrator
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

// MARK: - GroupsProtoAccessControl

public class GroupsProtoAccessControl: NSObject {

    // MARK: - GroupsProtoAccessControlBuilder

    public class func builder() -> GroupsProtoAccessControlBuilder {
        return GroupsProtoAccessControlBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoAccessControlBuilder {
        let builder = GroupsProtoAccessControlBuilder()
        if let _value = title {
            builder.setTitle(_value)
        }
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if let _value = members {
            builder.setMembers(_value)
        }
        return builder
    }

    public class GroupsProtoAccessControlBuilder: NSObject {

        private var proto = GroupsProtos_AccessControl()

        fileprivate override init() {}

        public func setTitle(_ valueParam: GroupsProtoAccessControlAccessRequired) {
            proto.title = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
        }

        public func setAvatar(_ valueParam: GroupsProtoAccessControlAccessRequired) {
            proto.avatar = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
        }

        public func setMembers(_ valueParam: GroupsProtoAccessControlAccessRequired) {
            proto.members = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
        }

        public func build() throws -> GroupsProtoAccessControl {
            return try GroupsProtoAccessControl.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoAccessControl.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_AccessControl

    public var title: GroupsProtoAccessControlAccessRequired? {
        guard hasTitle else {
            return nil
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.title)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedTitle: GroupsProtoAccessControlAccessRequired {
        if !hasTitle {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: AccessControl.title.")
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.title)
    }
    public var hasTitle: Bool {
        return true
    }

    public var avatar: GroupsProtoAccessControlAccessRequired? {
        guard hasAvatar else {
            return nil
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.avatar)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedAvatar: GroupsProtoAccessControlAccessRequired {
        if !hasAvatar {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: AccessControl.avatar.")
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.avatar)
    }
    public var hasAvatar: Bool {
        return true
    }

    public var members: GroupsProtoAccessControlAccessRequired? {
        guard hasMembers else {
            return nil
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.members)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedMembers: GroupsProtoAccessControlAccessRequired {
        if !hasMembers {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: AccessControl.members.")
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.members)
    }
    public var hasMembers: Bool {
        return true
    }

    private init(proto: GroupsProtos_AccessControl) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoAccessControl {
        let proto = try GroupsProtos_AccessControl(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_AccessControl) throws -> GroupsProtoAccessControl {
        // MARK: - Begin Validation Logic for GroupsProtoAccessControl -

        // MARK: - End Validation Logic for GroupsProtoAccessControl -

        let result = GroupsProtoAccessControl(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoAccessControl {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoAccessControl.GroupsProtoAccessControlBuilder {
    public func buildIgnoringErrors() -> GroupsProtoAccessControl? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroup

public class GroupsProtoGroup: NSObject {

    // MARK: - GroupsProtoGroupBuilder

    public class func builder() -> GroupsProtoGroupBuilder {
        return GroupsProtoGroupBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupBuilder {
        let builder = GroupsProtoGroupBuilder()
        if let _value = publicKey {
            builder.setPublicKey(_value)
        }
        if let _value = title {
            builder.setTitle(_value)
        }
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if let _value = accessControl {
            builder.setAccessControl(_value)
        }
        if hasVersion {
            builder.setVersion(version)
        }
        builder.setMembers(members)
        return builder
    }

    public class GroupsProtoGroupBuilder: NSObject {

        private var proto = GroupsProtos_Group()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setPublicKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.publicKey = valueParam
        }

        public func setPublicKey(_ valueParam: Data) {
            proto.publicKey = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setTitle(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.title = valueParam
        }

        public func setTitle(_ valueParam: Data) {
            proto.title = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setAvatar(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.avatar = valueParam
        }

        public func setAvatar(_ valueParam: Data) {
            proto.avatar = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setAccessControl(_ valueParam: GroupsProtoAccessControl?) {
            guard let valueParam = valueParam else { return }
            proto.accessControl = valueParam.proto
        }

        public func setAccessControl(_ valueParam: GroupsProtoAccessControl) {
            proto.accessControl = valueParam.proto
        }

        public func setVersion(_ valueParam: UInt32) {
            proto.version = valueParam
        }

        public func addMembers(_ valueParam: GroupsProtoMember) {
            var items = proto.members
            items.append(valueParam.proto)
            proto.members = items
        }

        public func setMembers(_ wrappedItems: [GroupsProtoMember]) {
            proto.members = wrappedItems.map { $0.proto }
        }

        public func build() throws -> GroupsProtoGroup {
            return try GroupsProtoGroup.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroup.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_Group

    public let accessControl: GroupsProtoAccessControl?

    public let members: [GroupsProtoMember]

    public var publicKey: Data? {
        guard hasPublicKey else {
            return nil
        }
        return proto.publicKey
    }
    public var hasPublicKey: Bool {
        return proto.publicKey.count > 0
    }

    public var title: Data? {
        guard hasTitle else {
            return nil
        }
        return proto.title
    }
    public var hasTitle: Bool {
        return proto.title.count > 0
    }

    public var avatar: Data? {
        guard hasAvatar else {
            return nil
        }
        return proto.avatar
    }
    public var hasAvatar: Bool {
        return proto.avatar.count > 0
    }

    public var version: UInt32 {
        return proto.version
    }
    public var hasVersion: Bool {
        return true
    }

    private init(proto: GroupsProtos_Group,
                 accessControl: GroupsProtoAccessControl?,
                 members: [GroupsProtoMember]) {
        self.proto = proto
        self.accessControl = accessControl
        self.members = members
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroup {
        let proto = try GroupsProtos_Group(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_Group) throws -> GroupsProtoGroup {
        var accessControl: GroupsProtoAccessControl? = nil
        if proto.hasAccessControl {
            accessControl = try GroupsProtoAccessControl.parseProto(proto.accessControl)
        }

        var members: [GroupsProtoMember] = []
        members = try proto.members.map { try GroupsProtoMember.parseProto($0) }

        // MARK: - Begin Validation Logic for GroupsProtoGroup -

        // MARK: - End Validation Logic for GroupsProtoGroup -

        let result = GroupsProtoGroup(proto: proto,
                                      accessControl: accessControl,
                                      members: members)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroup {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroup.GroupsProtoGroupBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroup? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsAddMemberAction

public class GroupsProtoGroupChangeActionsAddMemberAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsAddMemberActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsAddMemberActionBuilder {
        return GroupsProtoGroupChangeActionsAddMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsAddMemberActionBuilder {
        let builder = GroupsProtoGroupChangeActionsAddMemberActionBuilder()
        if let _value = added {
            builder.setAdded(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsAddMemberActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.AddMemberAction()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setAdded(_ valueParam: GroupsProtoMember?) {
            guard let valueParam = valueParam else { return }
            proto.added = valueParam.proto
        }

        public func setAdded(_ valueParam: GroupsProtoMember) {
            proto.added = valueParam.proto
        }

        public func build() throws -> GroupsProtoGroupChangeActionsAddMemberAction {
            return try GroupsProtoGroupChangeActionsAddMemberAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsAddMemberAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.AddMemberAction

    public let added: GroupsProtoMember?

    private init(proto: GroupsProtos_GroupChange.Actions.AddMemberAction,
                 added: GroupsProtoMember?) {
        self.proto = proto
        self.added = added
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsAddMemberAction {
        let proto = try GroupsProtos_GroupChange.Actions.AddMemberAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.AddMemberAction) throws -> GroupsProtoGroupChangeActionsAddMemberAction {
        var added: GroupsProtoMember? = nil
        if proto.hasAdded {
            added = try GroupsProtoMember.parseProto(proto.added)
        }

        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsAddMemberAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsAddMemberAction -

        let result = GroupsProtoGroupChangeActionsAddMemberAction(proto: proto,
                                                                  added: added)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsAddMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsAddMemberAction.GroupsProtoGroupChangeActionsAddMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsAddMemberAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsDeleteMemberAction

public class GroupsProtoGroupChangeActionsDeleteMemberAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsDeleteMemberActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsDeleteMemberActionBuilder {
        return GroupsProtoGroupChangeActionsDeleteMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsDeleteMemberActionBuilder {
        let builder = GroupsProtoGroupChangeActionsDeleteMemberActionBuilder()
        if let _value = deleted {
            builder.setDeleted(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsDeleteMemberActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.DeleteMemberAction()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setDeleted(_ valueParam: GroupsProtoMember?) {
            guard let valueParam = valueParam else { return }
            proto.deleted = valueParam.proto
        }

        public func setDeleted(_ valueParam: GroupsProtoMember) {
            proto.deleted = valueParam.proto
        }

        public func build() throws -> GroupsProtoGroupChangeActionsDeleteMemberAction {
            return try GroupsProtoGroupChangeActionsDeleteMemberAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsDeleteMemberAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.DeleteMemberAction

    public let deleted: GroupsProtoMember?

    private init(proto: GroupsProtos_GroupChange.Actions.DeleteMemberAction,
                 deleted: GroupsProtoMember?) {
        self.proto = proto
        self.deleted = deleted
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsDeleteMemberAction {
        let proto = try GroupsProtos_GroupChange.Actions.DeleteMemberAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.DeleteMemberAction) throws -> GroupsProtoGroupChangeActionsDeleteMemberAction {
        var deleted: GroupsProtoMember? = nil
        if proto.hasDeleted {
            deleted = try GroupsProtoMember.parseProto(proto.deleted)
        }

        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsDeleteMemberAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsDeleteMemberAction -

        let result = GroupsProtoGroupChangeActionsDeleteMemberAction(proto: proto,
                                                                     deleted: deleted)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsDeleteMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsDeleteMemberAction.GroupsProtoGroupChangeActionsDeleteMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsDeleteMemberAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyMemberRoleAction

public class GroupsProtoGroupChangeActionsModifyMemberRoleAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder {
        return GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder()
        if let _value = userID {
            builder.setUserID(_value)
        }
        if let _value = role {
            builder.setRole(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setUserID(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.userID = valueParam
        }

        public func setUserID(_ valueParam: Data) {
            proto.userID = valueParam
        }

        public func setRole(_ valueParam: GroupsProtoMemberRole) {
            proto.role = GroupsProtoMemberRoleUnwrap(valueParam)
        }

        public func build() throws -> GroupsProtoGroupChangeActionsModifyMemberRoleAction {
            return try GroupsProtoGroupChangeActionsModifyMemberRoleAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyMemberRoleAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction

    public var userID: Data? {
        guard hasUserID else {
            return nil
        }
        return proto.userID
    }
    public var hasUserID: Bool {
        return proto.userID.count > 0
    }

    public var role: GroupsProtoMemberRole? {
        guard hasRole else {
            return nil
        }
        return GroupsProtoMemberRoleWrap(proto.role)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedRole: GroupsProtoMemberRole {
        if !hasRole {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: ModifyMemberRoleAction.role.")
        }
        return GroupsProtoMemberRoleWrap(proto.role)
    }
    public var hasRole: Bool {
        return true
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyMemberRoleAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction) throws -> GroupsProtoGroupChangeActionsModifyMemberRoleAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyMemberRoleAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyMemberRoleAction -

        let result = GroupsProtoGroupChangeActionsModifyMemberRoleAction(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyMemberRoleAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyMemberRoleAction.GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyMemberRoleAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyTitleAction

public class GroupsProtoGroupChangeActionsModifyTitleAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyTitleActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsModifyTitleActionBuilder {
        return GroupsProtoGroupChangeActionsModifyTitleActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyTitleActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyTitleActionBuilder()
        if let _value = title {
            builder.setTitle(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsModifyTitleActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyTitleAction()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setTitle(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.title = valueParam
        }

        public func setTitle(_ valueParam: Data) {
            proto.title = valueParam
        }

        public func build() throws -> GroupsProtoGroupChangeActionsModifyTitleAction {
            return try GroupsProtoGroupChangeActionsModifyTitleAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyTitleAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyTitleAction

    public var title: Data? {
        guard hasTitle else {
            return nil
        }
        return proto.title
    }
    public var hasTitle: Bool {
        return proto.title.count > 0
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyTitleAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyTitleAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyTitleAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyTitleAction) throws -> GroupsProtoGroupChangeActionsModifyTitleAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyTitleAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyTitleAction -

        let result = GroupsProtoGroupChangeActionsModifyTitleAction(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyTitleAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyTitleAction.GroupsProtoGroupChangeActionsModifyTitleActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyTitleAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyAvatarAction

public class GroupsProtoGroupChangeActionsModifyAvatarAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyAvatarActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsModifyAvatarActionBuilder {
        return GroupsProtoGroupChangeActionsModifyAvatarActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyAvatarActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyAvatarActionBuilder()
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsModifyAvatarActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyAvatarAction()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setAvatar(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.avatar = valueParam
        }

        public func setAvatar(_ valueParam: Data) {
            proto.avatar = valueParam
        }

        public func build() throws -> GroupsProtoGroupChangeActionsModifyAvatarAction {
            return try GroupsProtoGroupChangeActionsModifyAvatarAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyAvatarAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAction

    public var avatar: Data? {
        guard hasAvatar else {
            return nil
        }
        return proto.avatar
    }
    public var hasAvatar: Bool {
        return proto.avatar.count > 0
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyAvatarAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyAvatarAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAction) throws -> GroupsProtoGroupChangeActionsModifyAvatarAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyAvatarAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyAvatarAction -

        let result = GroupsProtoGroupChangeActionsModifyAvatarAction(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyAvatarAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyAvatarAction.GroupsProtoGroupChangeActionsModifyAvatarActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyAvatarAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyTitleAccessControlAction

public class GroupsProtoGroupChangeActionsModifyTitleAccessControlAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder {
        return GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder()
        if let _value = titleAccess {
            builder.setTitleAccess(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyTitleAccessControlAction()

        fileprivate override init() {}

        public func setTitleAccess(_ valueParam: GroupsProtoAccessControlAccessRequired) {
            proto.titleAccess = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
        }

        public func build() throws -> GroupsProtoGroupChangeActionsModifyTitleAccessControlAction {
            return try GroupsProtoGroupChangeActionsModifyTitleAccessControlAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyTitleAccessControlAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyTitleAccessControlAction

    public var titleAccess: GroupsProtoAccessControlAccessRequired? {
        guard hasTitleAccess else {
            return nil
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.titleAccess)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedTitleAccess: GroupsProtoAccessControlAccessRequired {
        if !hasTitleAccess {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: ModifyTitleAccessControlAction.titleAccess.")
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.titleAccess)
    }
    public var hasTitleAccess: Bool {
        return true
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyTitleAccessControlAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyTitleAccessControlAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyTitleAccessControlAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyTitleAccessControlAction) throws -> GroupsProtoGroupChangeActionsModifyTitleAccessControlAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyTitleAccessControlAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyTitleAccessControlAction -

        let result = GroupsProtoGroupChangeActionsModifyTitleAccessControlAction(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyTitleAccessControlAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyTitleAccessControlAction.GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyTitleAccessControlAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction

public class GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder {
        return GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder()
        if let _value = avatarAccess {
            builder.setAvatarAccess(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction()

        fileprivate override init() {}

        public func setAvatarAccess(_ valueParam: GroupsProtoAccessControlAccessRequired) {
            proto.avatarAccess = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
        }

        public func build() throws -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction {
            return try GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction

    public var avatarAccess: GroupsProtoAccessControlAccessRequired? {
        guard hasAvatarAccess else {
            return nil
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.avatarAccess)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedAvatarAccess: GroupsProtoAccessControlAccessRequired {
        if !hasAvatarAccess {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: ModifyAvatarAccessControlAction.avatarAccess.")
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.avatarAccess)
    }
    public var hasAvatarAccess: Bool {
        return true
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction) throws -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction -

        let result = GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction.GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyMembersAccessControlAction

public class GroupsProtoGroupChangeActionsModifyMembersAccessControlAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder {
        return GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder()
        if let _value = membersAccess {
            builder.setMembersAccess(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction()

        fileprivate override init() {}

        public func setMembersAccess(_ valueParam: GroupsProtoAccessControlAccessRequired) {
            proto.membersAccess = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
        }

        public func build() throws -> GroupsProtoGroupChangeActionsModifyMembersAccessControlAction {
            return try GroupsProtoGroupChangeActionsModifyMembersAccessControlAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyMembersAccessControlAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction

    public var membersAccess: GroupsProtoAccessControlAccessRequired? {
        guard hasMembersAccess else {
            return nil
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.membersAccess)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedMembersAccess: GroupsProtoAccessControlAccessRequired {
        if !hasMembersAccess {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: ModifyMembersAccessControlAction.membersAccess.")
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.membersAccess)
    }
    public var hasMembersAccess: Bool {
        return true
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyMembersAccessControlAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction) throws -> GroupsProtoGroupChangeActionsModifyMembersAccessControlAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyMembersAccessControlAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyMembersAccessControlAction -

        let result = GroupsProtoGroupChangeActionsModifyMembersAccessControlAction(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyMembersAccessControlAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyMembersAccessControlAction.GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyMembersAccessControlAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActions

public class GroupsProtoGroupChangeActions: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsBuilder {
        return GroupsProtoGroupChangeActionsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsBuilder {
        let builder = GroupsProtoGroupChangeActionsBuilder()
        if let _value = source {
            builder.setSource(_value)
        }
        if hasVersion {
            builder.setVersion(version)
        }
        builder.setAddMembers(addMembers)
        builder.setDeleteMembers(deleteMembers)
        builder.setModifyMembers(modifyMembers)
        if let _value = modifyTitle {
            builder.setModifyTitle(_value)
        }
        if let _value = modifyAvatar {
            builder.setModifyAvatar(_value)
        }
        if let _value = modifyTitleAccess {
            builder.setModifyTitleAccess(_value)
        }
        if let _value = modifyAvatarAccess {
            builder.setModifyAvatarAccess(_value)
        }
        if let _value = modifyMemberAccess {
            builder.setModifyMemberAccess(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setSource(_ valueParam: GroupsProtoMember?) {
            guard let valueParam = valueParam else { return }
            proto.source = valueParam.proto
        }

        public func setSource(_ valueParam: GroupsProtoMember) {
            proto.source = valueParam.proto
        }

        public func setVersion(_ valueParam: UInt32) {
            proto.version = valueParam
        }

        public func addAddMembers(_ valueParam: GroupsProtoGroupChangeActionsAddMemberAction) {
            var items = proto.addMembers
            items.append(valueParam.proto)
            proto.addMembers = items
        }

        public func setAddMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsAddMemberAction]) {
            proto.addMembers = wrappedItems.map { $0.proto }
        }

        public func addDeleteMembers(_ valueParam: GroupsProtoGroupChangeActionsDeleteMemberAction) {
            var items = proto.deleteMembers
            items.append(valueParam.proto)
            proto.deleteMembers = items
        }

        public func setDeleteMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsDeleteMemberAction]) {
            proto.deleteMembers = wrappedItems.map { $0.proto }
        }

        public func addModifyMembers(_ valueParam: GroupsProtoGroupChangeActionsModifyMemberRoleAction) {
            var items = proto.modifyMembers
            items.append(valueParam.proto)
            proto.modifyMembers = items
        }

        public func setModifyMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsModifyMemberRoleAction]) {
            proto.modifyMembers = wrappedItems.map { $0.proto }
        }

        @available(swift, obsoleted: 1.0)
        public func setModifyTitle(_ valueParam: GroupsProtoGroupChangeActionsModifyTitleAction?) {
            guard let valueParam = valueParam else { return }
            proto.modifyTitle = valueParam.proto
        }

        public func setModifyTitle(_ valueParam: GroupsProtoGroupChangeActionsModifyTitleAction) {
            proto.modifyTitle = valueParam.proto
        }

        @available(swift, obsoleted: 1.0)
        public func setModifyAvatar(_ valueParam: GroupsProtoGroupChangeActionsModifyAvatarAction?) {
            guard let valueParam = valueParam else { return }
            proto.modifyAvatar = valueParam.proto
        }

        public func setModifyAvatar(_ valueParam: GroupsProtoGroupChangeActionsModifyAvatarAction) {
            proto.modifyAvatar = valueParam.proto
        }

        @available(swift, obsoleted: 1.0)
        public func setModifyTitleAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyTitleAccessControlAction?) {
            guard let valueParam = valueParam else { return }
            proto.modifyTitleAccess = valueParam.proto
        }

        public func setModifyTitleAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyTitleAccessControlAction) {
            proto.modifyTitleAccess = valueParam.proto
        }

        @available(swift, obsoleted: 1.0)
        public func setModifyAvatarAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction?) {
            guard let valueParam = valueParam else { return }
            proto.modifyAvatarAccess = valueParam.proto
        }

        public func setModifyAvatarAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction) {
            proto.modifyAvatarAccess = valueParam.proto
        }

        @available(swift, obsoleted: 1.0)
        public func setModifyMemberAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction?) {
            guard let valueParam = valueParam else { return }
            proto.modifyMemberAccess = valueParam.proto
        }

        public func setModifyMemberAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction) {
            proto.modifyMemberAccess = valueParam.proto
        }

        public func build() throws -> GroupsProtoGroupChangeActions {
            return try GroupsProtoGroupChangeActions.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActions.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions

    public let source: GroupsProtoMember?

    public let addMembers: [GroupsProtoGroupChangeActionsAddMemberAction]

    public let deleteMembers: [GroupsProtoGroupChangeActionsDeleteMemberAction]

    public let modifyMembers: [GroupsProtoGroupChangeActionsModifyMemberRoleAction]

    public let modifyTitle: GroupsProtoGroupChangeActionsModifyTitleAction?

    public let modifyAvatar: GroupsProtoGroupChangeActionsModifyAvatarAction?

    public let modifyTitleAccess: GroupsProtoGroupChangeActionsModifyTitleAccessControlAction?

    public let modifyAvatarAccess: GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction?

    public let modifyMemberAccess: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction?

    public var version: UInt32 {
        return proto.version
    }
    public var hasVersion: Bool {
        return true
    }

    private init(proto: GroupsProtos_GroupChange.Actions,
                 source: GroupsProtoMember?,
                 addMembers: [GroupsProtoGroupChangeActionsAddMemberAction],
                 deleteMembers: [GroupsProtoGroupChangeActionsDeleteMemberAction],
                 modifyMembers: [GroupsProtoGroupChangeActionsModifyMemberRoleAction],
                 modifyTitle: GroupsProtoGroupChangeActionsModifyTitleAction?,
                 modifyAvatar: GroupsProtoGroupChangeActionsModifyAvatarAction?,
                 modifyTitleAccess: GroupsProtoGroupChangeActionsModifyTitleAccessControlAction?,
                 modifyAvatarAccess: GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction?,
                 modifyMemberAccess: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction?) {
        self.proto = proto
        self.source = source
        self.addMembers = addMembers
        self.deleteMembers = deleteMembers
        self.modifyMembers = modifyMembers
        self.modifyTitle = modifyTitle
        self.modifyAvatar = modifyAvatar
        self.modifyTitleAccess = modifyTitleAccess
        self.modifyAvatarAccess = modifyAvatarAccess
        self.modifyMemberAccess = modifyMemberAccess
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActions {
        let proto = try GroupsProtos_GroupChange.Actions(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions) throws -> GroupsProtoGroupChangeActions {
        var source: GroupsProtoMember? = nil
        if proto.hasSource {
            source = try GroupsProtoMember.parseProto(proto.source)
        }

        var addMembers: [GroupsProtoGroupChangeActionsAddMemberAction] = []
        addMembers = try proto.addMembers.map { try GroupsProtoGroupChangeActionsAddMemberAction.parseProto($0) }

        var deleteMembers: [GroupsProtoGroupChangeActionsDeleteMemberAction] = []
        deleteMembers = try proto.deleteMembers.map { try GroupsProtoGroupChangeActionsDeleteMemberAction.parseProto($0) }

        var modifyMembers: [GroupsProtoGroupChangeActionsModifyMemberRoleAction] = []
        modifyMembers = try proto.modifyMembers.map { try GroupsProtoGroupChangeActionsModifyMemberRoleAction.parseProto($0) }

        var modifyTitle: GroupsProtoGroupChangeActionsModifyTitleAction? = nil
        if proto.hasModifyTitle {
            modifyTitle = try GroupsProtoGroupChangeActionsModifyTitleAction.parseProto(proto.modifyTitle)
        }

        var modifyAvatar: GroupsProtoGroupChangeActionsModifyAvatarAction? = nil
        if proto.hasModifyAvatar {
            modifyAvatar = try GroupsProtoGroupChangeActionsModifyAvatarAction.parseProto(proto.modifyAvatar)
        }

        var modifyTitleAccess: GroupsProtoGroupChangeActionsModifyTitleAccessControlAction? = nil
        if proto.hasModifyTitleAccess {
            modifyTitleAccess = try GroupsProtoGroupChangeActionsModifyTitleAccessControlAction.parseProto(proto.modifyTitleAccess)
        }

        var modifyAvatarAccess: GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction? = nil
        if proto.hasModifyAvatarAccess {
            modifyAvatarAccess = try GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction.parseProto(proto.modifyAvatarAccess)
        }

        var modifyMemberAccess: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction? = nil
        if proto.hasModifyMemberAccess {
            modifyMemberAccess = try GroupsProtoGroupChangeActionsModifyMembersAccessControlAction.parseProto(proto.modifyMemberAccess)
        }

        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActions -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActions -

        let result = GroupsProtoGroupChangeActions(proto: proto,
                                                   source: source,
                                                   addMembers: addMembers,
                                                   deleteMembers: deleteMembers,
                                                   modifyMembers: modifyMembers,
                                                   modifyTitle: modifyTitle,
                                                   modifyAvatar: modifyAvatar,
                                                   modifyTitleAccess: modifyTitleAccess,
                                                   modifyAvatarAccess: modifyAvatarAccess,
                                                   modifyMemberAccess: modifyMemberAccess)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActions {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActions.GroupsProtoGroupChangeActionsBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActions? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChange

public class GroupsProtoGroupChange: NSObject {

    // MARK: - GroupsProtoGroupChangeBuilder

    public class func builder() -> GroupsProtoGroupChangeBuilder {
        return GroupsProtoGroupChangeBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeBuilder {
        let builder = GroupsProtoGroupChangeBuilder()
        if let _value = actions {
            builder.setActions(_value)
        }
        if let _value = serverSignature {
            builder.setServerSignature(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setActions(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.actions = valueParam
        }

        public func setActions(_ valueParam: Data) {
            proto.actions = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setServerSignature(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.serverSignature = valueParam
        }

        public func setServerSignature(_ valueParam: Data) {
            proto.serverSignature = valueParam
        }

        public func build() throws -> GroupsProtoGroupChange {
            return try GroupsProtoGroupChange.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChange.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange

    public var actions: Data? {
        guard hasActions else {
            return nil
        }
        return proto.actions
    }
    public var hasActions: Bool {
        return proto.actions.count > 0
    }

    public var serverSignature: Data? {
        guard hasServerSignature else {
            return nil
        }
        return proto.serverSignature
    }
    public var hasServerSignature: Bool {
        return proto.serverSignature.count > 0
    }

    private init(proto: GroupsProtos_GroupChange) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChange {
        let proto = try GroupsProtos_GroupChange(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange) throws -> GroupsProtoGroupChange {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChange -

        // MARK: - End Validation Logic for GroupsProtoGroupChange -

        let result = GroupsProtoGroupChange(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChange {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChange.GroupsProtoGroupChangeBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChange? {
        return try! self.build()
    }
}

#endif
