//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

// WARNING: This code is generated. Only edit within the markers.

public enum GroupsProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - GroupsProtoMember

@objc public class GroupsProtoMember: NSObject {

    // MARK: - GroupsProtoMemberRole

    @objc public enum GroupsProtoMemberRole: Int32 {
        case unknown = 0
        case `default` = 1
        case administrator = 2
    }

    private class func GroupsProtoMemberRoleWrap(_ value: GroupsProtos_Member.Role) -> GroupsProtoMemberRole {
        switch value {
        case .unknown: return .unknown
        case .default: return .default
        case .administrator: return .administrator
        }
    }

    private class func GroupsProtoMemberRoleUnwrap(_ value: GroupsProtoMemberRole) -> GroupsProtos_Member.Role {
        switch value {
        case .unknown: return .unknown
        case .default: return .default
        case .administrator: return .administrator
        }
    }

    // MARK: - GroupsProtoMemberBuilder

    @objc public class func builder() -> GroupsProtoMemberBuilder {
        return GroupsProtoMemberBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> GroupsProtoMemberBuilder {
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

    @objc public class GroupsProtoMemberBuilder: NSObject {

        private var proto = GroupsProtos_Member()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setUserID(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.userID = valueParam
        }

        public func setUserID(_ valueParam: Data) {
            proto.userID = valueParam
        }

        @objc
        public func setRole(_ valueParam: GroupsProtoMemberRole) {
            proto.role = GroupsProtoMemberRoleUnwrap(valueParam)
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setProfileKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.profileKey = valueParam
        }

        public func setProfileKey(_ valueParam: Data) {
            proto.profileKey = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setPresentation(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.presentation = valueParam
        }

        public func setPresentation(_ valueParam: Data) {
            proto.presentation = valueParam
        }

        @objc
        public func setJoinedAtVersion(_ valueParam: UInt32) {
            proto.joinedAtVersion = valueParam
        }

        @objc public func build() throws -> GroupsProtoMember {
            return try GroupsProtoMember.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try GroupsProtoMember.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_Member

    @objc public var userID: Data? {
        guard proto.hasUserID else {
            return nil
        }
        return proto.userID
    }
    @objc public var hasUserID: Bool {
        return proto.hasUserID
    }

    public var role: GroupsProtoMemberRole? {
        guard proto.hasRole else {
            return nil
        }
        return GroupsProtoMember.GroupsProtoMemberRoleWrap(proto.role)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedRole: GroupsProtoMemberRole {
        if !hasRole {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Member.role.")
        }
        return GroupsProtoMember.GroupsProtoMemberRoleWrap(proto.role)
    }
    @objc public var hasRole: Bool {
        return proto.hasRole
    }

    @objc public var profileKey: Data? {
        guard proto.hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    @objc public var hasProfileKey: Bool {
        return proto.hasProfileKey
    }

    @objc public var presentation: Data? {
        guard proto.hasPresentation else {
            return nil
        }
        return proto.presentation
    }
    @objc public var hasPresentation: Bool {
        return proto.hasPresentation
    }

    @objc public var joinedAtVersion: UInt32 {
        return proto.joinedAtVersion
    }
    @objc public var hasJoinedAtVersion: Bool {
        return proto.hasJoinedAtVersion
    }

    private init(proto: GroupsProtos_Member) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> GroupsProtoMember {
        let proto = try GroupsProtos_Member(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_Member) throws -> GroupsProtoMember {
        // MARK: - Begin Validation Logic for GroupsProtoMember -

        // MARK: - End Validation Logic for GroupsProtoMember -

        let result = GroupsProtoMember(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoMember {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoMember.GroupsProtoMemberBuilder {
    @objc public func buildIgnoringErrors() -> GroupsProtoMember? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoAccessControl

@objc public class GroupsProtoAccessControl: NSObject {

    // MARK: - GroupsProtoAccessControlAccessRequired

    @objc public enum GroupsProtoAccessControlAccessRequired: Int32 {
        case unknown = 0
        case any = 1
        case member = 2
        case administrator = 3
    }

    private class func GroupsProtoAccessControlAccessRequiredWrap(_ value: GroupsProtos_AccessControl.AccessRequired) -> GroupsProtoAccessControlAccessRequired {
        switch value {
        case .unknown: return .unknown
        case .any: return .any
        case .member: return .member
        case .administrator: return .administrator
        }
    }

    private class func GroupsProtoAccessControlAccessRequiredUnwrap(_ value: GroupsProtoAccessControlAccessRequired) -> GroupsProtos_AccessControl.AccessRequired {
        switch value {
        case .unknown: return .unknown
        case .any: return .any
        case .member: return .member
        case .administrator: return .administrator
        }
    }

    // MARK: - GroupsProtoAccessControlBuilder

    @objc public class func builder() -> GroupsProtoAccessControlBuilder {
        return GroupsProtoAccessControlBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> GroupsProtoAccessControlBuilder {
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

    @objc public class GroupsProtoAccessControlBuilder: NSObject {

        private var proto = GroupsProtos_AccessControl()

        @objc fileprivate override init() {}

        @objc
        public func setTitle(_ valueParam: GroupsProtoAccessControlAccessRequired) {
            proto.title = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
        }

        @objc
        public func setAvatar(_ valueParam: GroupsProtoAccessControlAccessRequired) {
            proto.avatar = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
        }

        @objc
        public func setMembers(_ valueParam: GroupsProtoAccessControlAccessRequired) {
            proto.members = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
        }

        @objc public func build() throws -> GroupsProtoAccessControl {
            return try GroupsProtoAccessControl.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try GroupsProtoAccessControl.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_AccessControl

    public var title: GroupsProtoAccessControlAccessRequired? {
        guard proto.hasTitle else {
            return nil
        }
        return GroupsProtoAccessControl.GroupsProtoAccessControlAccessRequiredWrap(proto.title)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedTitle: GroupsProtoAccessControlAccessRequired {
        if !hasTitle {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: AccessControl.title.")
        }
        return GroupsProtoAccessControl.GroupsProtoAccessControlAccessRequiredWrap(proto.title)
    }
    @objc public var hasTitle: Bool {
        return proto.hasTitle
    }

    public var avatar: GroupsProtoAccessControlAccessRequired? {
        guard proto.hasAvatar else {
            return nil
        }
        return GroupsProtoAccessControl.GroupsProtoAccessControlAccessRequiredWrap(proto.avatar)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedAvatar: GroupsProtoAccessControlAccessRequired {
        if !hasAvatar {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: AccessControl.avatar.")
        }
        return GroupsProtoAccessControl.GroupsProtoAccessControlAccessRequiredWrap(proto.avatar)
    }
    @objc public var hasAvatar: Bool {
        return proto.hasAvatar
    }

    public var members: GroupsProtoAccessControlAccessRequired? {
        guard proto.hasMembers else {
            return nil
        }
        return GroupsProtoAccessControl.GroupsProtoAccessControlAccessRequiredWrap(proto.members)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedMembers: GroupsProtoAccessControlAccessRequired {
        if !hasMembers {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: AccessControl.members.")
        }
        return GroupsProtoAccessControl.GroupsProtoAccessControlAccessRequiredWrap(proto.members)
    }
    @objc public var hasMembers: Bool {
        return proto.hasMembers
    }

    private init(proto: GroupsProtos_AccessControl) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> GroupsProtoAccessControl {
        let proto = try GroupsProtos_AccessControl(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_AccessControl) throws -> GroupsProtoAccessControl {
        // MARK: - Begin Validation Logic for GroupsProtoAccessControl -

        // MARK: - End Validation Logic for GroupsProtoAccessControl -

        let result = GroupsProtoAccessControl(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoAccessControl {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoAccessControl.GroupsProtoAccessControlBuilder {
    @objc public func buildIgnoringErrors() -> GroupsProtoAccessControl? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroup

@objc public class GroupsProtoGroup: NSObject {

    // MARK: - GroupsProtoGroupBuilder

    @objc public class func builder() -> GroupsProtoGroupBuilder {
        return GroupsProtoGroupBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> GroupsProtoGroupBuilder {
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

    @objc public class GroupsProtoGroupBuilder: NSObject {

        private var proto = GroupsProtos_Group()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setPublicKey(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.publicKey = valueParam
        }

        public func setPublicKey(_ valueParam: Data) {
            proto.publicKey = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setTitle(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.title = valueParam
        }

        public func setTitle(_ valueParam: Data) {
            proto.title = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setAvatar(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.avatar = valueParam
        }

        public func setAvatar(_ valueParam: Data) {
            proto.avatar = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setAccessControl(_ valueParam: GroupsProtoAccessControl?) {
            guard let valueParam = valueParam else { return }
            proto.accessControl = valueParam.proto
        }

        public func setAccessControl(_ valueParam: GroupsProtoAccessControl) {
            proto.accessControl = valueParam.proto
        }

        @objc
        public func setVersion(_ valueParam: UInt32) {
            proto.version = valueParam
        }

        @objc public func addMembers(_ valueParam: GroupsProtoMember) {
            var items = proto.members
            items.append(valueParam.proto)
            proto.members = items
        }

        @objc public func setMembers(_ wrappedItems: [GroupsProtoMember]) {
            proto.members = wrappedItems.map { $0.proto }
        }

        @objc public func build() throws -> GroupsProtoGroup {
            return try GroupsProtoGroup.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroup.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_Group

    @objc public let accessControl: GroupsProtoAccessControl?

    @objc public let members: [GroupsProtoMember]

    @objc public var publicKey: Data? {
        guard proto.hasPublicKey else {
            return nil
        }
        return proto.publicKey
    }
    @objc public var hasPublicKey: Bool {
        return proto.hasPublicKey
    }

    @objc public var title: Data? {
        guard proto.hasTitle else {
            return nil
        }
        return proto.title
    }
    @objc public var hasTitle: Bool {
        return proto.hasTitle
    }

    @objc public var avatar: Data? {
        guard proto.hasAvatar else {
            return nil
        }
        return proto.avatar
    }
    @objc public var hasAvatar: Bool {
        return proto.hasAvatar
    }

    @objc public var version: UInt32 {
        return proto.version
    }
    @objc public var hasVersion: Bool {
        return proto.hasVersion
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

    @objc public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroup {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroup {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroup.GroupsProtoGroupBuilder {
    @objc public func buildIgnoringErrors() -> GroupsProtoGroup? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsAddMemberAction

@objc public class GroupsProtoGroupChangeActionsAddMemberAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsAddMemberActionBuilder

    @objc public class func builder() -> GroupsProtoGroupChangeActionsAddMemberActionBuilder {
        return GroupsProtoGroupChangeActionsAddMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> GroupsProtoGroupChangeActionsAddMemberActionBuilder {
        let builder = GroupsProtoGroupChangeActionsAddMemberActionBuilder()
        if let _value = added {
            builder.setAdded(_value)
        }
        return builder
    }

    @objc public class GroupsProtoGroupChangeActionsAddMemberActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.AddMemberAction()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setAdded(_ valueParam: GroupsProtoMember?) {
            guard let valueParam = valueParam else { return }
            proto.added = valueParam.proto
        }

        public func setAdded(_ valueParam: GroupsProtoMember) {
            proto.added = valueParam.proto
        }

        @objc public func build() throws -> GroupsProtoGroupChangeActionsAddMemberAction {
            return try GroupsProtoGroupChangeActionsAddMemberAction.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsAddMemberAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.AddMemberAction

    @objc public let added: GroupsProtoMember?

    private init(proto: GroupsProtos_GroupChange.Actions.AddMemberAction,
                 added: GroupsProtoMember?) {
        self.proto = proto
        self.added = added
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsAddMemberAction {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsAddMemberAction {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsAddMemberAction.GroupsProtoGroupChangeActionsAddMemberActionBuilder {
    @objc public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsAddMemberAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsDeleteMemberAction

@objc public class GroupsProtoGroupChangeActionsDeleteMemberAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsDeleteMemberActionBuilder

    @objc public class func builder() -> GroupsProtoGroupChangeActionsDeleteMemberActionBuilder {
        return GroupsProtoGroupChangeActionsDeleteMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> GroupsProtoGroupChangeActionsDeleteMemberActionBuilder {
        let builder = GroupsProtoGroupChangeActionsDeleteMemberActionBuilder()
        if let _value = deleted {
            builder.setDeleted(_value)
        }
        return builder
    }

    @objc public class GroupsProtoGroupChangeActionsDeleteMemberActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.DeleteMemberAction()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setDeleted(_ valueParam: GroupsProtoMember?) {
            guard let valueParam = valueParam else { return }
            proto.deleted = valueParam.proto
        }

        public func setDeleted(_ valueParam: GroupsProtoMember) {
            proto.deleted = valueParam.proto
        }

        @objc public func build() throws -> GroupsProtoGroupChangeActionsDeleteMemberAction {
            return try GroupsProtoGroupChangeActionsDeleteMemberAction.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsDeleteMemberAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.DeleteMemberAction

    @objc public let deleted: GroupsProtoMember?

    private init(proto: GroupsProtos_GroupChange.Actions.DeleteMemberAction,
                 deleted: GroupsProtoMember?) {
        self.proto = proto
        self.deleted = deleted
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsDeleteMemberAction {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsDeleteMemberAction {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsDeleteMemberAction.GroupsProtoGroupChangeActionsDeleteMemberActionBuilder {
    @objc public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsDeleteMemberAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyMemberRoleAction

@objc public class GroupsProtoGroupChangeActionsModifyMemberRoleAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder

    @objc public class func builder() -> GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder {
        return GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder()
        if let _value = userID {
            builder.setUserID(_value)
        }
        if let _value = role {
            builder.setRole(_value)
        }
        return builder
    }

    @objc public class GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setUserID(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.userID = valueParam
        }

        public func setUserID(_ valueParam: Data) {
            proto.userID = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setRole(_ valueParam: Member.Role?) {
            guard let valueParam = valueParam else { return }
            proto.role = valueParam
        }

        public func setRole(_ valueParam: Member.Role) {
            proto.role = valueParam
        }

        @objc public func build() throws -> GroupsProtoGroupChangeActionsModifyMemberRoleAction {
            return try GroupsProtoGroupChangeActionsModifyMemberRoleAction.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyMemberRoleAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction

    @objc public var userID: Data? {
        guard proto.hasUserID else {
            return nil
        }
        return proto.userID
    }
    @objc public var hasUserID: Bool {
        return proto.hasUserID
    }

    @objc public var role: Member.Role? {
        guard proto.hasRole else {
            return nil
        }
        return proto.role
    }
    @objc public var hasRole: Bool {
        return proto.hasRole
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyMemberRoleAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction) throws -> GroupsProtoGroupChangeActionsModifyMemberRoleAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyMemberRoleAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyMemberRoleAction -

        let result = GroupsProtoGroupChangeActionsModifyMemberRoleAction(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyMemberRoleAction {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyMemberRoleAction.GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder {
    @objc public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyMemberRoleAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyTitleAction

@objc public class GroupsProtoGroupChangeActionsModifyTitleAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyTitleActionBuilder

    @objc public class func builder() -> GroupsProtoGroupChangeActionsModifyTitleActionBuilder {
        return GroupsProtoGroupChangeActionsModifyTitleActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> GroupsProtoGroupChangeActionsModifyTitleActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyTitleActionBuilder()
        if let _value = title {
            builder.setTitle(_value)
        }
        return builder
    }

    @objc public class GroupsProtoGroupChangeActionsModifyTitleActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyTitleAction()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setTitle(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.title = valueParam
        }

        public func setTitle(_ valueParam: Data) {
            proto.title = valueParam
        }

        @objc public func build() throws -> GroupsProtoGroupChangeActionsModifyTitleAction {
            return try GroupsProtoGroupChangeActionsModifyTitleAction.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyTitleAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyTitleAction

    @objc public var title: Data? {
        guard proto.hasTitle else {
            return nil
        }
        return proto.title
    }
    @objc public var hasTitle: Bool {
        return proto.hasTitle
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyTitleAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyTitleAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyTitleAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyTitleAction) throws -> GroupsProtoGroupChangeActionsModifyTitleAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyTitleAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyTitleAction -

        let result = GroupsProtoGroupChangeActionsModifyTitleAction(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyTitleAction {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyTitleAction.GroupsProtoGroupChangeActionsModifyTitleActionBuilder {
    @objc public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyTitleAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyAvatarAction

@objc public class GroupsProtoGroupChangeActionsModifyAvatarAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyAvatarActionBuilder

    @objc public class func builder() -> GroupsProtoGroupChangeActionsModifyAvatarActionBuilder {
        return GroupsProtoGroupChangeActionsModifyAvatarActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> GroupsProtoGroupChangeActionsModifyAvatarActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyAvatarActionBuilder()
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        return builder
    }

    @objc public class GroupsProtoGroupChangeActionsModifyAvatarActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyAvatarAction()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setAvatar(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.avatar = valueParam
        }

        public func setAvatar(_ valueParam: Data) {
            proto.avatar = valueParam
        }

        @objc public func build() throws -> GroupsProtoGroupChangeActionsModifyAvatarAction {
            return try GroupsProtoGroupChangeActionsModifyAvatarAction.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyAvatarAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAction

    @objc public var avatar: Data? {
        guard proto.hasAvatar else {
            return nil
        }
        return proto.avatar
    }
    @objc public var hasAvatar: Bool {
        return proto.hasAvatar
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyAvatarAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyAvatarAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAction) throws -> GroupsProtoGroupChangeActionsModifyAvatarAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyAvatarAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyAvatarAction -

        let result = GroupsProtoGroupChangeActionsModifyAvatarAction(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyAvatarAction {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyAvatarAction.GroupsProtoGroupChangeActionsModifyAvatarActionBuilder {
    @objc public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyAvatarAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyTitleAccessControlAction

@objc public class GroupsProtoGroupChangeActionsModifyTitleAccessControlAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder

    @objc public class func builder() -> GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder {
        return GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder()
        if let _value = titleAccess {
            builder.setTitleAccess(_value)
        }
        return builder
    }

    @objc public class GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyTitleAccessControlAction()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setTitleAccess(_ valueParam: AccessControl.AccessRequired?) {
            guard let valueParam = valueParam else { return }
            proto.titleAccess = valueParam
        }

        public func setTitleAccess(_ valueParam: AccessControl.AccessRequired) {
            proto.titleAccess = valueParam
        }

        @objc public func build() throws -> GroupsProtoGroupChangeActionsModifyTitleAccessControlAction {
            return try GroupsProtoGroupChangeActionsModifyTitleAccessControlAction.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyTitleAccessControlAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyTitleAccessControlAction

    @objc public var titleAccess: AccessControl.AccessRequired? {
        guard proto.hasTitleAccess else {
            return nil
        }
        return proto.titleAccess
    }
    @objc public var hasTitleAccess: Bool {
        return proto.hasTitleAccess
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyTitleAccessControlAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyTitleAccessControlAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyTitleAccessControlAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyTitleAccessControlAction) throws -> GroupsProtoGroupChangeActionsModifyTitleAccessControlAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyTitleAccessControlAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyTitleAccessControlAction -

        let result = GroupsProtoGroupChangeActionsModifyTitleAccessControlAction(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyTitleAccessControlAction {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyTitleAccessControlAction.GroupsProtoGroupChangeActionsModifyTitleAccessControlActionBuilder {
    @objc public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyTitleAccessControlAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction

@objc public class GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder

    @objc public class func builder() -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder {
        return GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder()
        if let _value = avatarAccess {
            builder.setAvatarAccess(_value)
        }
        return builder
    }

    @objc public class GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setAvatarAccess(_ valueParam: AccessControl.AccessRequired?) {
            guard let valueParam = valueParam else { return }
            proto.avatarAccess = valueParam
        }

        public func setAvatarAccess(_ valueParam: AccessControl.AccessRequired) {
            proto.avatarAccess = valueParam
        }

        @objc public func build() throws -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction {
            return try GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction

    @objc public var avatarAccess: AccessControl.AccessRequired? {
        guard proto.hasAvatarAccess else {
            return nil
        }
        return proto.avatarAccess
    }
    @objc public var hasAvatarAccess: Bool {
        return proto.hasAvatarAccess
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction) throws -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction -

        let result = GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction.GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder {
    @objc public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyMembersAccessControlAction

@objc public class GroupsProtoGroupChangeActionsModifyMembersAccessControlAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder

    @objc public class func builder() -> GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder {
        return GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder()
        if let _value = membersAccess {
            builder.setMembersAccess(_value)
        }
        return builder
    }

    @objc public class GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setMembersAccess(_ valueParam: AccessControl.AccessRequired?) {
            guard let valueParam = valueParam else { return }
            proto.membersAccess = valueParam
        }

        public func setMembersAccess(_ valueParam: AccessControl.AccessRequired) {
            proto.membersAccess = valueParam
        }

        @objc public func build() throws -> GroupsProtoGroupChangeActionsModifyMembersAccessControlAction {
            return try GroupsProtoGroupChangeActionsModifyMembersAccessControlAction.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyMembersAccessControlAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction

    @objc public var membersAccess: AccessControl.AccessRequired? {
        guard proto.hasMembersAccess else {
            return nil
        }
        return proto.membersAccess
    }
    @objc public var hasMembersAccess: Bool {
        return proto.hasMembersAccess
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyMembersAccessControlAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction) throws -> GroupsProtoGroupChangeActionsModifyMembersAccessControlAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyMembersAccessControlAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyMembersAccessControlAction -

        let result = GroupsProtoGroupChangeActionsModifyMembersAccessControlAction(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyMembersAccessControlAction {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyMembersAccessControlAction.GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder {
    @objc public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyMembersAccessControlAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActions

@objc public class GroupsProtoGroupChangeActions: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsBuilder

    @objc public class func builder() -> GroupsProtoGroupChangeActionsBuilder {
        return GroupsProtoGroupChangeActionsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> GroupsProtoGroupChangeActionsBuilder {
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

    @objc public class GroupsProtoGroupChangeActionsBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setSource(_ valueParam: GroupsProtoMember?) {
            guard let valueParam = valueParam else { return }
            proto.source = valueParam.proto
        }

        public func setSource(_ valueParam: GroupsProtoMember) {
            proto.source = valueParam.proto
        }

        @objc
        public func setVersion(_ valueParam: UInt32) {
            proto.version = valueParam
        }

        @objc public func addAddMembers(_ valueParam: GroupsProtoGroupChangeActionsAddMemberAction) {
            var items = proto.addMembers
            items.append(valueParam.proto)
            proto.addMembers = items
        }

        @objc public func setAddMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsAddMemberAction]) {
            proto.addMembers = wrappedItems.map { $0.proto }
        }

        @objc public func addDeleteMembers(_ valueParam: GroupsProtoGroupChangeActionsDeleteMemberAction) {
            var items = proto.deleteMembers
            items.append(valueParam.proto)
            proto.deleteMembers = items
        }

        @objc public func setDeleteMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsDeleteMemberAction]) {
            proto.deleteMembers = wrappedItems.map { $0.proto }
        }

        @objc public func addModifyMembers(_ valueParam: GroupsProtoGroupChangeActionsModifyMemberRoleAction) {
            var items = proto.modifyMembers
            items.append(valueParam.proto)
            proto.modifyMembers = items
        }

        @objc public func setModifyMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsModifyMemberRoleAction]) {
            proto.modifyMembers = wrappedItems.map { $0.proto }
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setModifyTitle(_ valueParam: GroupsProtoGroupChangeActionsModifyTitleAction?) {
            guard let valueParam = valueParam else { return }
            proto.modifyTitle = valueParam.proto
        }

        public func setModifyTitle(_ valueParam: GroupsProtoGroupChangeActionsModifyTitleAction) {
            proto.modifyTitle = valueParam.proto
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setModifyAvatar(_ valueParam: GroupsProtoGroupChangeActionsModifyAvatarAction?) {
            guard let valueParam = valueParam else { return }
            proto.modifyAvatar = valueParam.proto
        }

        public func setModifyAvatar(_ valueParam: GroupsProtoGroupChangeActionsModifyAvatarAction) {
            proto.modifyAvatar = valueParam.proto
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setModifyTitleAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyTitleAccessControlAction?) {
            guard let valueParam = valueParam else { return }
            proto.modifyTitleAccess = valueParam.proto
        }

        public func setModifyTitleAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyTitleAccessControlAction) {
            proto.modifyTitleAccess = valueParam.proto
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setModifyAvatarAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction?) {
            guard let valueParam = valueParam else { return }
            proto.modifyAvatarAccess = valueParam.proto
        }

        public func setModifyAvatarAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction) {
            proto.modifyAvatarAccess = valueParam.proto
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setModifyMemberAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction?) {
            guard let valueParam = valueParam else { return }
            proto.modifyMemberAccess = valueParam.proto
        }

        public func setModifyMemberAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction) {
            proto.modifyMemberAccess = valueParam.proto
        }

        @objc public func build() throws -> GroupsProtoGroupChangeActions {
            return try GroupsProtoGroupChangeActions.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActions.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions

    @objc public let source: GroupsProtoMember?

    @objc public let addMembers: [GroupsProtoGroupChangeActionsAddMemberAction]

    @objc public let deleteMembers: [GroupsProtoGroupChangeActionsDeleteMemberAction]

    @objc public let modifyMembers: [GroupsProtoGroupChangeActionsModifyMemberRoleAction]

    @objc public let modifyTitle: GroupsProtoGroupChangeActionsModifyTitleAction?

    @objc public let modifyAvatar: GroupsProtoGroupChangeActionsModifyAvatarAction?

    @objc public let modifyTitleAccess: GroupsProtoGroupChangeActionsModifyTitleAccessControlAction?

    @objc public let modifyAvatarAccess: GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction?

    @objc public let modifyMemberAccess: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction?

    @objc public var version: UInt32 {
        return proto.version
    }
    @objc public var hasVersion: Bool {
        return proto.hasVersion
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

    @objc public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActions {
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

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActions {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActions.GroupsProtoGroupChangeActionsBuilder {
    @objc public func buildIgnoringErrors() -> GroupsProtoGroupChangeActions? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChange

@objc public class GroupsProtoGroupChange: NSObject {

    // MARK: - GroupsProtoGroupChangeBuilder

    @objc public class func builder() -> GroupsProtoGroupChangeBuilder {
        return GroupsProtoGroupChangeBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> GroupsProtoGroupChangeBuilder {
        let builder = GroupsProtoGroupChangeBuilder()
        if let _value = actions {
            builder.setActions(_value)
        }
        if let _value = serverSignature {
            builder.setServerSignature(_value)
        }
        return builder
    }

    @objc public class GroupsProtoGroupChangeBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange()

        @objc fileprivate override init() {}

        @objc
        @available(swift, obsoleted: 1.0)
        public func setActions(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.actions = valueParam
        }

        public func setActions(_ valueParam: Data) {
            proto.actions = valueParam
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setServerSignature(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.serverSignature = valueParam
        }

        public func setServerSignature(_ valueParam: Data) {
            proto.serverSignature = valueParam
        }

        @objc public func build() throws -> GroupsProtoGroupChange {
            return try GroupsProtoGroupChange.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChange.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange

    @objc public var actions: Data? {
        guard proto.hasActions else {
            return nil
        }
        return proto.actions
    }
    @objc public var hasActions: Bool {
        return proto.hasActions
    }

    @objc public var serverSignature: Data? {
        guard proto.hasServerSignature else {
            return nil
        }
        return proto.serverSignature
    }
    @objc public var hasServerSignature: Bool {
        return proto.hasServerSignature
    }

    private init(proto: GroupsProtos_GroupChange) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChange {
        let proto = try GroupsProtos_GroupChange(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange) throws -> GroupsProtoGroupChange {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChange -

        // MARK: - End Validation Logic for GroupsProtoGroupChange -

        let result = GroupsProtoGroupChange(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChange {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChange.GroupsProtoGroupChangeBuilder {
    @objc public func buildIgnoringErrors() -> GroupsProtoGroupChange? {
        return try! self.build()
    }
}

#endif
