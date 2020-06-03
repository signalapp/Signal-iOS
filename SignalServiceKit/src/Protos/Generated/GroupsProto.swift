//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum GroupsProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - GroupsProtoAvatarUploadAttributes

public class GroupsProtoAvatarUploadAttributes: NSObject {

    // MARK: - GroupsProtoAvatarUploadAttributesBuilder

    public class func builder() -> GroupsProtoAvatarUploadAttributesBuilder {
        return GroupsProtoAvatarUploadAttributesBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoAvatarUploadAttributesBuilder {
        let builder = GroupsProtoAvatarUploadAttributesBuilder()
        if let _value = key {
            builder.setKey(_value)
        }
        if let _value = credential {
            builder.setCredential(_value)
        }
        if let _value = acl {
            builder.setAcl(_value)
        }
        if let _value = algorithm {
            builder.setAlgorithm(_value)
        }
        if let _value = date {
            builder.setDate(_value)
        }
        if let _value = policy {
            builder.setPolicy(_value)
        }
        if let _value = signature {
            builder.setSignature(_value)
        }
        return builder
    }

    public class GroupsProtoAvatarUploadAttributesBuilder: NSObject {

        private var proto = GroupsProtos_AvatarUploadAttributes()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setKey(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.key = valueParam
        }

        public func setKey(_ valueParam: String) {
            proto.key = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setCredential(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.credential = valueParam
        }

        public func setCredential(_ valueParam: String) {
            proto.credential = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setAcl(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.acl = valueParam
        }

        public func setAcl(_ valueParam: String) {
            proto.acl = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setAlgorithm(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.algorithm = valueParam
        }

        public func setAlgorithm(_ valueParam: String) {
            proto.algorithm = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setDate(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.date = valueParam
        }

        public func setDate(_ valueParam: String) {
            proto.date = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setPolicy(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.policy = valueParam
        }

        public func setPolicy(_ valueParam: String) {
            proto.policy = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setSignature(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.signature = valueParam
        }

        public func setSignature(_ valueParam: String) {
            proto.signature = valueParam
        }

        public func build() throws -> GroupsProtoAvatarUploadAttributes {
            return try GroupsProtoAvatarUploadAttributes.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoAvatarUploadAttributes.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_AvatarUploadAttributes

    public var key: String? {
        guard hasKey else {
            return nil
        }
        return proto.key
    }
    public var hasKey: Bool {
        return !proto.key.isEmpty
    }

    public var credential: String? {
        guard hasCredential else {
            return nil
        }
        return proto.credential
    }
    public var hasCredential: Bool {
        return !proto.credential.isEmpty
    }

    public var acl: String? {
        guard hasAcl else {
            return nil
        }
        return proto.acl
    }
    public var hasAcl: Bool {
        return !proto.acl.isEmpty
    }

    public var algorithm: String? {
        guard hasAlgorithm else {
            return nil
        }
        return proto.algorithm
    }
    public var hasAlgorithm: Bool {
        return !proto.algorithm.isEmpty
    }

    public var date: String? {
        guard hasDate else {
            return nil
        }
        return proto.date
    }
    public var hasDate: Bool {
        return !proto.date.isEmpty
    }

    public var policy: String? {
        guard hasPolicy else {
            return nil
        }
        return proto.policy
    }
    public var hasPolicy: Bool {
        return !proto.policy.isEmpty
    }

    public var signature: String? {
        guard hasSignature else {
            return nil
        }
        return proto.signature
    }
    public var hasSignature: Bool {
        return !proto.signature.isEmpty
    }

    private init(proto: GroupsProtos_AvatarUploadAttributes) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoAvatarUploadAttributes {
        let proto = try GroupsProtos_AvatarUploadAttributes(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_AvatarUploadAttributes) throws -> GroupsProtoAvatarUploadAttributes {
        // MARK: - Begin Validation Logic for GroupsProtoAvatarUploadAttributes -

        // MARK: - End Validation Logic for GroupsProtoAvatarUploadAttributes -

        let result = GroupsProtoAvatarUploadAttributes(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoAvatarUploadAttributes {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoAvatarUploadAttributes.GroupsProtoAvatarUploadAttributesBuilder {
    public func buildIgnoringErrors() -> GroupsProtoAvatarUploadAttributes? {
        return try! self.build()
    }
}

#endif

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
        if hasJoinedAtRevision {
            builder.setJoinedAtRevision(joinedAtRevision)
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

        public func setJoinedAtRevision(_ valueParam: UInt32) {
            proto.joinedAtRevision = valueParam
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
        return !proto.userID.isEmpty
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
        return !proto.profileKey.isEmpty
    }

    public var presentation: Data? {
        guard hasPresentation else {
            return nil
        }
        return proto.presentation
    }
    public var hasPresentation: Bool {
        return !proto.presentation.isEmpty
    }

    public var joinedAtRevision: UInt32 {
        return proto.joinedAtRevision
    }
    public var hasJoinedAtRevision: Bool {
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

// MARK: - GroupsProtoPendingMember

public class GroupsProtoPendingMember: NSObject {

    // MARK: - GroupsProtoPendingMemberBuilder

    public class func builder() -> GroupsProtoPendingMemberBuilder {
        return GroupsProtoPendingMemberBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoPendingMemberBuilder {
        let builder = GroupsProtoPendingMemberBuilder()
        if let _value = member {
            builder.setMember(_value)
        }
        if let _value = addedByUserID {
            builder.setAddedByUserID(_value)
        }
        if hasTimestamp {
            builder.setTimestamp(timestamp)
        }
        return builder
    }

    public class GroupsProtoPendingMemberBuilder: NSObject {

        private var proto = GroupsProtos_PendingMember()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setMember(_ valueParam: GroupsProtoMember?) {
            guard let valueParam = valueParam else { return }
            proto.member = valueParam.proto
        }

        public func setMember(_ valueParam: GroupsProtoMember) {
            proto.member = valueParam.proto
        }

        @available(swift, obsoleted: 1.0)
        public func setAddedByUserID(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.addedByUserID = valueParam
        }

        public func setAddedByUserID(_ valueParam: Data) {
            proto.addedByUserID = valueParam
        }

        public func setTimestamp(_ valueParam: UInt64) {
            proto.timestamp = valueParam
        }

        public func build() throws -> GroupsProtoPendingMember {
            return try GroupsProtoPendingMember.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoPendingMember.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_PendingMember

    public let member: GroupsProtoMember?

    public var addedByUserID: Data? {
        guard hasAddedByUserID else {
            return nil
        }
        return proto.addedByUserID
    }
    public var hasAddedByUserID: Bool {
        return !proto.addedByUserID.isEmpty
    }

    public var timestamp: UInt64 {
        return proto.timestamp
    }
    public var hasTimestamp: Bool {
        return true
    }

    private init(proto: GroupsProtos_PendingMember,
                 member: GroupsProtoMember?) {
        self.proto = proto
        self.member = member
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoPendingMember {
        let proto = try GroupsProtos_PendingMember(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_PendingMember) throws -> GroupsProtoPendingMember {
        var member: GroupsProtoMember?
        if proto.hasMember {
            member = try GroupsProtoMember.parseProto(proto.member)
        }

        // MARK: - Begin Validation Logic for GroupsProtoPendingMember -

        // MARK: - End Validation Logic for GroupsProtoPendingMember -

        let result = GroupsProtoPendingMember(proto: proto,
                                              member: member)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoPendingMember {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoPendingMember.GroupsProtoPendingMemberBuilder {
    public func buildIgnoringErrors() -> GroupsProtoPendingMember? {
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
        if let _value = attributes {
            builder.setAttributes(_value)
        }
        if let _value = members {
            builder.setMembers(_value)
        }
        return builder
    }

    public class GroupsProtoAccessControlBuilder: NSObject {

        private var proto = GroupsProtos_AccessControl()

        fileprivate override init() {}

        public func setAttributes(_ valueParam: GroupsProtoAccessControlAccessRequired) {
            proto.attributes = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
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

    public var attributes: GroupsProtoAccessControlAccessRequired? {
        guard hasAttributes else {
            return nil
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.attributes)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedAttributes: GroupsProtoAccessControlAccessRequired {
        if !hasAttributes {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: AccessControl.attributes.")
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.attributes)
    }
    public var hasAttributes: Bool {
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
        if let _value = disappearingMessagesTimer {
            builder.setDisappearingMessagesTimer(_value)
        }
        if let _value = accessControl {
            builder.setAccessControl(_value)
        }
        if hasRevision {
            builder.setRevision(revision)
        }
        builder.setMembers(members)
        builder.setPendingMembers(pendingMembers)
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
        public func setAvatar(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.avatar = valueParam
        }

        public func setAvatar(_ valueParam: String) {
            proto.avatar = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setDisappearingMessagesTimer(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.disappearingMessagesTimer = valueParam
        }

        public func setDisappearingMessagesTimer(_ valueParam: Data) {
            proto.disappearingMessagesTimer = valueParam
        }

        @available(swift, obsoleted: 1.0)
        public func setAccessControl(_ valueParam: GroupsProtoAccessControl?) {
            guard let valueParam = valueParam else { return }
            proto.accessControl = valueParam.proto
        }

        public func setAccessControl(_ valueParam: GroupsProtoAccessControl) {
            proto.accessControl = valueParam.proto
        }

        public func setRevision(_ valueParam: UInt32) {
            proto.revision = valueParam
        }

        public func addMembers(_ valueParam: GroupsProtoMember) {
            var items = proto.members
            items.append(valueParam.proto)
            proto.members = items
        }

        public func setMembers(_ wrappedItems: [GroupsProtoMember]) {
            proto.members = wrappedItems.map { $0.proto }
        }

        public func addPendingMembers(_ valueParam: GroupsProtoPendingMember) {
            var items = proto.pendingMembers
            items.append(valueParam.proto)
            proto.pendingMembers = items
        }

        public func setPendingMembers(_ wrappedItems: [GroupsProtoPendingMember]) {
            proto.pendingMembers = wrappedItems.map { $0.proto }
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

    public let pendingMembers: [GroupsProtoPendingMember]

    public var publicKey: Data? {
        guard hasPublicKey else {
            return nil
        }
        return proto.publicKey
    }
    public var hasPublicKey: Bool {
        return !proto.publicKey.isEmpty
    }

    public var title: Data? {
        guard hasTitle else {
            return nil
        }
        return proto.title
    }
    public var hasTitle: Bool {
        return !proto.title.isEmpty
    }

    public var avatar: String? {
        guard hasAvatar else {
            return nil
        }
        return proto.avatar
    }
    public var hasAvatar: Bool {
        return !proto.avatar.isEmpty
    }

    public var disappearingMessagesTimer: Data? {
        guard hasDisappearingMessagesTimer else {
            return nil
        }
        return proto.disappearingMessagesTimer
    }
    public var hasDisappearingMessagesTimer: Bool {
        return !proto.disappearingMessagesTimer.isEmpty
    }

    public var revision: UInt32 {
        return proto.revision
    }
    public var hasRevision: Bool {
        return true
    }

    private init(proto: GroupsProtos_Group,
                 accessControl: GroupsProtoAccessControl?,
                 members: [GroupsProtoMember],
                 pendingMembers: [GroupsProtoPendingMember]) {
        self.proto = proto
        self.accessControl = accessControl
        self.members = members
        self.pendingMembers = pendingMembers
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
        var accessControl: GroupsProtoAccessControl?
        if proto.hasAccessControl {
            accessControl = try GroupsProtoAccessControl.parseProto(proto.accessControl)
        }

        var members: [GroupsProtoMember] = []
        members = try proto.members.map { try GroupsProtoMember.parseProto($0) }

        var pendingMembers: [GroupsProtoPendingMember] = []
        pendingMembers = try proto.pendingMembers.map { try GroupsProtoPendingMember.parseProto($0) }

        // MARK: - Begin Validation Logic for GroupsProtoGroup -

        // MARK: - End Validation Logic for GroupsProtoGroup -

        let result = GroupsProtoGroup(proto: proto,
                                      accessControl: accessControl,
                                      members: members,
                                      pendingMembers: pendingMembers)
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
        var added: GroupsProtoMember?
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
        if let _value = deletedUserID {
            builder.setDeletedUserID(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsDeleteMemberActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.DeleteMemberAction()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setDeletedUserID(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.deletedUserID = valueParam
        }

        public func setDeletedUserID(_ valueParam: Data) {
            proto.deletedUserID = valueParam
        }

        public func build() throws -> GroupsProtoGroupChangeActionsDeleteMemberAction {
            return try GroupsProtoGroupChangeActionsDeleteMemberAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsDeleteMemberAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.DeleteMemberAction

    public var deletedUserID: Data? {
        guard hasDeletedUserID else {
            return nil
        }
        return proto.deletedUserID
    }
    public var hasDeletedUserID: Bool {
        return !proto.deletedUserID.isEmpty
    }

    private init(proto: GroupsProtos_GroupChange.Actions.DeleteMemberAction) {
        self.proto = proto
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
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsDeleteMemberAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsDeleteMemberAction -

        let result = GroupsProtoGroupChangeActionsDeleteMemberAction(proto: proto)
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
        return !proto.userID.isEmpty
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

// MARK: - GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction

public class GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyMemberProfileKeyActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsModifyMemberProfileKeyActionBuilder {
        return GroupsProtoGroupChangeActionsModifyMemberProfileKeyActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyMemberProfileKeyActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyMemberProfileKeyActionBuilder()
        if let _value = presentation {
            builder.setPresentation(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsModifyMemberProfileKeyActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyMemberProfileKeyAction()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setPresentation(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.presentation = valueParam
        }

        public func setPresentation(_ valueParam: Data) {
            proto.presentation = valueParam
        }

        public func build() throws -> GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction {
            return try GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyMemberProfileKeyAction

    public var presentation: Data? {
        guard hasPresentation else {
            return nil
        }
        return proto.presentation
    }
    public var hasPresentation: Bool {
        return !proto.presentation.isEmpty
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyMemberProfileKeyAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyMemberProfileKeyAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyMemberProfileKeyAction) throws -> GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction -

        let result = GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction.GroupsProtoGroupChangeActionsModifyMemberProfileKeyActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsAddPendingMemberAction

public class GroupsProtoGroupChangeActionsAddPendingMemberAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsAddPendingMemberActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsAddPendingMemberActionBuilder {
        return GroupsProtoGroupChangeActionsAddPendingMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsAddPendingMemberActionBuilder {
        let builder = GroupsProtoGroupChangeActionsAddPendingMemberActionBuilder()
        if let _value = added {
            builder.setAdded(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsAddPendingMemberActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.AddPendingMemberAction()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setAdded(_ valueParam: GroupsProtoPendingMember?) {
            guard let valueParam = valueParam else { return }
            proto.added = valueParam.proto
        }

        public func setAdded(_ valueParam: GroupsProtoPendingMember) {
            proto.added = valueParam.proto
        }

        public func build() throws -> GroupsProtoGroupChangeActionsAddPendingMemberAction {
            return try GroupsProtoGroupChangeActionsAddPendingMemberAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsAddPendingMemberAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.AddPendingMemberAction

    public let added: GroupsProtoPendingMember?

    private init(proto: GroupsProtos_GroupChange.Actions.AddPendingMemberAction,
                 added: GroupsProtoPendingMember?) {
        self.proto = proto
        self.added = added
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsAddPendingMemberAction {
        let proto = try GroupsProtos_GroupChange.Actions.AddPendingMemberAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.AddPendingMemberAction) throws -> GroupsProtoGroupChangeActionsAddPendingMemberAction {
        var added: GroupsProtoPendingMember?
        if proto.hasAdded {
            added = try GroupsProtoPendingMember.parseProto(proto.added)
        }

        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsAddPendingMemberAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsAddPendingMemberAction -

        let result = GroupsProtoGroupChangeActionsAddPendingMemberAction(proto: proto,
                                                                         added: added)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsAddPendingMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsAddPendingMemberAction.GroupsProtoGroupChangeActionsAddPendingMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsAddPendingMemberAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsDeletePendingMemberAction

public class GroupsProtoGroupChangeActionsDeletePendingMemberAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsDeletePendingMemberActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsDeletePendingMemberActionBuilder {
        return GroupsProtoGroupChangeActionsDeletePendingMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsDeletePendingMemberActionBuilder {
        let builder = GroupsProtoGroupChangeActionsDeletePendingMemberActionBuilder()
        if let _value = deletedUserID {
            builder.setDeletedUserID(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsDeletePendingMemberActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.DeletePendingMemberAction()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setDeletedUserID(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.deletedUserID = valueParam
        }

        public func setDeletedUserID(_ valueParam: Data) {
            proto.deletedUserID = valueParam
        }

        public func build() throws -> GroupsProtoGroupChangeActionsDeletePendingMemberAction {
            return try GroupsProtoGroupChangeActionsDeletePendingMemberAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsDeletePendingMemberAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.DeletePendingMemberAction

    public var deletedUserID: Data? {
        guard hasDeletedUserID else {
            return nil
        }
        return proto.deletedUserID
    }
    public var hasDeletedUserID: Bool {
        return !proto.deletedUserID.isEmpty
    }

    private init(proto: GroupsProtos_GroupChange.Actions.DeletePendingMemberAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsDeletePendingMemberAction {
        let proto = try GroupsProtos_GroupChange.Actions.DeletePendingMemberAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.DeletePendingMemberAction) throws -> GroupsProtoGroupChangeActionsDeletePendingMemberAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsDeletePendingMemberAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsDeletePendingMemberAction -

        let result = GroupsProtoGroupChangeActionsDeletePendingMemberAction(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsDeletePendingMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsDeletePendingMemberAction.GroupsProtoGroupChangeActionsDeletePendingMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsDeletePendingMemberAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsPromotePendingMemberAction

public class GroupsProtoGroupChangeActionsPromotePendingMemberAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsPromotePendingMemberActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsPromotePendingMemberActionBuilder {
        return GroupsProtoGroupChangeActionsPromotePendingMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsPromotePendingMemberActionBuilder {
        let builder = GroupsProtoGroupChangeActionsPromotePendingMemberActionBuilder()
        if let _value = presentation {
            builder.setPresentation(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsPromotePendingMemberActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.PromotePendingMemberAction()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setPresentation(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.presentation = valueParam
        }

        public func setPresentation(_ valueParam: Data) {
            proto.presentation = valueParam
        }

        public func build() throws -> GroupsProtoGroupChangeActionsPromotePendingMemberAction {
            return try GroupsProtoGroupChangeActionsPromotePendingMemberAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsPromotePendingMemberAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.PromotePendingMemberAction

    public var presentation: Data? {
        guard hasPresentation else {
            return nil
        }
        return proto.presentation
    }
    public var hasPresentation: Bool {
        return !proto.presentation.isEmpty
    }

    private init(proto: GroupsProtos_GroupChange.Actions.PromotePendingMemberAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsPromotePendingMemberAction {
        let proto = try GroupsProtos_GroupChange.Actions.PromotePendingMemberAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.PromotePendingMemberAction) throws -> GroupsProtoGroupChangeActionsPromotePendingMemberAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsPromotePendingMemberAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsPromotePendingMemberAction -

        let result = GroupsProtoGroupChangeActionsPromotePendingMemberAction(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsPromotePendingMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsPromotePendingMemberAction.GroupsProtoGroupChangeActionsPromotePendingMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsPromotePendingMemberAction? {
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
        return !proto.title.isEmpty
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
        public func setAvatar(_ valueParam: String?) {
            guard let valueParam = valueParam else { return }
            proto.avatar = valueParam
        }

        public func setAvatar(_ valueParam: String) {
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

    public var avatar: String? {
        guard hasAvatar else {
            return nil
        }
        return proto.avatar
    }
    public var hasAvatar: Bool {
        return !proto.avatar.isEmpty
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

// MARK: - GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction

public class GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerActionBuilder {
        return GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerActionBuilder()
        if let _value = timer {
            builder.setTimer(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyDisappearingMessagesTimerAction()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setTimer(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.timer = valueParam
        }

        public func setTimer(_ valueParam: Data) {
            proto.timer = valueParam
        }

        public func build() throws -> GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction {
            return try GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyDisappearingMessagesTimerAction

    public var timer: Data? {
        guard hasTimer else {
            return nil
        }
        return proto.timer
    }
    public var hasTimer: Bool {
        return !proto.timer.isEmpty
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyDisappearingMessagesTimerAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyDisappearingMessagesTimerAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyDisappearingMessagesTimerAction) throws -> GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction -

        let result = GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction.GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction

public class GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction: NSObject {

    // MARK: - GroupsProtoGroupChangeActionsModifyAttributesAccessControlActionBuilder

    public class func builder() -> GroupsProtoGroupChangeActionsModifyAttributesAccessControlActionBuilder {
        return GroupsProtoGroupChangeActionsModifyAttributesAccessControlActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyAttributesAccessControlActionBuilder {
        let builder = GroupsProtoGroupChangeActionsModifyAttributesAccessControlActionBuilder()
        if let _value = attributesAccess {
            builder.setAttributesAccess(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangeActionsModifyAttributesAccessControlActionBuilder: NSObject {

        private var proto = GroupsProtos_GroupChange.Actions.ModifyAttributesAccessControlAction()

        fileprivate override init() {}

        public func setAttributesAccess(_ valueParam: GroupsProtoAccessControlAccessRequired) {
            proto.attributesAccess = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
        }

        public func build() throws -> GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction {
            return try GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyAttributesAccessControlAction

    public var attributesAccess: GroupsProtoAccessControlAccessRequired? {
        guard hasAttributesAccess else {
            return nil
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.attributesAccess)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedAttributesAccess: GroupsProtoAccessControlAccessRequired {
        if !hasAttributesAccess {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: ModifyAttributesAccessControlAction.attributesAccess.")
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.attributesAccess)
    }
    public var hasAttributesAccess: Bool {
        return true
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyAttributesAccessControlAction) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyAttributesAccessControlAction(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChange.Actions.ModifyAttributesAccessControlAction) throws -> GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction {
        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction -

        let result = GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction.GroupsProtoGroupChangeActionsModifyAttributesAccessControlActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction? {
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
        if let _value = sourceUuid {
            builder.setSourceUuid(_value)
        }
        if hasRevision {
            builder.setRevision(revision)
        }
        builder.setAddMembers(addMembers)
        builder.setDeleteMembers(deleteMembers)
        builder.setModifyMemberRoles(modifyMemberRoles)
        builder.setModifyMemberProfileKeys(modifyMemberProfileKeys)
        builder.setAddPendingMembers(addPendingMembers)
        builder.setDeletePendingMembers(deletePendingMembers)
        builder.setPromotePendingMembers(promotePendingMembers)
        if let _value = modifyTitle {
            builder.setModifyTitle(_value)
        }
        if let _value = modifyAvatar {
            builder.setModifyAvatar(_value)
        }
        if let _value = modifyDisappearingMessagesTimer {
            builder.setModifyDisappearingMessagesTimer(_value)
        }
        if let _value = modifyAttributesAccess {
            builder.setModifyAttributesAccess(_value)
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
        public func setSourceUuid(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.sourceUuid = valueParam
        }

        public func setSourceUuid(_ valueParam: Data) {
            proto.sourceUuid = valueParam
        }

        public func setRevision(_ valueParam: UInt32) {
            proto.revision = valueParam
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

        public func addModifyMemberRoles(_ valueParam: GroupsProtoGroupChangeActionsModifyMemberRoleAction) {
            var items = proto.modifyMemberRoles
            items.append(valueParam.proto)
            proto.modifyMemberRoles = items
        }

        public func setModifyMemberRoles(_ wrappedItems: [GroupsProtoGroupChangeActionsModifyMemberRoleAction]) {
            proto.modifyMemberRoles = wrappedItems.map { $0.proto }
        }

        public func addModifyMemberProfileKeys(_ valueParam: GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction) {
            var items = proto.modifyMemberProfileKeys
            items.append(valueParam.proto)
            proto.modifyMemberProfileKeys = items
        }

        public func setModifyMemberProfileKeys(_ wrappedItems: [GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction]) {
            proto.modifyMemberProfileKeys = wrappedItems.map { $0.proto }
        }

        public func addAddPendingMembers(_ valueParam: GroupsProtoGroupChangeActionsAddPendingMemberAction) {
            var items = proto.addPendingMembers
            items.append(valueParam.proto)
            proto.addPendingMembers = items
        }

        public func setAddPendingMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsAddPendingMemberAction]) {
            proto.addPendingMembers = wrappedItems.map { $0.proto }
        }

        public func addDeletePendingMembers(_ valueParam: GroupsProtoGroupChangeActionsDeletePendingMemberAction) {
            var items = proto.deletePendingMembers
            items.append(valueParam.proto)
            proto.deletePendingMembers = items
        }

        public func setDeletePendingMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsDeletePendingMemberAction]) {
            proto.deletePendingMembers = wrappedItems.map { $0.proto }
        }

        public func addPromotePendingMembers(_ valueParam: GroupsProtoGroupChangeActionsPromotePendingMemberAction) {
            var items = proto.promotePendingMembers
            items.append(valueParam.proto)
            proto.promotePendingMembers = items
        }

        public func setPromotePendingMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsPromotePendingMemberAction]) {
            proto.promotePendingMembers = wrappedItems.map { $0.proto }
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
        public func setModifyDisappearingMessagesTimer(_ valueParam: GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction?) {
            guard let valueParam = valueParam else { return }
            proto.modifyDisappearingMessagesTimer = valueParam.proto
        }

        public func setModifyDisappearingMessagesTimer(_ valueParam: GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction) {
            proto.modifyDisappearingMessagesTimer = valueParam.proto
        }

        @available(swift, obsoleted: 1.0)
        public func setModifyAttributesAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction?) {
            guard let valueParam = valueParam else { return }
            proto.modifyAttributesAccess = valueParam.proto
        }

        public func setModifyAttributesAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction) {
            proto.modifyAttributesAccess = valueParam.proto
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

    public let addMembers: [GroupsProtoGroupChangeActionsAddMemberAction]

    public let deleteMembers: [GroupsProtoGroupChangeActionsDeleteMemberAction]

    public let modifyMemberRoles: [GroupsProtoGroupChangeActionsModifyMemberRoleAction]

    public let modifyMemberProfileKeys: [GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction]

    public let addPendingMembers: [GroupsProtoGroupChangeActionsAddPendingMemberAction]

    public let deletePendingMembers: [GroupsProtoGroupChangeActionsDeletePendingMemberAction]

    public let promotePendingMembers: [GroupsProtoGroupChangeActionsPromotePendingMemberAction]

    public let modifyTitle: GroupsProtoGroupChangeActionsModifyTitleAction?

    public let modifyAvatar: GroupsProtoGroupChangeActionsModifyAvatarAction?

    public let modifyDisappearingMessagesTimer: GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction?

    public let modifyAttributesAccess: GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction?

    public let modifyMemberAccess: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction?

    public var sourceUuid: Data? {
        guard hasSourceUuid else {
            return nil
        }
        return proto.sourceUuid
    }
    public var hasSourceUuid: Bool {
        return !proto.sourceUuid.isEmpty
    }

    public var revision: UInt32 {
        return proto.revision
    }
    public var hasRevision: Bool {
        return true
    }

    private init(proto: GroupsProtos_GroupChange.Actions,
                 addMembers: [GroupsProtoGroupChangeActionsAddMemberAction],
                 deleteMembers: [GroupsProtoGroupChangeActionsDeleteMemberAction],
                 modifyMemberRoles: [GroupsProtoGroupChangeActionsModifyMemberRoleAction],
                 modifyMemberProfileKeys: [GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction],
                 addPendingMembers: [GroupsProtoGroupChangeActionsAddPendingMemberAction],
                 deletePendingMembers: [GroupsProtoGroupChangeActionsDeletePendingMemberAction],
                 promotePendingMembers: [GroupsProtoGroupChangeActionsPromotePendingMemberAction],
                 modifyTitle: GroupsProtoGroupChangeActionsModifyTitleAction?,
                 modifyAvatar: GroupsProtoGroupChangeActionsModifyAvatarAction?,
                 modifyDisappearingMessagesTimer: GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction?,
                 modifyAttributesAccess: GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction?,
                 modifyMemberAccess: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction?) {
        self.proto = proto
        self.addMembers = addMembers
        self.deleteMembers = deleteMembers
        self.modifyMemberRoles = modifyMemberRoles
        self.modifyMemberProfileKeys = modifyMemberProfileKeys
        self.addPendingMembers = addPendingMembers
        self.deletePendingMembers = deletePendingMembers
        self.promotePendingMembers = promotePendingMembers
        self.modifyTitle = modifyTitle
        self.modifyAvatar = modifyAvatar
        self.modifyDisappearingMessagesTimer = modifyDisappearingMessagesTimer
        self.modifyAttributesAccess = modifyAttributesAccess
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
        var addMembers: [GroupsProtoGroupChangeActionsAddMemberAction] = []
        addMembers = try proto.addMembers.map { try GroupsProtoGroupChangeActionsAddMemberAction.parseProto($0) }

        var deleteMembers: [GroupsProtoGroupChangeActionsDeleteMemberAction] = []
        deleteMembers = try proto.deleteMembers.map { try GroupsProtoGroupChangeActionsDeleteMemberAction.parseProto($0) }

        var modifyMemberRoles: [GroupsProtoGroupChangeActionsModifyMemberRoleAction] = []
        modifyMemberRoles = try proto.modifyMemberRoles.map { try GroupsProtoGroupChangeActionsModifyMemberRoleAction.parseProto($0) }

        var modifyMemberProfileKeys: [GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction] = []
        modifyMemberProfileKeys = try proto.modifyMemberProfileKeys.map { try GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction.parseProto($0) }

        var addPendingMembers: [GroupsProtoGroupChangeActionsAddPendingMemberAction] = []
        addPendingMembers = try proto.addPendingMembers.map { try GroupsProtoGroupChangeActionsAddPendingMemberAction.parseProto($0) }

        var deletePendingMembers: [GroupsProtoGroupChangeActionsDeletePendingMemberAction] = []
        deletePendingMembers = try proto.deletePendingMembers.map { try GroupsProtoGroupChangeActionsDeletePendingMemberAction.parseProto($0) }

        var promotePendingMembers: [GroupsProtoGroupChangeActionsPromotePendingMemberAction] = []
        promotePendingMembers = try proto.promotePendingMembers.map { try GroupsProtoGroupChangeActionsPromotePendingMemberAction.parseProto($0) }

        var modifyTitle: GroupsProtoGroupChangeActionsModifyTitleAction?
        if proto.hasModifyTitle {
            modifyTitle = try GroupsProtoGroupChangeActionsModifyTitleAction.parseProto(proto.modifyTitle)
        }

        var modifyAvatar: GroupsProtoGroupChangeActionsModifyAvatarAction?
        if proto.hasModifyAvatar {
            modifyAvatar = try GroupsProtoGroupChangeActionsModifyAvatarAction.parseProto(proto.modifyAvatar)
        }

        var modifyDisappearingMessagesTimer: GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction?
        if proto.hasModifyDisappearingMessagesTimer {
            modifyDisappearingMessagesTimer = try GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction.parseProto(proto.modifyDisappearingMessagesTimer)
        }

        var modifyAttributesAccess: GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction?
        if proto.hasModifyAttributesAccess {
            modifyAttributesAccess = try GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction.parseProto(proto.modifyAttributesAccess)
        }

        var modifyMemberAccess: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction?
        if proto.hasModifyMemberAccess {
            modifyMemberAccess = try GroupsProtoGroupChangeActionsModifyMembersAccessControlAction.parseProto(proto.modifyMemberAccess)
        }

        // MARK: - Begin Validation Logic for GroupsProtoGroupChangeActions -

        // MARK: - End Validation Logic for GroupsProtoGroupChangeActions -

        let result = GroupsProtoGroupChangeActions(proto: proto,
                                                   addMembers: addMembers,
                                                   deleteMembers: deleteMembers,
                                                   modifyMemberRoles: modifyMemberRoles,
                                                   modifyMemberProfileKeys: modifyMemberProfileKeys,
                                                   addPendingMembers: addPendingMembers,
                                                   deletePendingMembers: deletePendingMembers,
                                                   promotePendingMembers: promotePendingMembers,
                                                   modifyTitle: modifyTitle,
                                                   modifyAvatar: modifyAvatar,
                                                   modifyDisappearingMessagesTimer: modifyDisappearingMessagesTimer,
                                                   modifyAttributesAccess: modifyAttributesAccess,
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
        if hasChangeEpoch {
            builder.setChangeEpoch(changeEpoch)
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

        public func setChangeEpoch(_ valueParam: UInt32) {
            proto.changeEpoch = valueParam
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
        return !proto.actions.isEmpty
    }

    public var serverSignature: Data? {
        guard hasServerSignature else {
            return nil
        }
        return proto.serverSignature
    }
    public var hasServerSignature: Bool {
        return !proto.serverSignature.isEmpty
    }

    public var changeEpoch: UInt32 {
        return proto.changeEpoch
    }
    public var hasChangeEpoch: Bool {
        return true
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

// MARK: - GroupsProtoGroupChangesGroupChangeState

public class GroupsProtoGroupChangesGroupChangeState: NSObject {

    // MARK: - GroupsProtoGroupChangesGroupChangeStateBuilder

    public class func builder() -> GroupsProtoGroupChangesGroupChangeStateBuilder {
        return GroupsProtoGroupChangesGroupChangeStateBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangesGroupChangeStateBuilder {
        let builder = GroupsProtoGroupChangesGroupChangeStateBuilder()
        if let _value = groupChange {
            builder.setGroupChange(_value)
        }
        if let _value = groupState {
            builder.setGroupState(_value)
        }
        return builder
    }

    public class GroupsProtoGroupChangesGroupChangeStateBuilder: NSObject {

        private var proto = GroupsProtos_GroupChanges.GroupChangeState()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setGroupChange(_ valueParam: GroupsProtoGroupChange?) {
            guard let valueParam = valueParam else { return }
            proto.groupChange = valueParam.proto
        }

        public func setGroupChange(_ valueParam: GroupsProtoGroupChange) {
            proto.groupChange = valueParam.proto
        }

        @available(swift, obsoleted: 1.0)
        public func setGroupState(_ valueParam: GroupsProtoGroup?) {
            guard let valueParam = valueParam else { return }
            proto.groupState = valueParam.proto
        }

        public func setGroupState(_ valueParam: GroupsProtoGroup) {
            proto.groupState = valueParam.proto
        }

        public func build() throws -> GroupsProtoGroupChangesGroupChangeState {
            return try GroupsProtoGroupChangesGroupChangeState.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChangesGroupChangeState.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChanges.GroupChangeState

    public let groupChange: GroupsProtoGroupChange?

    public let groupState: GroupsProtoGroup?

    private init(proto: GroupsProtos_GroupChanges.GroupChangeState,
                 groupChange: GroupsProtoGroupChange?,
                 groupState: GroupsProtoGroup?) {
        self.proto = proto
        self.groupChange = groupChange
        self.groupState = groupState
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChangesGroupChangeState {
        let proto = try GroupsProtos_GroupChanges.GroupChangeState(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChanges.GroupChangeState) throws -> GroupsProtoGroupChangesGroupChangeState {
        var groupChange: GroupsProtoGroupChange?
        if proto.hasGroupChange {
            groupChange = try GroupsProtoGroupChange.parseProto(proto.groupChange)
        }

        var groupState: GroupsProtoGroup?
        if proto.hasGroupState {
            groupState = try GroupsProtoGroup.parseProto(proto.groupState)
        }

        // MARK: - Begin Validation Logic for GroupsProtoGroupChangesGroupChangeState -

        // MARK: - End Validation Logic for GroupsProtoGroupChangesGroupChangeState -

        let result = GroupsProtoGroupChangesGroupChangeState(proto: proto,
                                                             groupChange: groupChange,
                                                             groupState: groupState)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChangesGroupChangeState {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangesGroupChangeState.GroupsProtoGroupChangesGroupChangeStateBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangesGroupChangeState? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupChanges

public class GroupsProtoGroupChanges: NSObject {

    // MARK: - GroupsProtoGroupChangesBuilder

    public class func builder() -> GroupsProtoGroupChangesBuilder {
        return GroupsProtoGroupChangesBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangesBuilder {
        let builder = GroupsProtoGroupChangesBuilder()
        builder.setGroupChanges(groupChanges)
        return builder
    }

    public class GroupsProtoGroupChangesBuilder: NSObject {

        private var proto = GroupsProtos_GroupChanges()

        fileprivate override init() {}

        public func addGroupChanges(_ valueParam: GroupsProtoGroupChangesGroupChangeState) {
            var items = proto.groupChanges
            items.append(valueParam.proto)
            proto.groupChanges = items
        }

        public func setGroupChanges(_ wrappedItems: [GroupsProtoGroupChangesGroupChangeState]) {
            proto.groupChanges = wrappedItems.map { $0.proto }
        }

        public func build() throws -> GroupsProtoGroupChanges {
            return try GroupsProtoGroupChanges.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupChanges.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupChanges

    public let groupChanges: [GroupsProtoGroupChangesGroupChangeState]

    private init(proto: GroupsProtos_GroupChanges,
                 groupChanges: [GroupsProtoGroupChangesGroupChangeState]) {
        self.proto = proto
        self.groupChanges = groupChanges
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupChanges {
        let proto = try GroupsProtos_GroupChanges(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupChanges) throws -> GroupsProtoGroupChanges {
        var groupChanges: [GroupsProtoGroupChangesGroupChangeState] = []
        groupChanges = try proto.groupChanges.map { try GroupsProtoGroupChangesGroupChangeState.parseProto($0) }

        // MARK: - Begin Validation Logic for GroupsProtoGroupChanges -

        // MARK: - End Validation Logic for GroupsProtoGroupChanges -

        let result = GroupsProtoGroupChanges(proto: proto,
                                             groupChanges: groupChanges)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupChanges {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChanges.GroupsProtoGroupChangesBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChanges? {
        return try! self.build()
    }
}

#endif

// MARK: - GroupsProtoGroupAttributeBlobOneOfContent

public enum GroupsProtoGroupAttributeBlobOneOfContent: Equatable {
    case title(String)
    case avatar(Data)
    case disappearingMessagesDuration(UInt32)
}

private func GroupsProtoGroupAttributeBlobOneOfContentWrap(_ value: GroupsProtos_GroupAttributeBlob.OneOf_Content) throws -> GroupsProtoGroupAttributeBlobOneOfContent {
    switch value {
    case .title(let value): return .title(value)
    case .avatar(let value): return .avatar(value)
    case .disappearingMessagesDuration(let value): return .disappearingMessagesDuration(value)
    }
}

private func GroupsProtoGroupAttributeBlobOneOfContentUnwrap(_ value: GroupsProtoGroupAttributeBlobOneOfContent) -> GroupsProtos_GroupAttributeBlob.OneOf_Content {
    switch value {
    case .title(let value): return .title(value)
    case .avatar(let value): return .avatar(value)
    case .disappearingMessagesDuration(let value): return .disappearingMessagesDuration(value)
    }
}

// MARK: - GroupsProtoGroupAttributeBlob

public class GroupsProtoGroupAttributeBlob: NSObject {

    // MARK: - GroupsProtoGroupAttributeBlobBuilder

    public class func builder() -> GroupsProtoGroupAttributeBlobBuilder {
        return GroupsProtoGroupAttributeBlobBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupAttributeBlobBuilder {
        let builder = GroupsProtoGroupAttributeBlobBuilder()
        if let _value = content {
            builder.setContent(_value)
        }
        return builder
    }

    public class GroupsProtoGroupAttributeBlobBuilder: NSObject {

        private var proto = GroupsProtos_GroupAttributeBlob()

        fileprivate override init() {}

        @available(swift, obsoleted: 1.0)
        public func setContent(_ valueParam: GroupsProtoGroupAttributeBlobOneOfContent?) {
            guard let valueParam = valueParam else { return }
            proto.content = GroupsProtoGroupAttributeBlobOneOfContentUnwrap(valueParam)
        }

        public func setContent(_ valueParam: GroupsProtoGroupAttributeBlobOneOfContent) {
            proto.content = GroupsProtoGroupAttributeBlobOneOfContentUnwrap(valueParam)
        }

        public func build() throws -> GroupsProtoGroupAttributeBlob {
            return try GroupsProtoGroupAttributeBlob.parseProto(proto)
        }

        public func buildSerializedData() throws -> Data {
            return try GroupsProtoGroupAttributeBlob.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: GroupsProtos_GroupAttributeBlob

    public var content: GroupsProtoGroupAttributeBlobOneOfContent? {
        guard hasContent else {
            return nil
        }
        guard let content = proto.content else {
            owsFailDebug("content was unexpectedly nil")
            return nil
        }
        guard let unwrappedContent = try? GroupsProtoGroupAttributeBlobOneOfContentWrap(content) else {
            owsFailDebug("failed to unwrap content")
            return nil
        }
        return unwrappedContent
    }
    public var hasContent: Bool {
        return true
    }

    private init(proto: GroupsProtos_GroupAttributeBlob) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public class func parseData(_ serializedData: Data) throws -> GroupsProtoGroupAttributeBlob {
        let proto = try GroupsProtos_GroupAttributeBlob(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: GroupsProtos_GroupAttributeBlob) throws -> GroupsProtoGroupAttributeBlob {
        // MARK: - Begin Validation Logic for GroupsProtoGroupAttributeBlob -

        // MARK: - End Validation Logic for GroupsProtoGroupAttributeBlob -

        let result = GroupsProtoGroupAttributeBlob(proto: proto)
        return result
    }

    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension GroupsProtoGroupAttributeBlob {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupAttributeBlob.GroupsProtoGroupAttributeBlobBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupAttributeBlob? {
        return try! self.build()
    }
}

#endif
