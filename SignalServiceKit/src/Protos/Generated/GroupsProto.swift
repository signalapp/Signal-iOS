//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum GroupsProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - GroupsProtoAvatarUploadAttributes

public struct GroupsProtoAvatarUploadAttributes: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_AvatarUploadAttributes) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_AvatarUploadAttributes(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_AvatarUploadAttributes) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoAvatarUploadAttributes {
    public static func builder() -> GroupsProtoAvatarUploadAttributesBuilder {
        return GroupsProtoAvatarUploadAttributesBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoAvatarUploadAttributesBuilder {
        var builder = GroupsProtoAvatarUploadAttributesBuilder()
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
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoAvatarUploadAttributesBuilder {

    private var proto = GroupsProtos_AvatarUploadAttributes()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setKey(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.key = valueParam
    }

    public mutating func setKey(_ valueParam: String) {
        proto.key = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setCredential(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.credential = valueParam
    }

    public mutating func setCredential(_ valueParam: String) {
        proto.credential = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setAcl(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.acl = valueParam
    }

    public mutating func setAcl(_ valueParam: String) {
        proto.acl = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setAlgorithm(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.algorithm = valueParam
    }

    public mutating func setAlgorithm(_ valueParam: String) {
        proto.algorithm = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setDate(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.date = valueParam
    }

    public mutating func setDate(_ valueParam: String) {
        proto.date = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setPolicy(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.policy = valueParam
    }

    public mutating func setPolicy(_ valueParam: String) {
        proto.policy = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setSignature(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.signature = valueParam
    }

    public mutating func setSignature(_ valueParam: String) {
        proto.signature = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoAvatarUploadAttributes {
        return GroupsProtoAvatarUploadAttributes(proto)
    }

    public func buildInfallibly() -> GroupsProtoAvatarUploadAttributes {
        return GroupsProtoAvatarUploadAttributes(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoAvatarUploadAttributes(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoAvatarUploadAttributes {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoAvatarUploadAttributesBuilder {
    public func buildIgnoringErrors() -> GroupsProtoAvatarUploadAttributes? {
        return self.buildInfallibly()
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
            case 1: self = .default
            case 2: self = .administrator
            default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
            case .unknown: return 0
            case .default: return 1
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

public struct GroupsProtoMember: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_Member) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_Member(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_Member) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoMember {
    public static func builder() -> GroupsProtoMemberBuilder {
        return GroupsProtoMemberBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoMemberBuilder {
        var builder = GroupsProtoMemberBuilder()
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
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoMemberBuilder {

    private var proto = GroupsProtos_Member()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.userID = valueParam
    }

    public mutating func setUserID(_ valueParam: Data) {
        proto.userID = valueParam
    }

    public mutating func setRole(_ valueParam: GroupsProtoMemberRole) {
        proto.role = GroupsProtoMemberRoleUnwrap(valueParam)
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setProfileKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.profileKey = valueParam
    }

    public mutating func setProfileKey(_ valueParam: Data) {
        proto.profileKey = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setPresentation(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.presentation = valueParam
    }

    public mutating func setPresentation(_ valueParam: Data) {
        proto.presentation = valueParam
    }

    public mutating func setJoinedAtRevision(_ valueParam: UInt32) {
        proto.joinedAtRevision = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoMember {
        return GroupsProtoMember(proto)
    }

    public func buildInfallibly() -> GroupsProtoMember {
        return GroupsProtoMember(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoMember(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoMember {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoMemberBuilder {
    public func buildIgnoringErrors() -> GroupsProtoMember? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoPendingMember

public struct GroupsProtoPendingMember: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_PendingMember,
                 member: GroupsProtoMember?) {
        self.proto = proto
        self.member = member
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_PendingMember(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_PendingMember) {
        var member: GroupsProtoMember?
        if proto.hasMember {
            member = GroupsProtoMember(proto.member)
        }

        self.init(proto: proto,
                  member: member)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoPendingMember {
    public static func builder() -> GroupsProtoPendingMemberBuilder {
        return GroupsProtoPendingMemberBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoPendingMemberBuilder {
        var builder = GroupsProtoPendingMemberBuilder()
        if let _value = member {
            builder.setMember(_value)
        }
        if let _value = addedByUserID {
            builder.setAddedByUserID(_value)
        }
        if hasTimestamp {
            builder.setTimestamp(timestamp)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoPendingMemberBuilder {

    private var proto = GroupsProtos_PendingMember()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setMember(_ valueParam: GroupsProtoMember?) {
        guard let valueParam = valueParam else { return }
        proto.member = valueParam.proto
    }

    public mutating func setMember(_ valueParam: GroupsProtoMember) {
        proto.member = valueParam.proto
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setAddedByUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.addedByUserID = valueParam
    }

    public mutating func setAddedByUserID(_ valueParam: Data) {
        proto.addedByUserID = valueParam
    }

    public mutating func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoPendingMember {
        return GroupsProtoPendingMember(proto)
    }

    public func buildInfallibly() -> GroupsProtoPendingMember {
        return GroupsProtoPendingMember(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoPendingMember(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoPendingMember {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoPendingMemberBuilder {
    public func buildIgnoringErrors() -> GroupsProtoPendingMember? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoRequestingMember

public struct GroupsProtoRequestingMember: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_RequestingMember

    public var userID: Data? {
        guard hasUserID else {
            return nil
        }
        return proto.userID
    }
    public var hasUserID: Bool {
        return !proto.userID.isEmpty
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

    public var timestamp: UInt64 {
        return proto.timestamp
    }
    public var hasTimestamp: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_RequestingMember) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_RequestingMember(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_RequestingMember) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoRequestingMember {
    public static func builder() -> GroupsProtoRequestingMemberBuilder {
        return GroupsProtoRequestingMemberBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoRequestingMemberBuilder {
        var builder = GroupsProtoRequestingMemberBuilder()
        if let _value = userID {
            builder.setUserID(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = presentation {
            builder.setPresentation(_value)
        }
        if hasTimestamp {
            builder.setTimestamp(timestamp)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoRequestingMemberBuilder {

    private var proto = GroupsProtos_RequestingMember()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.userID = valueParam
    }

    public mutating func setUserID(_ valueParam: Data) {
        proto.userID = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setProfileKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.profileKey = valueParam
    }

    public mutating func setProfileKey(_ valueParam: Data) {
        proto.profileKey = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setPresentation(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.presentation = valueParam
    }

    public mutating func setPresentation(_ valueParam: Data) {
        proto.presentation = valueParam
    }

    public mutating func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoRequestingMember {
        return GroupsProtoRequestingMember(proto)
    }

    public func buildInfallibly() -> GroupsProtoRequestingMember {
        return GroupsProtoRequestingMember(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoRequestingMember(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoRequestingMember {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoRequestingMemberBuilder {
    public func buildIgnoringErrors() -> GroupsProtoRequestingMember? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoBannedMember

public struct GroupsProtoBannedMember: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_BannedMember

    public var userID: Data? {
        guard hasUserID else {
            return nil
        }
        return proto.userID
    }
    public var hasUserID: Bool {
        return !proto.userID.isEmpty
    }

    public var bannedAtTimestamp: UInt64 {
        return proto.bannedAtTimestamp
    }
    public var hasBannedAtTimestamp: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_BannedMember) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_BannedMember(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_BannedMember) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoBannedMember {
    public static func builder() -> GroupsProtoBannedMemberBuilder {
        return GroupsProtoBannedMemberBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoBannedMemberBuilder {
        var builder = GroupsProtoBannedMemberBuilder()
        if let _value = userID {
            builder.setUserID(_value)
        }
        if hasBannedAtTimestamp {
            builder.setBannedAtTimestamp(bannedAtTimestamp)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoBannedMemberBuilder {

    private var proto = GroupsProtos_BannedMember()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.userID = valueParam
    }

    public mutating func setUserID(_ valueParam: Data) {
        proto.userID = valueParam
    }

    public mutating func setBannedAtTimestamp(_ valueParam: UInt64) {
        proto.bannedAtTimestamp = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoBannedMember {
        return GroupsProtoBannedMember(proto)
    }

    public func buildInfallibly() -> GroupsProtoBannedMember {
        return GroupsProtoBannedMember(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoBannedMember(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoBannedMember {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoBannedMemberBuilder {
    public func buildIgnoringErrors() -> GroupsProtoBannedMember? {
        return self.buildInfallibly()
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
    case unsatisfiable // 4
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
            case 4: self = .unsatisfiable
            default: self = .UNRECOGNIZED(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
            case .unknown: return 0
            case .any: return 1
            case .member: return 2
            case .administrator: return 3
            case .unsatisfiable: return 4
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
    case .unsatisfiable: return .unsatisfiable
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

private func GroupsProtoAccessControlAccessRequiredUnwrap(_ value: GroupsProtoAccessControlAccessRequired) -> GroupsProtos_AccessControl.AccessRequired {
    switch value {
    case .unknown: return .unknown
    case .any: return .any
    case .member: return .member
    case .administrator: return .administrator
    case .unsatisfiable: return .unsatisfiable
    case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
    }
}

// MARK: - GroupsProtoAccessControl

public struct GroupsProtoAccessControl: Codable, CustomDebugStringConvertible {

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

    public var addFromInviteLink: GroupsProtoAccessControlAccessRequired? {
        guard hasAddFromInviteLink else {
            return nil
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.addFromInviteLink)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedAddFromInviteLink: GroupsProtoAccessControlAccessRequired {
        if !hasAddFromInviteLink {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: AccessControl.addFromInviteLink.")
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.addFromInviteLink)
    }
    public var hasAddFromInviteLink: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_AccessControl) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_AccessControl(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_AccessControl) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoAccessControl {
    public static func builder() -> GroupsProtoAccessControlBuilder {
        return GroupsProtoAccessControlBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoAccessControlBuilder {
        var builder = GroupsProtoAccessControlBuilder()
        if let _value = attributes {
            builder.setAttributes(_value)
        }
        if let _value = members {
            builder.setMembers(_value)
        }
        if let _value = addFromInviteLink {
            builder.setAddFromInviteLink(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoAccessControlBuilder {

    private var proto = GroupsProtos_AccessControl()

    fileprivate init() {}

    public mutating func setAttributes(_ valueParam: GroupsProtoAccessControlAccessRequired) {
        proto.attributes = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
    }

    public mutating func setMembers(_ valueParam: GroupsProtoAccessControlAccessRequired) {
        proto.members = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
    }

    public mutating func setAddFromInviteLink(_ valueParam: GroupsProtoAccessControlAccessRequired) {
        proto.addFromInviteLink = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoAccessControl {
        return GroupsProtoAccessControl(proto)
    }

    public func buildInfallibly() -> GroupsProtoAccessControl {
        return GroupsProtoAccessControl(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoAccessControl(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoAccessControl {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoAccessControlBuilder {
    public func buildIgnoringErrors() -> GroupsProtoAccessControl? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroup

public struct GroupsProtoGroup: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_Group

    public let accessControl: GroupsProtoAccessControl?

    public let members: [GroupsProtoMember]

    public let pendingMembers: [GroupsProtoPendingMember]

    public let requestingMembers: [GroupsProtoRequestingMember]

    public let bannedMembers: [GroupsProtoBannedMember]

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

    public var inviteLinkPassword: Data? {
        guard hasInviteLinkPassword else {
            return nil
        }
        return proto.inviteLinkPassword
    }
    public var hasInviteLinkPassword: Bool {
        return !proto.inviteLinkPassword.isEmpty
    }

    public var descriptionBytes: Data? {
        guard hasDescriptionBytes else {
            return nil
        }
        return proto.descriptionBytes
    }
    public var hasDescriptionBytes: Bool {
        return !proto.descriptionBytes.isEmpty
    }

    public var announcementsOnly: Bool {
        return proto.announcementsOnly
    }
    public var hasAnnouncementsOnly: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_Group,
                 accessControl: GroupsProtoAccessControl?,
                 members: [GroupsProtoMember],
                 pendingMembers: [GroupsProtoPendingMember],
                 requestingMembers: [GroupsProtoRequestingMember],
                 bannedMembers: [GroupsProtoBannedMember]) {
        self.proto = proto
        self.accessControl = accessControl
        self.members = members
        self.pendingMembers = pendingMembers
        self.requestingMembers = requestingMembers
        self.bannedMembers = bannedMembers
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_Group(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_Group) {
        var accessControl: GroupsProtoAccessControl?
        if proto.hasAccessControl {
            accessControl = GroupsProtoAccessControl(proto.accessControl)
        }

        var members: [GroupsProtoMember] = []
        members = proto.members.map { GroupsProtoMember($0) }

        var pendingMembers: [GroupsProtoPendingMember] = []
        pendingMembers = proto.pendingMembers.map { GroupsProtoPendingMember($0) }

        var requestingMembers: [GroupsProtoRequestingMember] = []
        requestingMembers = proto.requestingMembers.map { GroupsProtoRequestingMember($0) }

        var bannedMembers: [GroupsProtoBannedMember] = []
        bannedMembers = proto.bannedMembers.map { GroupsProtoBannedMember($0) }

        self.init(proto: proto,
                  accessControl: accessControl,
                  members: members,
                  pendingMembers: pendingMembers,
                  requestingMembers: requestingMembers,
                  bannedMembers: bannedMembers)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroup {
    public static func builder() -> GroupsProtoGroupBuilder {
        return GroupsProtoGroupBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupBuilder {
        var builder = GroupsProtoGroupBuilder()
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
        builder.setRequestingMembers(requestingMembers)
        if let _value = inviteLinkPassword {
            builder.setInviteLinkPassword(_value)
        }
        if let _value = descriptionBytes {
            builder.setDescriptionBytes(_value)
        }
        if hasAnnouncementsOnly {
            builder.setAnnouncementsOnly(announcementsOnly)
        }
        builder.setBannedMembers(bannedMembers)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupBuilder {

    private var proto = GroupsProtos_Group()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setPublicKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.publicKey = valueParam
    }

    public mutating func setPublicKey(_ valueParam: Data) {
        proto.publicKey = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setTitle(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.title = valueParam
    }

    public mutating func setTitle(_ valueParam: Data) {
        proto.title = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setAvatar(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.avatar = valueParam
    }

    public mutating func setAvatar(_ valueParam: String) {
        proto.avatar = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setDisappearingMessagesTimer(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.disappearingMessagesTimer = valueParam
    }

    public mutating func setDisappearingMessagesTimer(_ valueParam: Data) {
        proto.disappearingMessagesTimer = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setAccessControl(_ valueParam: GroupsProtoAccessControl?) {
        guard let valueParam = valueParam else { return }
        proto.accessControl = valueParam.proto
    }

    public mutating func setAccessControl(_ valueParam: GroupsProtoAccessControl) {
        proto.accessControl = valueParam.proto
    }

    public mutating func setRevision(_ valueParam: UInt32) {
        proto.revision = valueParam
    }

    public mutating func addMembers(_ valueParam: GroupsProtoMember) {
        proto.members.append(valueParam.proto)
    }

    public mutating func setMembers(_ wrappedItems: [GroupsProtoMember]) {
        proto.members = wrappedItems.map { $0.proto }
    }

    public mutating func addPendingMembers(_ valueParam: GroupsProtoPendingMember) {
        proto.pendingMembers.append(valueParam.proto)
    }

    public mutating func setPendingMembers(_ wrappedItems: [GroupsProtoPendingMember]) {
        proto.pendingMembers = wrappedItems.map { $0.proto }
    }

    public mutating func addRequestingMembers(_ valueParam: GroupsProtoRequestingMember) {
        proto.requestingMembers.append(valueParam.proto)
    }

    public mutating func setRequestingMembers(_ wrappedItems: [GroupsProtoRequestingMember]) {
        proto.requestingMembers = wrappedItems.map { $0.proto }
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setInviteLinkPassword(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.inviteLinkPassword = valueParam
    }

    public mutating func setInviteLinkPassword(_ valueParam: Data) {
        proto.inviteLinkPassword = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setDescriptionBytes(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.descriptionBytes = valueParam
    }

    public mutating func setDescriptionBytes(_ valueParam: Data) {
        proto.descriptionBytes = valueParam
    }

    public mutating func setAnnouncementsOnly(_ valueParam: Bool) {
        proto.announcementsOnly = valueParam
    }

    public mutating func addBannedMembers(_ valueParam: GroupsProtoBannedMember) {
        proto.bannedMembers.append(valueParam.proto)
    }

    public mutating func setBannedMembers(_ wrappedItems: [GroupsProtoBannedMember]) {
        proto.bannedMembers = wrappedItems.map { $0.proto }
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroup {
        return GroupsProtoGroup(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroup {
        return GroupsProtoGroup(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroup(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroup {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroup? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsAddMemberAction

public struct GroupsProtoGroupChangeActionsAddMemberAction: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChange.Actions.AddMemberAction

    public let added: GroupsProtoMember?

    public var joinFromInviteLink: Bool {
        return proto.joinFromInviteLink
    }
    public var hasJoinFromInviteLink: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.AddMemberAction,
                 added: GroupsProtoMember?) {
        self.proto = proto
        self.added = added
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.AddMemberAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.AddMemberAction) {
        var added: GroupsProtoMember?
        if proto.hasAdded {
            added = GroupsProtoMember(proto.added)
        }

        self.init(proto: proto,
                  added: added)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsAddMemberAction {
    public static func builder() -> GroupsProtoGroupChangeActionsAddMemberActionBuilder {
        return GroupsProtoGroupChangeActionsAddMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsAddMemberActionBuilder {
        var builder = GroupsProtoGroupChangeActionsAddMemberActionBuilder()
        if let _value = added {
            builder.setAdded(_value)
        }
        if hasJoinFromInviteLink {
            builder.setJoinFromInviteLink(joinFromInviteLink)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsAddMemberActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.AddMemberAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setAdded(_ valueParam: GroupsProtoMember?) {
        guard let valueParam = valueParam else { return }
        proto.added = valueParam.proto
    }

    public mutating func setAdded(_ valueParam: GroupsProtoMember) {
        proto.added = valueParam.proto
    }

    public mutating func setJoinFromInviteLink(_ valueParam: Bool) {
        proto.joinFromInviteLink = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsAddMemberAction {
        return GroupsProtoGroupChangeActionsAddMemberAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsAddMemberAction {
        return GroupsProtoGroupChangeActionsAddMemberAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsAddMemberAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsAddMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsAddMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsAddMemberAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsDeleteMemberAction

public struct GroupsProtoGroupChangeActionsDeleteMemberAction: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.DeleteMemberAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.DeleteMemberAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.DeleteMemberAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsDeleteMemberAction {
    public static func builder() -> GroupsProtoGroupChangeActionsDeleteMemberActionBuilder {
        return GroupsProtoGroupChangeActionsDeleteMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsDeleteMemberActionBuilder {
        var builder = GroupsProtoGroupChangeActionsDeleteMemberActionBuilder()
        if let _value = deletedUserID {
            builder.setDeletedUserID(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsDeleteMemberActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.DeleteMemberAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setDeletedUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.deletedUserID = valueParam
    }

    public mutating func setDeletedUserID(_ valueParam: Data) {
        proto.deletedUserID = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsDeleteMemberAction {
        return GroupsProtoGroupChangeActionsDeleteMemberAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsDeleteMemberAction {
        return GroupsProtoGroupChangeActionsDeleteMemberAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsDeleteMemberAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsDeleteMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsDeleteMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsDeleteMemberAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyMemberRoleAction

public struct GroupsProtoGroupChangeActionsModifyMemberRoleAction: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsModifyMemberRoleAction {
    public static func builder() -> GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder {
        return GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder {
        var builder = GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder()
        if let _value = userID {
            builder.setUserID(_value)
        }
        if let _value = role {
            builder.setRole(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.ModifyMemberRoleAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.userID = valueParam
    }

    public mutating func setUserID(_ valueParam: Data) {
        proto.userID = valueParam
    }

    public mutating func setRole(_ valueParam: GroupsProtoMemberRole) {
        proto.role = GroupsProtoMemberRoleUnwrap(valueParam)
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsModifyMemberRoleAction {
        return GroupsProtoGroupChangeActionsModifyMemberRoleAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsModifyMemberRoleAction {
        return GroupsProtoGroupChangeActionsModifyMemberRoleAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsModifyMemberRoleAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsModifyMemberRoleAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyMemberRoleActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyMemberRoleAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction

public struct GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction: Codable, CustomDebugStringConvertible {

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

    public var userID: Data? {
        guard hasUserID else {
            return nil
        }
        return proto.userID
    }
    public var hasUserID: Bool {
        return !proto.userID.isEmpty
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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyMemberProfileKeyAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyMemberProfileKeyAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.ModifyMemberProfileKeyAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction {
    public static func builder() -> GroupsProtoGroupChangeActionsModifyMemberProfileKeyActionBuilder {
        return GroupsProtoGroupChangeActionsModifyMemberProfileKeyActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyMemberProfileKeyActionBuilder {
        var builder = GroupsProtoGroupChangeActionsModifyMemberProfileKeyActionBuilder()
        if let _value = presentation {
            builder.setPresentation(_value)
        }
        if let _value = userID {
            builder.setUserID(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsModifyMemberProfileKeyActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.ModifyMemberProfileKeyAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setPresentation(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.presentation = valueParam
    }

    public mutating func setPresentation(_ valueParam: Data) {
        proto.presentation = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.userID = valueParam
    }

    public mutating func setUserID(_ valueParam: Data) {
        proto.userID = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setProfileKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.profileKey = valueParam
    }

    public mutating func setProfileKey(_ valueParam: Data) {
        proto.profileKey = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction {
        return GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction {
        return GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyMemberProfileKeyActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsAddPendingMemberAction

public struct GroupsProtoGroupChangeActionsAddPendingMemberAction: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChange.Actions.AddPendingMemberAction

    public let added: GroupsProtoPendingMember?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.AddPendingMemberAction,
                 added: GroupsProtoPendingMember?) {
        self.proto = proto
        self.added = added
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.AddPendingMemberAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.AddPendingMemberAction) {
        var added: GroupsProtoPendingMember?
        if proto.hasAdded {
            added = GroupsProtoPendingMember(proto.added)
        }

        self.init(proto: proto,
                  added: added)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsAddPendingMemberAction {
    public static func builder() -> GroupsProtoGroupChangeActionsAddPendingMemberActionBuilder {
        return GroupsProtoGroupChangeActionsAddPendingMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsAddPendingMemberActionBuilder {
        var builder = GroupsProtoGroupChangeActionsAddPendingMemberActionBuilder()
        if let _value = added {
            builder.setAdded(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsAddPendingMemberActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.AddPendingMemberAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setAdded(_ valueParam: GroupsProtoPendingMember?) {
        guard let valueParam = valueParam else { return }
        proto.added = valueParam.proto
    }

    public mutating func setAdded(_ valueParam: GroupsProtoPendingMember) {
        proto.added = valueParam.proto
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsAddPendingMemberAction {
        return GroupsProtoGroupChangeActionsAddPendingMemberAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsAddPendingMemberAction {
        return GroupsProtoGroupChangeActionsAddPendingMemberAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsAddPendingMemberAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsAddPendingMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsAddPendingMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsAddPendingMemberAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsDeletePendingMemberAction

public struct GroupsProtoGroupChangeActionsDeletePendingMemberAction: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.DeletePendingMemberAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.DeletePendingMemberAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.DeletePendingMemberAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsDeletePendingMemberAction {
    public static func builder() -> GroupsProtoGroupChangeActionsDeletePendingMemberActionBuilder {
        return GroupsProtoGroupChangeActionsDeletePendingMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsDeletePendingMemberActionBuilder {
        var builder = GroupsProtoGroupChangeActionsDeletePendingMemberActionBuilder()
        if let _value = deletedUserID {
            builder.setDeletedUserID(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsDeletePendingMemberActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.DeletePendingMemberAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setDeletedUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.deletedUserID = valueParam
    }

    public mutating func setDeletedUserID(_ valueParam: Data) {
        proto.deletedUserID = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsDeletePendingMemberAction {
        return GroupsProtoGroupChangeActionsDeletePendingMemberAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsDeletePendingMemberAction {
        return GroupsProtoGroupChangeActionsDeletePendingMemberAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsDeletePendingMemberAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsDeletePendingMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsDeletePendingMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsDeletePendingMemberAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsPromotePendingMemberAction

public struct GroupsProtoGroupChangeActionsPromotePendingMemberAction: Codable, CustomDebugStringConvertible {

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

    public var userID: Data? {
        guard hasUserID else {
            return nil
        }
        return proto.userID
    }
    public var hasUserID: Bool {
        return !proto.userID.isEmpty
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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.PromotePendingMemberAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.PromotePendingMemberAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.PromotePendingMemberAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsPromotePendingMemberAction {
    public static func builder() -> GroupsProtoGroupChangeActionsPromotePendingMemberActionBuilder {
        return GroupsProtoGroupChangeActionsPromotePendingMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsPromotePendingMemberActionBuilder {
        var builder = GroupsProtoGroupChangeActionsPromotePendingMemberActionBuilder()
        if let _value = presentation {
            builder.setPresentation(_value)
        }
        if let _value = userID {
            builder.setUserID(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsPromotePendingMemberActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.PromotePendingMemberAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setPresentation(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.presentation = valueParam
    }

    public mutating func setPresentation(_ valueParam: Data) {
        proto.presentation = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.userID = valueParam
    }

    public mutating func setUserID(_ valueParam: Data) {
        proto.userID = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setProfileKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.profileKey = valueParam
    }

    public mutating func setProfileKey(_ valueParam: Data) {
        proto.profileKey = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsPromotePendingMemberAction {
        return GroupsProtoGroupChangeActionsPromotePendingMemberAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsPromotePendingMemberAction {
        return GroupsProtoGroupChangeActionsPromotePendingMemberAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsPromotePendingMemberAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsPromotePendingMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsPromotePendingMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsPromotePendingMemberAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction

public struct GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChange.Actions.PromoteMemberPendingPniAciProfileKeyAction

    public var presentation: Data? {
        guard hasPresentation else {
            return nil
        }
        return proto.presentation
    }
    public var hasPresentation: Bool {
        return !proto.presentation.isEmpty
    }

    public var userID: Data? {
        guard hasUserID else {
            return nil
        }
        return proto.userID
    }
    public var hasUserID: Bool {
        return !proto.userID.isEmpty
    }

    public var pni: Data? {
        guard hasPni else {
            return nil
        }
        return proto.pni
    }
    public var hasPni: Bool {
        return !proto.pni.isEmpty
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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.PromoteMemberPendingPniAciProfileKeyAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.PromoteMemberPendingPniAciProfileKeyAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.PromoteMemberPendingPniAciProfileKeyAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction {
    public static func builder() -> GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyActionBuilder {
        return GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyActionBuilder {
        var builder = GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyActionBuilder()
        if let _value = presentation {
            builder.setPresentation(_value)
        }
        if let _value = userID {
            builder.setUserID(_value)
        }
        if let _value = pni {
            builder.setPni(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.PromoteMemberPendingPniAciProfileKeyAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setPresentation(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.presentation = valueParam
    }

    public mutating func setPresentation(_ valueParam: Data) {
        proto.presentation = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.userID = valueParam
    }

    public mutating func setUserID(_ valueParam: Data) {
        proto.userID = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setPni(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.pni = valueParam
    }

    public mutating func setPni(_ valueParam: Data) {
        proto.pni = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setProfileKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.profileKey = valueParam
    }

    public mutating func setProfileKey(_ valueParam: Data) {
        proto.profileKey = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction {
        return GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction {
        return GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsAddRequestingMemberAction

public struct GroupsProtoGroupChangeActionsAddRequestingMemberAction: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChange.Actions.AddRequestingMemberAction

    public let added: GroupsProtoRequestingMember?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.AddRequestingMemberAction,
                 added: GroupsProtoRequestingMember?) {
        self.proto = proto
        self.added = added
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.AddRequestingMemberAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.AddRequestingMemberAction) {
        var added: GroupsProtoRequestingMember?
        if proto.hasAdded {
            added = GroupsProtoRequestingMember(proto.added)
        }

        self.init(proto: proto,
                  added: added)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsAddRequestingMemberAction {
    public static func builder() -> GroupsProtoGroupChangeActionsAddRequestingMemberActionBuilder {
        return GroupsProtoGroupChangeActionsAddRequestingMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsAddRequestingMemberActionBuilder {
        var builder = GroupsProtoGroupChangeActionsAddRequestingMemberActionBuilder()
        if let _value = added {
            builder.setAdded(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsAddRequestingMemberActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.AddRequestingMemberAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setAdded(_ valueParam: GroupsProtoRequestingMember?) {
        guard let valueParam = valueParam else { return }
        proto.added = valueParam.proto
    }

    public mutating func setAdded(_ valueParam: GroupsProtoRequestingMember) {
        proto.added = valueParam.proto
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsAddRequestingMemberAction {
        return GroupsProtoGroupChangeActionsAddRequestingMemberAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsAddRequestingMemberAction {
        return GroupsProtoGroupChangeActionsAddRequestingMemberAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsAddRequestingMemberAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsAddRequestingMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsAddRequestingMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsAddRequestingMemberAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsDeleteRequestingMemberAction

public struct GroupsProtoGroupChangeActionsDeleteRequestingMemberAction: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChange.Actions.DeleteRequestingMemberAction

    public var deletedUserID: Data? {
        guard hasDeletedUserID else {
            return nil
        }
        return proto.deletedUserID
    }
    public var hasDeletedUserID: Bool {
        return !proto.deletedUserID.isEmpty
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.DeleteRequestingMemberAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.DeleteRequestingMemberAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.DeleteRequestingMemberAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsDeleteRequestingMemberAction {
    public static func builder() -> GroupsProtoGroupChangeActionsDeleteRequestingMemberActionBuilder {
        return GroupsProtoGroupChangeActionsDeleteRequestingMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsDeleteRequestingMemberActionBuilder {
        var builder = GroupsProtoGroupChangeActionsDeleteRequestingMemberActionBuilder()
        if let _value = deletedUserID {
            builder.setDeletedUserID(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsDeleteRequestingMemberActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.DeleteRequestingMemberAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setDeletedUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.deletedUserID = valueParam
    }

    public mutating func setDeletedUserID(_ valueParam: Data) {
        proto.deletedUserID = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsDeleteRequestingMemberAction {
        return GroupsProtoGroupChangeActionsDeleteRequestingMemberAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsDeleteRequestingMemberAction {
        return GroupsProtoGroupChangeActionsDeleteRequestingMemberAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsDeleteRequestingMemberAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsDeleteRequestingMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsDeleteRequestingMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsDeleteRequestingMemberAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsPromoteRequestingMemberAction

public struct GroupsProtoGroupChangeActionsPromoteRequestingMemberAction: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChange.Actions.PromoteRequestingMemberAction

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
            owsFailDebug("Unsafe unwrap of missing optional: PromoteRequestingMemberAction.role.")
        }
        return GroupsProtoMemberRoleWrap(proto.role)
    }
    public var hasRole: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.PromoteRequestingMemberAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.PromoteRequestingMemberAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.PromoteRequestingMemberAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsPromoteRequestingMemberAction {
    public static func builder() -> GroupsProtoGroupChangeActionsPromoteRequestingMemberActionBuilder {
        return GroupsProtoGroupChangeActionsPromoteRequestingMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsPromoteRequestingMemberActionBuilder {
        var builder = GroupsProtoGroupChangeActionsPromoteRequestingMemberActionBuilder()
        if let _value = userID {
            builder.setUserID(_value)
        }
        if let _value = role {
            builder.setRole(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsPromoteRequestingMemberActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.PromoteRequestingMemberAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.userID = valueParam
    }

    public mutating func setUserID(_ valueParam: Data) {
        proto.userID = valueParam
    }

    public mutating func setRole(_ valueParam: GroupsProtoMemberRole) {
        proto.role = GroupsProtoMemberRoleUnwrap(valueParam)
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsPromoteRequestingMemberAction {
        return GroupsProtoGroupChangeActionsPromoteRequestingMemberAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsPromoteRequestingMemberAction {
        return GroupsProtoGroupChangeActionsPromoteRequestingMemberAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsPromoteRequestingMemberAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsPromoteRequestingMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsPromoteRequestingMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsPromoteRequestingMemberAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsAddBannedMemberAction

public struct GroupsProtoGroupChangeActionsAddBannedMemberAction: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChange.Actions.AddBannedMemberAction

    public let added: GroupsProtoBannedMember?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.AddBannedMemberAction,
                 added: GroupsProtoBannedMember?) {
        self.proto = proto
        self.added = added
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.AddBannedMemberAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.AddBannedMemberAction) {
        var added: GroupsProtoBannedMember?
        if proto.hasAdded {
            added = GroupsProtoBannedMember(proto.added)
        }

        self.init(proto: proto,
                  added: added)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsAddBannedMemberAction {
    public static func builder() -> GroupsProtoGroupChangeActionsAddBannedMemberActionBuilder {
        return GroupsProtoGroupChangeActionsAddBannedMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsAddBannedMemberActionBuilder {
        var builder = GroupsProtoGroupChangeActionsAddBannedMemberActionBuilder()
        if let _value = added {
            builder.setAdded(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsAddBannedMemberActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.AddBannedMemberAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setAdded(_ valueParam: GroupsProtoBannedMember?) {
        guard let valueParam = valueParam else { return }
        proto.added = valueParam.proto
    }

    public mutating func setAdded(_ valueParam: GroupsProtoBannedMember) {
        proto.added = valueParam.proto
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsAddBannedMemberAction {
        return GroupsProtoGroupChangeActionsAddBannedMemberAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsAddBannedMemberAction {
        return GroupsProtoGroupChangeActionsAddBannedMemberAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsAddBannedMemberAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsAddBannedMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsAddBannedMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsAddBannedMemberAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsDeleteBannedMemberAction

public struct GroupsProtoGroupChangeActionsDeleteBannedMemberAction: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChange.Actions.DeleteBannedMemberAction

    public var deletedUserID: Data? {
        guard hasDeletedUserID else {
            return nil
        }
        return proto.deletedUserID
    }
    public var hasDeletedUserID: Bool {
        return !proto.deletedUserID.isEmpty
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.DeleteBannedMemberAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.DeleteBannedMemberAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.DeleteBannedMemberAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsDeleteBannedMemberAction {
    public static func builder() -> GroupsProtoGroupChangeActionsDeleteBannedMemberActionBuilder {
        return GroupsProtoGroupChangeActionsDeleteBannedMemberActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsDeleteBannedMemberActionBuilder {
        var builder = GroupsProtoGroupChangeActionsDeleteBannedMemberActionBuilder()
        if let _value = deletedUserID {
            builder.setDeletedUserID(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsDeleteBannedMemberActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.DeleteBannedMemberAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setDeletedUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.deletedUserID = valueParam
    }

    public mutating func setDeletedUserID(_ valueParam: Data) {
        proto.deletedUserID = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsDeleteBannedMemberAction {
        return GroupsProtoGroupChangeActionsDeleteBannedMemberAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsDeleteBannedMemberAction {
        return GroupsProtoGroupChangeActionsDeleteBannedMemberAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsDeleteBannedMemberAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsDeleteBannedMemberAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsDeleteBannedMemberActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsDeleteBannedMemberAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyTitleAction

public struct GroupsProtoGroupChangeActionsModifyTitleAction: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyTitleAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyTitleAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.ModifyTitleAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsModifyTitleAction {
    public static func builder() -> GroupsProtoGroupChangeActionsModifyTitleActionBuilder {
        return GroupsProtoGroupChangeActionsModifyTitleActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyTitleActionBuilder {
        var builder = GroupsProtoGroupChangeActionsModifyTitleActionBuilder()
        if let _value = title {
            builder.setTitle(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsModifyTitleActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.ModifyTitleAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setTitle(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.title = valueParam
    }

    public mutating func setTitle(_ valueParam: Data) {
        proto.title = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsModifyTitleAction {
        return GroupsProtoGroupChangeActionsModifyTitleAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsModifyTitleAction {
        return GroupsProtoGroupChangeActionsModifyTitleAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsModifyTitleAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsModifyTitleAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyTitleActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyTitleAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyAvatarAction

public struct GroupsProtoGroupChangeActionsModifyAvatarAction: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyAvatarAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsModifyAvatarAction {
    public static func builder() -> GroupsProtoGroupChangeActionsModifyAvatarActionBuilder {
        return GroupsProtoGroupChangeActionsModifyAvatarActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyAvatarActionBuilder {
        var builder = GroupsProtoGroupChangeActionsModifyAvatarActionBuilder()
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsModifyAvatarActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.ModifyAvatarAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setAvatar(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.avatar = valueParam
    }

    public mutating func setAvatar(_ valueParam: String) {
        proto.avatar = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsModifyAvatarAction {
        return GroupsProtoGroupChangeActionsModifyAvatarAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsModifyAvatarAction {
        return GroupsProtoGroupChangeActionsModifyAvatarAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsModifyAvatarAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsModifyAvatarAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyAvatarActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyAvatarAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction

public struct GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyDisappearingMessagesTimerAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyDisappearingMessagesTimerAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.ModifyDisappearingMessagesTimerAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction {
    public static func builder() -> GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerActionBuilder {
        return GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerActionBuilder {
        var builder = GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerActionBuilder()
        if let _value = timer {
            builder.setTimer(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.ModifyDisappearingMessagesTimerAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setTimer(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.timer = valueParam
    }

    public mutating func setTimer(_ valueParam: Data) {
        proto.timer = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction {
        return GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction {
        return GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction

public struct GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyAttributesAccessControlAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyAttributesAccessControlAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.ModifyAttributesAccessControlAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction {
    public static func builder() -> GroupsProtoGroupChangeActionsModifyAttributesAccessControlActionBuilder {
        return GroupsProtoGroupChangeActionsModifyAttributesAccessControlActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyAttributesAccessControlActionBuilder {
        var builder = GroupsProtoGroupChangeActionsModifyAttributesAccessControlActionBuilder()
        if let _value = attributesAccess {
            builder.setAttributesAccess(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsModifyAttributesAccessControlActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.ModifyAttributesAccessControlAction()

    fileprivate init() {}

    public mutating func setAttributesAccess(_ valueParam: GroupsProtoAccessControlAccessRequired) {
        proto.attributesAccess = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction {
        return GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction {
        return GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyAttributesAccessControlActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction

public struct GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction {
    public static func builder() -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder {
        return GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder {
        var builder = GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder()
        if let _value = avatarAccess {
            builder.setAvatarAccess(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.ModifyAvatarAccessControlAction()

    fileprivate init() {}

    public mutating func setAvatarAccess(_ valueParam: GroupsProtoAccessControlAccessRequired) {
        proto.avatarAccess = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction {
        return GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction {
        return GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyAvatarAccessControlActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyAvatarAccessControlAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyMembersAccessControlAction

public struct GroupsProtoGroupChangeActionsModifyMembersAccessControlAction: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsModifyMembersAccessControlAction {
    public static func builder() -> GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder {
        return GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder {
        var builder = GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder()
        if let _value = membersAccess {
            builder.setMembersAccess(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.ModifyMembersAccessControlAction()

    fileprivate init() {}

    public mutating func setMembersAccess(_ valueParam: GroupsProtoAccessControlAccessRequired) {
        proto.membersAccess = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsModifyMembersAccessControlAction {
        return GroupsProtoGroupChangeActionsModifyMembersAccessControlAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsModifyMembersAccessControlAction {
        return GroupsProtoGroupChangeActionsModifyMembersAccessControlAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsModifyMembersAccessControlAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsModifyMembersAccessControlAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyMembersAccessControlActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyMembersAccessControlAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction

public struct GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyAddFromInviteLinkAccessControlAction

    public var addFromInviteLinkAccess: GroupsProtoAccessControlAccessRequired? {
        guard hasAddFromInviteLinkAccess else {
            return nil
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.addFromInviteLinkAccess)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedAddFromInviteLinkAccess: GroupsProtoAccessControlAccessRequired {
        if !hasAddFromInviteLinkAccess {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: ModifyAddFromInviteLinkAccessControlAction.addFromInviteLinkAccess.")
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.addFromInviteLinkAccess)
    }
    public var hasAddFromInviteLinkAccess: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyAddFromInviteLinkAccessControlAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyAddFromInviteLinkAccessControlAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.ModifyAddFromInviteLinkAccessControlAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction {
    public static func builder() -> GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlActionBuilder {
        return GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlActionBuilder {
        var builder = GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlActionBuilder()
        if let _value = addFromInviteLinkAccess {
            builder.setAddFromInviteLinkAccess(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.ModifyAddFromInviteLinkAccessControlAction()

    fileprivate init() {}

    public mutating func setAddFromInviteLinkAccess(_ valueParam: GroupsProtoAccessControlAccessRequired) {
        proto.addFromInviteLinkAccess = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction {
        return GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction {
        return GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction

public struct GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyInviteLinkPasswordAction

    public var inviteLinkPassword: Data? {
        guard hasInviteLinkPassword else {
            return nil
        }
        return proto.inviteLinkPassword
    }
    public var hasInviteLinkPassword: Bool {
        return !proto.inviteLinkPassword.isEmpty
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyInviteLinkPasswordAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyInviteLinkPasswordAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.ModifyInviteLinkPasswordAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction {
    public static func builder() -> GroupsProtoGroupChangeActionsModifyInviteLinkPasswordActionBuilder {
        return GroupsProtoGroupChangeActionsModifyInviteLinkPasswordActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyInviteLinkPasswordActionBuilder {
        var builder = GroupsProtoGroupChangeActionsModifyInviteLinkPasswordActionBuilder()
        if let _value = inviteLinkPassword {
            builder.setInviteLinkPassword(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsModifyInviteLinkPasswordActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.ModifyInviteLinkPasswordAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setInviteLinkPassword(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.inviteLinkPassword = valueParam
    }

    public mutating func setInviteLinkPassword(_ valueParam: Data) {
        proto.inviteLinkPassword = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction {
        return GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction {
        return GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyInviteLinkPasswordActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyDescriptionAction

public struct GroupsProtoGroupChangeActionsModifyDescriptionAction: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyDescriptionAction

    public var descriptionBytes: Data? {
        guard hasDescriptionBytes else {
            return nil
        }
        return proto.descriptionBytes
    }
    public var hasDescriptionBytes: Bool {
        return !proto.descriptionBytes.isEmpty
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyDescriptionAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyDescriptionAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.ModifyDescriptionAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsModifyDescriptionAction {
    public static func builder() -> GroupsProtoGroupChangeActionsModifyDescriptionActionBuilder {
        return GroupsProtoGroupChangeActionsModifyDescriptionActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyDescriptionActionBuilder {
        var builder = GroupsProtoGroupChangeActionsModifyDescriptionActionBuilder()
        if let _value = descriptionBytes {
            builder.setDescriptionBytes(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsModifyDescriptionActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.ModifyDescriptionAction()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setDescriptionBytes(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.descriptionBytes = valueParam
    }

    public mutating func setDescriptionBytes(_ valueParam: Data) {
        proto.descriptionBytes = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsModifyDescriptionAction {
        return GroupsProtoGroupChangeActionsModifyDescriptionAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsModifyDescriptionAction {
        return GroupsProtoGroupChangeActionsModifyDescriptionAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsModifyDescriptionAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsModifyDescriptionAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyDescriptionActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyDescriptionAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction

public struct GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChange.Actions.ModifyAnnouncementsOnlyAction

    public var announcementsOnly: Bool {
        return proto.announcementsOnly
    }
    public var hasAnnouncementsOnly: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange.Actions.ModifyAnnouncementsOnlyAction) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions.ModifyAnnouncementsOnlyAction(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions.ModifyAnnouncementsOnlyAction) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction {
    public static func builder() -> GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyActionBuilder {
        return GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyActionBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyActionBuilder {
        var builder = GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyActionBuilder()
        if hasAnnouncementsOnly {
            builder.setAnnouncementsOnly(announcementsOnly)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyActionBuilder {

    private var proto = GroupsProtos_GroupChange.Actions.ModifyAnnouncementsOnlyAction()

    fileprivate init() {}

    public mutating func setAnnouncementsOnly(_ valueParam: Bool) {
        proto.announcementsOnly = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction {
        return GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction {
        return GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyActionBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangeActions

public struct GroupsProtoGroupChangeActions: Codable, CustomDebugStringConvertible {

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

    public let modifyAddFromInviteLinkAccess: GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction?

    public let addRequestingMembers: [GroupsProtoGroupChangeActionsAddRequestingMemberAction]

    public let deleteRequestingMembers: [GroupsProtoGroupChangeActionsDeleteRequestingMemberAction]

    public let promoteRequestingMembers: [GroupsProtoGroupChangeActionsPromoteRequestingMemberAction]

    public let modifyInviteLinkPassword: GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction?

    public let modifyDescription: GroupsProtoGroupChangeActionsModifyDescriptionAction?

    public let modifyAnnouncementsOnly: GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction?

    public let addBannedMembers: [GroupsProtoGroupChangeActionsAddBannedMemberAction]

    public let deleteBannedMembers: [GroupsProtoGroupChangeActionsDeleteBannedMemberAction]

    public let promotePniPendingMembers: [GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction]

    public var sourceUserID: Data? {
        guard hasSourceUserID else {
            return nil
        }
        return proto.sourceUserID
    }
    public var hasSourceUserID: Bool {
        return !proto.sourceUserID.isEmpty
    }

    public var revision: UInt32 {
        return proto.revision
    }
    public var hasRevision: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
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
                 modifyMemberAccess: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction?,
                 modifyAddFromInviteLinkAccess: GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction?,
                 addRequestingMembers: [GroupsProtoGroupChangeActionsAddRequestingMemberAction],
                 deleteRequestingMembers: [GroupsProtoGroupChangeActionsDeleteRequestingMemberAction],
                 promoteRequestingMembers: [GroupsProtoGroupChangeActionsPromoteRequestingMemberAction],
                 modifyInviteLinkPassword: GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction?,
                 modifyDescription: GroupsProtoGroupChangeActionsModifyDescriptionAction?,
                 modifyAnnouncementsOnly: GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction?,
                 addBannedMembers: [GroupsProtoGroupChangeActionsAddBannedMemberAction],
                 deleteBannedMembers: [GroupsProtoGroupChangeActionsDeleteBannedMemberAction],
                 promotePniPendingMembers: [GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction]) {
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
        self.modifyAddFromInviteLinkAccess = modifyAddFromInviteLinkAccess
        self.addRequestingMembers = addRequestingMembers
        self.deleteRequestingMembers = deleteRequestingMembers
        self.promoteRequestingMembers = promoteRequestingMembers
        self.modifyInviteLinkPassword = modifyInviteLinkPassword
        self.modifyDescription = modifyDescription
        self.modifyAnnouncementsOnly = modifyAnnouncementsOnly
        self.addBannedMembers = addBannedMembers
        self.deleteBannedMembers = deleteBannedMembers
        self.promotePniPendingMembers = promotePniPendingMembers
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange.Actions(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange.Actions) {
        var addMembers: [GroupsProtoGroupChangeActionsAddMemberAction] = []
        addMembers = proto.addMembers.map { GroupsProtoGroupChangeActionsAddMemberAction($0) }

        var deleteMembers: [GroupsProtoGroupChangeActionsDeleteMemberAction] = []
        deleteMembers = proto.deleteMembers.map { GroupsProtoGroupChangeActionsDeleteMemberAction($0) }

        var modifyMemberRoles: [GroupsProtoGroupChangeActionsModifyMemberRoleAction] = []
        modifyMemberRoles = proto.modifyMemberRoles.map { GroupsProtoGroupChangeActionsModifyMemberRoleAction($0) }

        var modifyMemberProfileKeys: [GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction] = []
        modifyMemberProfileKeys = proto.modifyMemberProfileKeys.map { GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction($0) }

        var addPendingMembers: [GroupsProtoGroupChangeActionsAddPendingMemberAction] = []
        addPendingMembers = proto.addPendingMembers.map { GroupsProtoGroupChangeActionsAddPendingMemberAction($0) }

        var deletePendingMembers: [GroupsProtoGroupChangeActionsDeletePendingMemberAction] = []
        deletePendingMembers = proto.deletePendingMembers.map { GroupsProtoGroupChangeActionsDeletePendingMemberAction($0) }

        var promotePendingMembers: [GroupsProtoGroupChangeActionsPromotePendingMemberAction] = []
        promotePendingMembers = proto.promotePendingMembers.map { GroupsProtoGroupChangeActionsPromotePendingMemberAction($0) }

        var modifyTitle: GroupsProtoGroupChangeActionsModifyTitleAction?
        if proto.hasModifyTitle {
            modifyTitle = GroupsProtoGroupChangeActionsModifyTitleAction(proto.modifyTitle)
        }

        var modifyAvatar: GroupsProtoGroupChangeActionsModifyAvatarAction?
        if proto.hasModifyAvatar {
            modifyAvatar = GroupsProtoGroupChangeActionsModifyAvatarAction(proto.modifyAvatar)
        }

        var modifyDisappearingMessagesTimer: GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction?
        if proto.hasModifyDisappearingMessagesTimer {
            modifyDisappearingMessagesTimer = GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction(proto.modifyDisappearingMessagesTimer)
        }

        var modifyAttributesAccess: GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction?
        if proto.hasModifyAttributesAccess {
            modifyAttributesAccess = GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction(proto.modifyAttributesAccess)
        }

        var modifyMemberAccess: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction?
        if proto.hasModifyMemberAccess {
            modifyMemberAccess = GroupsProtoGroupChangeActionsModifyMembersAccessControlAction(proto.modifyMemberAccess)
        }

        var modifyAddFromInviteLinkAccess: GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction?
        if proto.hasModifyAddFromInviteLinkAccess {
            modifyAddFromInviteLinkAccess = GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction(proto.modifyAddFromInviteLinkAccess)
        }

        var addRequestingMembers: [GroupsProtoGroupChangeActionsAddRequestingMemberAction] = []
        addRequestingMembers = proto.addRequestingMembers.map { GroupsProtoGroupChangeActionsAddRequestingMemberAction($0) }

        var deleteRequestingMembers: [GroupsProtoGroupChangeActionsDeleteRequestingMemberAction] = []
        deleteRequestingMembers = proto.deleteRequestingMembers.map { GroupsProtoGroupChangeActionsDeleteRequestingMemberAction($0) }

        var promoteRequestingMembers: [GroupsProtoGroupChangeActionsPromoteRequestingMemberAction] = []
        promoteRequestingMembers = proto.promoteRequestingMembers.map { GroupsProtoGroupChangeActionsPromoteRequestingMemberAction($0) }

        var modifyInviteLinkPassword: GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction?
        if proto.hasModifyInviteLinkPassword {
            modifyInviteLinkPassword = GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction(proto.modifyInviteLinkPassword)
        }

        var modifyDescription: GroupsProtoGroupChangeActionsModifyDescriptionAction?
        if proto.hasModifyDescription {
            modifyDescription = GroupsProtoGroupChangeActionsModifyDescriptionAction(proto.modifyDescription)
        }

        var modifyAnnouncementsOnly: GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction?
        if proto.hasModifyAnnouncementsOnly {
            modifyAnnouncementsOnly = GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction(proto.modifyAnnouncementsOnly)
        }

        var addBannedMembers: [GroupsProtoGroupChangeActionsAddBannedMemberAction] = []
        addBannedMembers = proto.addBannedMembers.map { GroupsProtoGroupChangeActionsAddBannedMemberAction($0) }

        var deleteBannedMembers: [GroupsProtoGroupChangeActionsDeleteBannedMemberAction] = []
        deleteBannedMembers = proto.deleteBannedMembers.map { GroupsProtoGroupChangeActionsDeleteBannedMemberAction($0) }

        var promotePniPendingMembers: [GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction] = []
        promotePniPendingMembers = proto.promotePniPendingMembers.map { GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction($0) }

        self.init(proto: proto,
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
                  modifyMemberAccess: modifyMemberAccess,
                  modifyAddFromInviteLinkAccess: modifyAddFromInviteLinkAccess,
                  addRequestingMembers: addRequestingMembers,
                  deleteRequestingMembers: deleteRequestingMembers,
                  promoteRequestingMembers: promoteRequestingMembers,
                  modifyInviteLinkPassword: modifyInviteLinkPassword,
                  modifyDescription: modifyDescription,
                  modifyAnnouncementsOnly: modifyAnnouncementsOnly,
                  addBannedMembers: addBannedMembers,
                  deleteBannedMembers: deleteBannedMembers,
                  promotePniPendingMembers: promotePniPendingMembers)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangeActions {
    public static func builder() -> GroupsProtoGroupChangeActionsBuilder {
        return GroupsProtoGroupChangeActionsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeActionsBuilder {
        var builder = GroupsProtoGroupChangeActionsBuilder()
        if let _value = sourceUserID {
            builder.setSourceUserID(_value)
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
        if let _value = modifyAddFromInviteLinkAccess {
            builder.setModifyAddFromInviteLinkAccess(_value)
        }
        builder.setAddRequestingMembers(addRequestingMembers)
        builder.setDeleteRequestingMembers(deleteRequestingMembers)
        builder.setPromoteRequestingMembers(promoteRequestingMembers)
        if let _value = modifyInviteLinkPassword {
            builder.setModifyInviteLinkPassword(_value)
        }
        if let _value = modifyDescription {
            builder.setModifyDescription(_value)
        }
        if let _value = modifyAnnouncementsOnly {
            builder.setModifyAnnouncementsOnly(_value)
        }
        builder.setAddBannedMembers(addBannedMembers)
        builder.setDeleteBannedMembers(deleteBannedMembers)
        builder.setPromotePniPendingMembers(promotePniPendingMembers)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeActionsBuilder {

    private var proto = GroupsProtos_GroupChange.Actions()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setSourceUserID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.sourceUserID = valueParam
    }

    public mutating func setSourceUserID(_ valueParam: Data) {
        proto.sourceUserID = valueParam
    }

    public mutating func setRevision(_ valueParam: UInt32) {
        proto.revision = valueParam
    }

    public mutating func addAddMembers(_ valueParam: GroupsProtoGroupChangeActionsAddMemberAction) {
        proto.addMembers.append(valueParam.proto)
    }

    public mutating func setAddMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsAddMemberAction]) {
        proto.addMembers = wrappedItems.map { $0.proto }
    }

    public mutating func addDeleteMembers(_ valueParam: GroupsProtoGroupChangeActionsDeleteMemberAction) {
        proto.deleteMembers.append(valueParam.proto)
    }

    public mutating func setDeleteMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsDeleteMemberAction]) {
        proto.deleteMembers = wrappedItems.map { $0.proto }
    }

    public mutating func addModifyMemberRoles(_ valueParam: GroupsProtoGroupChangeActionsModifyMemberRoleAction) {
        proto.modifyMemberRoles.append(valueParam.proto)
    }

    public mutating func setModifyMemberRoles(_ wrappedItems: [GroupsProtoGroupChangeActionsModifyMemberRoleAction]) {
        proto.modifyMemberRoles = wrappedItems.map { $0.proto }
    }

    public mutating func addModifyMemberProfileKeys(_ valueParam: GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction) {
        proto.modifyMemberProfileKeys.append(valueParam.proto)
    }

    public mutating func setModifyMemberProfileKeys(_ wrappedItems: [GroupsProtoGroupChangeActionsModifyMemberProfileKeyAction]) {
        proto.modifyMemberProfileKeys = wrappedItems.map { $0.proto }
    }

    public mutating func addAddPendingMembers(_ valueParam: GroupsProtoGroupChangeActionsAddPendingMemberAction) {
        proto.addPendingMembers.append(valueParam.proto)
    }

    public mutating func setAddPendingMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsAddPendingMemberAction]) {
        proto.addPendingMembers = wrappedItems.map { $0.proto }
    }

    public mutating func addDeletePendingMembers(_ valueParam: GroupsProtoGroupChangeActionsDeletePendingMemberAction) {
        proto.deletePendingMembers.append(valueParam.proto)
    }

    public mutating func setDeletePendingMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsDeletePendingMemberAction]) {
        proto.deletePendingMembers = wrappedItems.map { $0.proto }
    }

    public mutating func addPromotePendingMembers(_ valueParam: GroupsProtoGroupChangeActionsPromotePendingMemberAction) {
        proto.promotePendingMembers.append(valueParam.proto)
    }

    public mutating func setPromotePendingMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsPromotePendingMemberAction]) {
        proto.promotePendingMembers = wrappedItems.map { $0.proto }
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setModifyTitle(_ valueParam: GroupsProtoGroupChangeActionsModifyTitleAction?) {
        guard let valueParam = valueParam else { return }
        proto.modifyTitle = valueParam.proto
    }

    public mutating func setModifyTitle(_ valueParam: GroupsProtoGroupChangeActionsModifyTitleAction) {
        proto.modifyTitle = valueParam.proto
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setModifyAvatar(_ valueParam: GroupsProtoGroupChangeActionsModifyAvatarAction?) {
        guard let valueParam = valueParam else { return }
        proto.modifyAvatar = valueParam.proto
    }

    public mutating func setModifyAvatar(_ valueParam: GroupsProtoGroupChangeActionsModifyAvatarAction) {
        proto.modifyAvatar = valueParam.proto
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setModifyDisappearingMessagesTimer(_ valueParam: GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction?) {
        guard let valueParam = valueParam else { return }
        proto.modifyDisappearingMessagesTimer = valueParam.proto
    }

    public mutating func setModifyDisappearingMessagesTimer(_ valueParam: GroupsProtoGroupChangeActionsModifyDisappearingMessagesTimerAction) {
        proto.modifyDisappearingMessagesTimer = valueParam.proto
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setModifyAttributesAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction?) {
        guard let valueParam = valueParam else { return }
        proto.modifyAttributesAccess = valueParam.proto
    }

    public mutating func setModifyAttributesAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyAttributesAccessControlAction) {
        proto.modifyAttributesAccess = valueParam.proto
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setModifyMemberAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction?) {
        guard let valueParam = valueParam else { return }
        proto.modifyMemberAccess = valueParam.proto
    }

    public mutating func setModifyMemberAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyMembersAccessControlAction) {
        proto.modifyMemberAccess = valueParam.proto
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setModifyAddFromInviteLinkAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction?) {
        guard let valueParam = valueParam else { return }
        proto.modifyAddFromInviteLinkAccess = valueParam.proto
    }

    public mutating func setModifyAddFromInviteLinkAccess(_ valueParam: GroupsProtoGroupChangeActionsModifyAddFromInviteLinkAccessControlAction) {
        proto.modifyAddFromInviteLinkAccess = valueParam.proto
    }

    public mutating func addAddRequestingMembers(_ valueParam: GroupsProtoGroupChangeActionsAddRequestingMemberAction) {
        proto.addRequestingMembers.append(valueParam.proto)
    }

    public mutating func setAddRequestingMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsAddRequestingMemberAction]) {
        proto.addRequestingMembers = wrappedItems.map { $0.proto }
    }

    public mutating func addDeleteRequestingMembers(_ valueParam: GroupsProtoGroupChangeActionsDeleteRequestingMemberAction) {
        proto.deleteRequestingMembers.append(valueParam.proto)
    }

    public mutating func setDeleteRequestingMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsDeleteRequestingMemberAction]) {
        proto.deleteRequestingMembers = wrappedItems.map { $0.proto }
    }

    public mutating func addPromoteRequestingMembers(_ valueParam: GroupsProtoGroupChangeActionsPromoteRequestingMemberAction) {
        proto.promoteRequestingMembers.append(valueParam.proto)
    }

    public mutating func setPromoteRequestingMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsPromoteRequestingMemberAction]) {
        proto.promoteRequestingMembers = wrappedItems.map { $0.proto }
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setModifyInviteLinkPassword(_ valueParam: GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction?) {
        guard let valueParam = valueParam else { return }
        proto.modifyInviteLinkPassword = valueParam.proto
    }

    public mutating func setModifyInviteLinkPassword(_ valueParam: GroupsProtoGroupChangeActionsModifyInviteLinkPasswordAction) {
        proto.modifyInviteLinkPassword = valueParam.proto
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setModifyDescription(_ valueParam: GroupsProtoGroupChangeActionsModifyDescriptionAction?) {
        guard let valueParam = valueParam else { return }
        proto.modifyDescription = valueParam.proto
    }

    public mutating func setModifyDescription(_ valueParam: GroupsProtoGroupChangeActionsModifyDescriptionAction) {
        proto.modifyDescription = valueParam.proto
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setModifyAnnouncementsOnly(_ valueParam: GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction?) {
        guard let valueParam = valueParam else { return }
        proto.modifyAnnouncementsOnly = valueParam.proto
    }

    public mutating func setModifyAnnouncementsOnly(_ valueParam: GroupsProtoGroupChangeActionsModifyAnnouncementsOnlyAction) {
        proto.modifyAnnouncementsOnly = valueParam.proto
    }

    public mutating func addAddBannedMembers(_ valueParam: GroupsProtoGroupChangeActionsAddBannedMemberAction) {
        proto.addBannedMembers.append(valueParam.proto)
    }

    public mutating func setAddBannedMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsAddBannedMemberAction]) {
        proto.addBannedMembers = wrappedItems.map { $0.proto }
    }

    public mutating func addDeleteBannedMembers(_ valueParam: GroupsProtoGroupChangeActionsDeleteBannedMemberAction) {
        proto.deleteBannedMembers.append(valueParam.proto)
    }

    public mutating func setDeleteBannedMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsDeleteBannedMemberAction]) {
        proto.deleteBannedMembers = wrappedItems.map { $0.proto }
    }

    public mutating func addPromotePniPendingMembers(_ valueParam: GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction) {
        proto.promotePniPendingMembers.append(valueParam.proto)
    }

    public mutating func setPromotePniPendingMembers(_ wrappedItems: [GroupsProtoGroupChangeActionsPromoteMemberPendingPniAciProfileKeyAction]) {
        proto.promotePniPendingMembers = wrappedItems.map { $0.proto }
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangeActions {
        return GroupsProtoGroupChangeActions(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangeActions {
        return GroupsProtoGroupChangeActions(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangeActions(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangeActions {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeActionsBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangeActions? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChange

public struct GroupsProtoGroupChange: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChange) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChange(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChange) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChange {
    public static func builder() -> GroupsProtoGroupChangeBuilder {
        return GroupsProtoGroupChangeBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangeBuilder {
        var builder = GroupsProtoGroupChangeBuilder()
        if let _value = actions {
            builder.setActions(_value)
        }
        if let _value = serverSignature {
            builder.setServerSignature(_value)
        }
        if hasChangeEpoch {
            builder.setChangeEpoch(changeEpoch)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangeBuilder {

    private var proto = GroupsProtos_GroupChange()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setActions(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.actions = valueParam
    }

    public mutating func setActions(_ valueParam: Data) {
        proto.actions = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setServerSignature(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.serverSignature = valueParam
    }

    public mutating func setServerSignature(_ valueParam: Data) {
        proto.serverSignature = valueParam
    }

    public mutating func setChangeEpoch(_ valueParam: UInt32) {
        proto.changeEpoch = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChange {
        return GroupsProtoGroupChange(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChange {
        return GroupsProtoGroupChange(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChange(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChange {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangeBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChange? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChangesGroupChangeState

public struct GroupsProtoGroupChangesGroupChangeState: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChanges.GroupChangeState

    public let groupChange: GroupsProtoGroupChange?

    public let groupState: GroupsProtoGroup?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChanges.GroupChangeState,
                 groupChange: GroupsProtoGroupChange?,
                 groupState: GroupsProtoGroup?) {
        self.proto = proto
        self.groupChange = groupChange
        self.groupState = groupState
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChanges.GroupChangeState(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChanges.GroupChangeState) {
        var groupChange: GroupsProtoGroupChange?
        if proto.hasGroupChange {
            groupChange = GroupsProtoGroupChange(proto.groupChange)
        }

        var groupState: GroupsProtoGroup?
        if proto.hasGroupState {
            groupState = GroupsProtoGroup(proto.groupState)
        }

        self.init(proto: proto,
                  groupChange: groupChange,
                  groupState: groupState)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChangesGroupChangeState {
    public static func builder() -> GroupsProtoGroupChangesGroupChangeStateBuilder {
        return GroupsProtoGroupChangesGroupChangeStateBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangesGroupChangeStateBuilder {
        var builder = GroupsProtoGroupChangesGroupChangeStateBuilder()
        if let _value = groupChange {
            builder.setGroupChange(_value)
        }
        if let _value = groupState {
            builder.setGroupState(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangesGroupChangeStateBuilder {

    private var proto = GroupsProtos_GroupChanges.GroupChangeState()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setGroupChange(_ valueParam: GroupsProtoGroupChange?) {
        guard let valueParam = valueParam else { return }
        proto.groupChange = valueParam.proto
    }

    public mutating func setGroupChange(_ valueParam: GroupsProtoGroupChange) {
        proto.groupChange = valueParam.proto
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setGroupState(_ valueParam: GroupsProtoGroup?) {
        guard let valueParam = valueParam else { return }
        proto.groupState = valueParam.proto
    }

    public mutating func setGroupState(_ valueParam: GroupsProtoGroup) {
        proto.groupState = valueParam.proto
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChangesGroupChangeState {
        return GroupsProtoGroupChangesGroupChangeState(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChangesGroupChangeState {
        return GroupsProtoGroupChangesGroupChangeState(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChangesGroupChangeState(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChangesGroupChangeState {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangesGroupChangeStateBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChangesGroupChangeState? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupChanges

public struct GroupsProtoGroupChanges: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupChanges

    public var groupChanges: [Data] {
        return proto.groupChanges
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupChanges) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupChanges(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupChanges) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupChanges {
    public static func builder() -> GroupsProtoGroupChangesBuilder {
        return GroupsProtoGroupChangesBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupChangesBuilder {
        var builder = GroupsProtoGroupChangesBuilder()
        builder.setGroupChanges(groupChanges)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupChangesBuilder {

    private var proto = GroupsProtos_GroupChanges()

    fileprivate init() {}

    public mutating func addGroupChanges(_ valueParam: Data) {
        proto.groupChanges.append(valueParam)
    }

    public mutating func setGroupChanges(_ wrappedItems: [Data]) {
        proto.groupChanges = wrappedItems
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupChanges {
        return GroupsProtoGroupChanges(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupChanges {
        return GroupsProtoGroupChanges(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupChanges(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupChanges {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupChangesBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupChanges? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupAttributeBlobOneOfContent

public enum GroupsProtoGroupAttributeBlobOneOfContent {
    case title(String)
    case avatar(Data)
    case disappearingMessagesDuration(UInt32)
    case descriptionText(String)
}

private func GroupsProtoGroupAttributeBlobOneOfContentWrap(_ value: GroupsProtos_GroupAttributeBlob.OneOf_Content) throws -> GroupsProtoGroupAttributeBlobOneOfContent {
    switch value {
    case .title(let value): return .title(value)
    case .avatar(let value): return .avatar(value)
    case .disappearingMessagesDuration(let value): return .disappearingMessagesDuration(value)
    case .descriptionText(let value): return .descriptionText(value)
    }
}

private func GroupsProtoGroupAttributeBlobOneOfContentUnwrap(_ value: GroupsProtoGroupAttributeBlobOneOfContent) -> GroupsProtos_GroupAttributeBlob.OneOf_Content {
    switch value {
    case .title(let value): return .title(value)
    case .avatar(let value): return .avatar(value)
    case .disappearingMessagesDuration(let value): return .disappearingMessagesDuration(value)
    case .descriptionText(let value): return .descriptionText(value)
    }
}

// MARK: - GroupsProtoGroupAttributeBlob

public struct GroupsProtoGroupAttributeBlob: Codable, CustomDebugStringConvertible {

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupAttributeBlob) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupAttributeBlob(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupAttributeBlob) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupAttributeBlob {
    public static func builder() -> GroupsProtoGroupAttributeBlobBuilder {
        return GroupsProtoGroupAttributeBlobBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupAttributeBlobBuilder {
        var builder = GroupsProtoGroupAttributeBlobBuilder()
        if let _value = content {
            builder.setContent(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupAttributeBlobBuilder {

    private var proto = GroupsProtos_GroupAttributeBlob()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setContent(_ valueParam: GroupsProtoGroupAttributeBlobOneOfContent?) {
        guard let valueParam = valueParam else { return }
        proto.content = GroupsProtoGroupAttributeBlobOneOfContentUnwrap(valueParam)
    }

    public mutating func setContent(_ valueParam: GroupsProtoGroupAttributeBlobOneOfContent) {
        proto.content = GroupsProtoGroupAttributeBlobOneOfContentUnwrap(valueParam)
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupAttributeBlob {
        return GroupsProtoGroupAttributeBlob(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupAttributeBlob {
        return GroupsProtoGroupAttributeBlob(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupAttributeBlob(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupAttributeBlob {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupAttributeBlobBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupAttributeBlob? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1

public struct GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupInviteLink.GroupInviteLinkContentsV1

    public var groupMasterKey: Data? {
        guard hasGroupMasterKey else {
            return nil
        }
        return proto.groupMasterKey
    }
    public var hasGroupMasterKey: Bool {
        return !proto.groupMasterKey.isEmpty
    }

    public var inviteLinkPassword: Data? {
        guard hasInviteLinkPassword else {
            return nil
        }
        return proto.inviteLinkPassword
    }
    public var hasInviteLinkPassword: Bool {
        return !proto.inviteLinkPassword.isEmpty
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupInviteLink.GroupInviteLinkContentsV1) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupInviteLink.GroupInviteLinkContentsV1(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupInviteLink.GroupInviteLinkContentsV1) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1 {
    public static func builder() -> GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1Builder {
        return GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1Builder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1Builder {
        var builder = GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1Builder()
        if let _value = groupMasterKey {
            builder.setGroupMasterKey(_value)
        }
        if let _value = inviteLinkPassword {
            builder.setInviteLinkPassword(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1Builder {

    private var proto = GroupsProtos_GroupInviteLink.GroupInviteLinkContentsV1()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setGroupMasterKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.groupMasterKey = valueParam
    }

    public mutating func setGroupMasterKey(_ valueParam: Data) {
        proto.groupMasterKey = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setInviteLinkPassword(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.inviteLinkPassword = valueParam
    }

    public mutating func setInviteLinkPassword(_ valueParam: Data) {
        proto.inviteLinkPassword = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1 {
        return GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1 {
        return GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1 {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1Builder {
    public func buildIgnoringErrors() -> GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupInviteLinkOneOfContents

public enum GroupsProtoGroupInviteLinkOneOfContents {
    case contentsV1(GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1)
}

private func GroupsProtoGroupInviteLinkOneOfContentsWrap(_ value: GroupsProtos_GroupInviteLink.OneOf_Contents) throws -> GroupsProtoGroupInviteLinkOneOfContents {
    switch value {
    case .contentsV1(let value): return .contentsV1(GroupsProtoGroupInviteLinkGroupInviteLinkContentsV1(value))
    }
}

private func GroupsProtoGroupInviteLinkOneOfContentsUnwrap(_ value: GroupsProtoGroupInviteLinkOneOfContents) -> GroupsProtos_GroupInviteLink.OneOf_Contents {
    switch value {
    case .contentsV1(let value): return .contentsV1(value.proto)
    }
}

// MARK: - GroupsProtoGroupInviteLink

public struct GroupsProtoGroupInviteLink: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupInviteLink

    public var contents: GroupsProtoGroupInviteLinkOneOfContents? {
        guard hasContents else {
            return nil
        }
        guard let contents = proto.contents else {
            owsFailDebug("contents was unexpectedly nil")
            return nil
        }
        guard let unwrappedContents = try? GroupsProtoGroupInviteLinkOneOfContentsWrap(contents) else {
            owsFailDebug("failed to unwrap contents")
            return nil
        }
        return unwrappedContents
    }
    public var hasContents: Bool {
        return true
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupInviteLink) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupInviteLink(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupInviteLink) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupInviteLink {
    public static func builder() -> GroupsProtoGroupInviteLinkBuilder {
        return GroupsProtoGroupInviteLinkBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupInviteLinkBuilder {
        var builder = GroupsProtoGroupInviteLinkBuilder()
        if let _value = contents {
            builder.setContents(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupInviteLinkBuilder {

    private var proto = GroupsProtos_GroupInviteLink()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setContents(_ valueParam: GroupsProtoGroupInviteLinkOneOfContents?) {
        guard let valueParam = valueParam else { return }
        proto.contents = GroupsProtoGroupInviteLinkOneOfContentsUnwrap(valueParam)
    }

    public mutating func setContents(_ valueParam: GroupsProtoGroupInviteLinkOneOfContents) {
        proto.contents = GroupsProtoGroupInviteLinkOneOfContentsUnwrap(valueParam)
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupInviteLink {
        return GroupsProtoGroupInviteLink(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupInviteLink {
        return GroupsProtoGroupInviteLink(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupInviteLink(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupInviteLink {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupInviteLinkBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupInviteLink? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupJoinInfo

public struct GroupsProtoGroupJoinInfo: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupJoinInfo

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

    public var memberCount: UInt32 {
        return proto.memberCount
    }
    public var hasMemberCount: Bool {
        return true
    }

    public var addFromInviteLink: GroupsProtoAccessControlAccessRequired? {
        guard hasAddFromInviteLink else {
            return nil
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.addFromInviteLink)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    public var unwrappedAddFromInviteLink: GroupsProtoAccessControlAccessRequired {
        if !hasAddFromInviteLink {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: GroupJoinInfo.addFromInviteLink.")
        }
        return GroupsProtoAccessControlAccessRequiredWrap(proto.addFromInviteLink)
    }
    public var hasAddFromInviteLink: Bool {
        return true
    }

    public var revision: UInt32 {
        return proto.revision
    }
    public var hasRevision: Bool {
        return true
    }

    public var pendingAdminApproval: Bool {
        return proto.pendingAdminApproval
    }
    public var hasPendingAdminApproval: Bool {
        return true
    }

    public var descriptionBytes: Data? {
        guard hasDescriptionBytes else {
            return nil
        }
        return proto.descriptionBytes
    }
    public var hasDescriptionBytes: Bool {
        return !proto.descriptionBytes.isEmpty
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupJoinInfo) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupJoinInfo(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupJoinInfo) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupJoinInfo {
    public static func builder() -> GroupsProtoGroupJoinInfoBuilder {
        return GroupsProtoGroupJoinInfoBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupJoinInfoBuilder {
        var builder = GroupsProtoGroupJoinInfoBuilder()
        if let _value = publicKey {
            builder.setPublicKey(_value)
        }
        if let _value = title {
            builder.setTitle(_value)
        }
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if hasMemberCount {
            builder.setMemberCount(memberCount)
        }
        if let _value = addFromInviteLink {
            builder.setAddFromInviteLink(_value)
        }
        if hasRevision {
            builder.setRevision(revision)
        }
        if hasPendingAdminApproval {
            builder.setPendingAdminApproval(pendingAdminApproval)
        }
        if let _value = descriptionBytes {
            builder.setDescriptionBytes(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupJoinInfoBuilder {

    private var proto = GroupsProtos_GroupJoinInfo()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setPublicKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.publicKey = valueParam
    }

    public mutating func setPublicKey(_ valueParam: Data) {
        proto.publicKey = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setTitle(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.title = valueParam
    }

    public mutating func setTitle(_ valueParam: Data) {
        proto.title = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setAvatar(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.avatar = valueParam
    }

    public mutating func setAvatar(_ valueParam: String) {
        proto.avatar = valueParam
    }

    public mutating func setMemberCount(_ valueParam: UInt32) {
        proto.memberCount = valueParam
    }

    public mutating func setAddFromInviteLink(_ valueParam: GroupsProtoAccessControlAccessRequired) {
        proto.addFromInviteLink = GroupsProtoAccessControlAccessRequiredUnwrap(valueParam)
    }

    public mutating func setRevision(_ valueParam: UInt32) {
        proto.revision = valueParam
    }

    public mutating func setPendingAdminApproval(_ valueParam: Bool) {
        proto.pendingAdminApproval = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setDescriptionBytes(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.descriptionBytes = valueParam
    }

    public mutating func setDescriptionBytes(_ valueParam: Data) {
        proto.descriptionBytes = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupJoinInfo {
        return GroupsProtoGroupJoinInfo(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupJoinInfo {
        return GroupsProtoGroupJoinInfo(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupJoinInfo(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupJoinInfo {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupJoinInfoBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupJoinInfo? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - GroupsProtoGroupExternalCredential

public struct GroupsProtoGroupExternalCredential: Codable, CustomDebugStringConvertible {

    fileprivate let proto: GroupsProtos_GroupExternalCredential

    public var token: String? {
        guard hasToken else {
            return nil
        }
        return proto.token
    }
    public var hasToken: Bool {
        return !proto.token.isEmpty
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: GroupsProtos_GroupExternalCredential) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try GroupsProtos_GroupExternalCredential(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate init(_ proto: GroupsProtos_GroupExternalCredential) {
        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension GroupsProtoGroupExternalCredential {
    public static func builder() -> GroupsProtoGroupExternalCredentialBuilder {
        return GroupsProtoGroupExternalCredentialBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> GroupsProtoGroupExternalCredentialBuilder {
        var builder = GroupsProtoGroupExternalCredentialBuilder()
        if let _value = token {
            builder.setToken(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

public struct GroupsProtoGroupExternalCredentialBuilder {

    private var proto = GroupsProtos_GroupExternalCredential()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setToken(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.token = valueParam
    }

    public mutating func setToken(_ valueParam: String) {
        proto.token = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> GroupsProtoGroupExternalCredential {
        return GroupsProtoGroupExternalCredential(proto)
    }

    public func buildInfallibly() -> GroupsProtoGroupExternalCredential {
        return GroupsProtoGroupExternalCredential(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try GroupsProtoGroupExternalCredential(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension GroupsProtoGroupExternalCredential {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension GroupsProtoGroupExternalCredentialBuilder {
    public func buildIgnoringErrors() -> GroupsProtoGroupExternalCredential? {
        return self.buildInfallibly()
    }
}

#endif
