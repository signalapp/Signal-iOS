//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum BackupProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - BackupProtoBackupInfo

@objc
public class BackupProtoBackupInfo: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_BackupInfo

    @objc
    public let version: UInt64

    @objc
    public let backupTime: UInt64

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_BackupInfo,
                 version: UInt64,
                 backupTime: UInt64) {
        self.proto = proto
        self.version = version
        self.backupTime = backupTime
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_BackupInfo(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_BackupInfo) throws {
        guard proto.hasVersion else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: version")
        }
        let version = proto.version

        guard proto.hasBackupTime else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: backupTime")
        }
        let backupTime = proto.backupTime

        self.init(proto: proto,
                  version: version,
                  backupTime: backupTime)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoBackupInfo {
    @objc
    public static func builder(version: UInt64, backupTime: UInt64) -> BackupProtoBackupInfoBuilder {
        return BackupProtoBackupInfoBuilder(version: version, backupTime: backupTime)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoBackupInfoBuilder {
        let builder = BackupProtoBackupInfoBuilder(version: version, backupTime: backupTime)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoBackupInfoBuilder: NSObject {

    private var proto = BackupProtos_BackupInfo()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(version: UInt64, backupTime: UInt64) {
        super.init()

        setVersion(version)
        setBackupTime(backupTime)
    }

    @objc
    public func setVersion(_ valueParam: UInt64) {
        proto.version = valueParam
    }

    @objc
    public func setBackupTime(_ valueParam: UInt64) {
        proto.backupTime = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoBackupInfo {
        return try BackupProtoBackupInfo(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoBackupInfo(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoBackupInfo {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoBackupInfoBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoBackupInfo? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoFrame

@objc
public class BackupProtoFrame: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Frame

    @objc
    public let account: BackupProtoAccountData?

    @objc
    public let recipient: BackupProtoRecipient?

    @objc
    public let chat: BackupProtoChat?

    @objc
    public let chatItem: BackupProtoChatItem?

    @objc
    public let call: BackupProtoCall?

    @objc
    public let stickerPack: BackupProtoStickerPack?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_Frame,
                 account: BackupProtoAccountData?,
                 recipient: BackupProtoRecipient?,
                 chat: BackupProtoChat?,
                 chatItem: BackupProtoChatItem?,
                 call: BackupProtoCall?,
                 stickerPack: BackupProtoStickerPack?) {
        self.proto = proto
        self.account = account
        self.recipient = recipient
        self.chat = chat
        self.chatItem = chatItem
        self.call = call
        self.stickerPack = stickerPack
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_Frame(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Frame) throws {
        var account: BackupProtoAccountData?
        if proto.hasAccount {
            account = try BackupProtoAccountData(proto.account)
        }

        var recipient: BackupProtoRecipient?
        if proto.hasRecipient {
            recipient = try BackupProtoRecipient(proto.recipient)
        }

        var chat: BackupProtoChat?
        if proto.hasChat {
            chat = try BackupProtoChat(proto.chat)
        }

        var chatItem: BackupProtoChatItem?
        if proto.hasChatItem {
            chatItem = try BackupProtoChatItem(proto.chatItem)
        }

        var call: BackupProtoCall?
        if proto.hasCall {
            call = try BackupProtoCall(proto.call)
        }

        var stickerPack: BackupProtoStickerPack?
        if proto.hasStickerPack {
            stickerPack = try BackupProtoStickerPack(proto.stickerPack)
        }

        self.init(proto: proto,
                  account: account,
                  recipient: recipient,
                  chat: chat,
                  chatItem: chatItem,
                  call: call,
                  stickerPack: stickerPack)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoFrame {
    @objc
    public static func builder() -> BackupProtoFrameBuilder {
        return BackupProtoFrameBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoFrameBuilder {
        let builder = BackupProtoFrameBuilder()
        if let _value = account {
            builder.setAccount(_value)
        }
        if let _value = recipient {
            builder.setRecipient(_value)
        }
        if let _value = chat {
            builder.setChat(_value)
        }
        if let _value = chatItem {
            builder.setChatItem(_value)
        }
        if let _value = call {
            builder.setCall(_value)
        }
        if let _value = stickerPack {
            builder.setStickerPack(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoFrameBuilder: NSObject {

    private var proto = BackupProtos_Frame()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAccount(_ valueParam: BackupProtoAccountData?) {
        guard let valueParam = valueParam else { return }
        proto.account = valueParam.proto
    }

    public func setAccount(_ valueParam: BackupProtoAccountData) {
        proto.account = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setRecipient(_ valueParam: BackupProtoRecipient?) {
        guard let valueParam = valueParam else { return }
        proto.recipient = valueParam.proto
    }

    public func setRecipient(_ valueParam: BackupProtoRecipient) {
        proto.recipient = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setChat(_ valueParam: BackupProtoChat?) {
        guard let valueParam = valueParam else { return }
        proto.chat = valueParam.proto
    }

    public func setChat(_ valueParam: BackupProtoChat) {
        proto.chat = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setChatItem(_ valueParam: BackupProtoChatItem?) {
        guard let valueParam = valueParam else { return }
        proto.chatItem = valueParam.proto
    }

    public func setChatItem(_ valueParam: BackupProtoChatItem) {
        proto.chatItem = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCall(_ valueParam: BackupProtoCall?) {
        guard let valueParam = valueParam else { return }
        proto.call = valueParam.proto
    }

    public func setCall(_ valueParam: BackupProtoCall) {
        proto.call = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setStickerPack(_ valueParam: BackupProtoStickerPack?) {
        guard let valueParam = valueParam else { return }
        proto.stickerPack = valueParam.proto
    }

    public func setStickerPack(_ valueParam: BackupProtoStickerPack) {
        proto.stickerPack = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoFrame {
        return try BackupProtoFrame(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoFrame(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoFrame {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoFrameBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoFrame? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoAccountDataUsernameLinkColor

@objc
public enum BackupProtoAccountDataUsernameLinkColor: Int32 {
    case unknown = 0
    case blue = 1
    case white = 2
    case grey = 3
    case olive = 4
    case green = 5
    case orange = 6
    case pink = 7
    case purple = 8
}

private func BackupProtoAccountDataUsernameLinkColorWrap(_ value: BackupProtos_AccountData.UsernameLink.Color) -> BackupProtoAccountDataUsernameLinkColor {
    switch value {
    case .unknown: return .unknown
    case .blue: return .blue
    case .white: return .white
    case .grey: return .grey
    case .olive: return .olive
    case .green: return .green
    case .orange: return .orange
    case .pink: return .pink
    case .purple: return .purple
    }
}

private func BackupProtoAccountDataUsernameLinkColorUnwrap(_ value: BackupProtoAccountDataUsernameLinkColor) -> BackupProtos_AccountData.UsernameLink.Color {
    switch value {
    case .unknown: return .unknown
    case .blue: return .blue
    case .white: return .white
    case .grey: return .grey
    case .olive: return .olive
    case .green: return .green
    case .orange: return .orange
    case .pink: return .pink
    case .purple: return .purple
    }
}

// MARK: - BackupProtoAccountDataUsernameLink

@objc
public class BackupProtoAccountDataUsernameLink: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_AccountData.UsernameLink

    @objc
    public let entropy: Data

    @objc
    public let serverID: Data

    public var color: BackupProtoAccountDataUsernameLinkColor? {
        guard hasColor else {
            return nil
        }
        return BackupProtoAccountDataUsernameLinkColorWrap(proto.color)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedColor: BackupProtoAccountDataUsernameLinkColor {
        if !hasColor {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: UsernameLink.color.")
        }
        return BackupProtoAccountDataUsernameLinkColorWrap(proto.color)
    }
    @objc
    public var hasColor: Bool {
        return proto.hasColor
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_AccountData.UsernameLink,
                 entropy: Data,
                 serverID: Data) {
        self.proto = proto
        self.entropy = entropy
        self.serverID = serverID
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_AccountData.UsernameLink(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_AccountData.UsernameLink) throws {
        guard proto.hasEntropy else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: entropy")
        }
        let entropy = proto.entropy

        guard proto.hasServerID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: serverID")
        }
        let serverID = proto.serverID

        self.init(proto: proto,
                  entropy: entropy,
                  serverID: serverID)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoAccountDataUsernameLink {
    @objc
    public static func builder(entropy: Data, serverID: Data) -> BackupProtoAccountDataUsernameLinkBuilder {
        return BackupProtoAccountDataUsernameLinkBuilder(entropy: entropy, serverID: serverID)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoAccountDataUsernameLinkBuilder {
        let builder = BackupProtoAccountDataUsernameLinkBuilder(entropy: entropy, serverID: serverID)
        if let _value = color {
            builder.setColor(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoAccountDataUsernameLinkBuilder: NSObject {

    private var proto = BackupProtos_AccountData.UsernameLink()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(entropy: Data, serverID: Data) {
        super.init()

        setEntropy(entropy)
        setServerID(serverID)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setEntropy(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.entropy = valueParam
    }

    public func setEntropy(_ valueParam: Data) {
        proto.entropy = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setServerID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.serverID = valueParam
    }

    public func setServerID(_ valueParam: Data) {
        proto.serverID = valueParam
    }

    @objc
    public func setColor(_ valueParam: BackupProtoAccountDataUsernameLinkColor) {
        proto.color = BackupProtoAccountDataUsernameLinkColorUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoAccountDataUsernameLink {
        return try BackupProtoAccountDataUsernameLink(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoAccountDataUsernameLink(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoAccountDataUsernameLink {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoAccountDataUsernameLinkBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoAccountDataUsernameLink? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoAccountDataAccountSettings

@objc
public class BackupProtoAccountDataAccountSettings: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_AccountData.AccountSettings

    @objc
    public let noteToSelfArchived: Bool

    @objc
    public let readReceipts: Bool

    @objc
    public let sealedSenderIndicators: Bool

    @objc
    public let typingIndicators: Bool

    @objc
    public let proxiedLinkPreviews: Bool

    @objc
    public let noteToSelfMarkedUnread: Bool

    @objc
    public let linkPreviews: Bool

    @objc
    public let unlistedPhoneNumber: Bool

    @objc
    public let preferContactAvatars: Bool

    @objc
    public let universalExpireTimer: UInt32

    @objc
    public let displayBadgesOnProfile: Bool

    @objc
    public let keepMutedChatsArchived: Bool

    @objc
    public let myStoriesPrivacyHasBeenSet: Bool

    @objc
    public let onboardingStoryHasBeenViewed: Bool

    @objc
    public let storiesDisabled: Bool

    @objc
    public let onboardingStoryHasBeenRead: Bool

    @objc
    public let groupStoryEducationSheetHasBeenSet: Bool

    @objc
    public let usernameOnboardingHasBeenCompleted: Bool

    @objc
    public var preferredReactionEmoji: [String] {
        return proto.preferredReactionEmoji
    }

    @objc
    public var storyViewReceiptsEnabled: Bool {
        return proto.storyViewReceiptsEnabled
    }
    @objc
    public var hasStoryViewReceiptsEnabled: Bool {
        return proto.hasStoryViewReceiptsEnabled
    }

    public var phoneNumberSharingMode: BackupProtoAccountDataPhoneNumberSharingMode? {
        guard hasPhoneNumberSharingMode else {
            return nil
        }
        return BackupProtoAccountDataPhoneNumberSharingModeWrap(proto.phoneNumberSharingMode)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedPhoneNumberSharingMode: BackupProtoAccountDataPhoneNumberSharingMode {
        if !hasPhoneNumberSharingMode {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: AccountSettings.phoneNumberSharingMode.")
        }
        return BackupProtoAccountDataPhoneNumberSharingModeWrap(proto.phoneNumberSharingMode)
    }
    @objc
    public var hasPhoneNumberSharingMode: Bool {
        return proto.hasPhoneNumberSharingMode
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_AccountData.AccountSettings,
                 noteToSelfArchived: Bool,
                 readReceipts: Bool,
                 sealedSenderIndicators: Bool,
                 typingIndicators: Bool,
                 proxiedLinkPreviews: Bool,
                 noteToSelfMarkedUnread: Bool,
                 linkPreviews: Bool,
                 unlistedPhoneNumber: Bool,
                 preferContactAvatars: Bool,
                 universalExpireTimer: UInt32,
                 displayBadgesOnProfile: Bool,
                 keepMutedChatsArchived: Bool,
                 myStoriesPrivacyHasBeenSet: Bool,
                 onboardingStoryHasBeenViewed: Bool,
                 storiesDisabled: Bool,
                 onboardingStoryHasBeenRead: Bool,
                 groupStoryEducationSheetHasBeenSet: Bool,
                 usernameOnboardingHasBeenCompleted: Bool) {
        self.proto = proto
        self.noteToSelfArchived = noteToSelfArchived
        self.readReceipts = readReceipts
        self.sealedSenderIndicators = sealedSenderIndicators
        self.typingIndicators = typingIndicators
        self.proxiedLinkPreviews = proxiedLinkPreviews
        self.noteToSelfMarkedUnread = noteToSelfMarkedUnread
        self.linkPreviews = linkPreviews
        self.unlistedPhoneNumber = unlistedPhoneNumber
        self.preferContactAvatars = preferContactAvatars
        self.universalExpireTimer = universalExpireTimer
        self.displayBadgesOnProfile = displayBadgesOnProfile
        self.keepMutedChatsArchived = keepMutedChatsArchived
        self.myStoriesPrivacyHasBeenSet = myStoriesPrivacyHasBeenSet
        self.onboardingStoryHasBeenViewed = onboardingStoryHasBeenViewed
        self.storiesDisabled = storiesDisabled
        self.onboardingStoryHasBeenRead = onboardingStoryHasBeenRead
        self.groupStoryEducationSheetHasBeenSet = groupStoryEducationSheetHasBeenSet
        self.usernameOnboardingHasBeenCompleted = usernameOnboardingHasBeenCompleted
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_AccountData.AccountSettings(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_AccountData.AccountSettings) throws {
        guard proto.hasNoteToSelfArchived else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: noteToSelfArchived")
        }
        let noteToSelfArchived = proto.noteToSelfArchived

        guard proto.hasReadReceipts else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: readReceipts")
        }
        let readReceipts = proto.readReceipts

        guard proto.hasSealedSenderIndicators else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: sealedSenderIndicators")
        }
        let sealedSenderIndicators = proto.sealedSenderIndicators

        guard proto.hasTypingIndicators else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: typingIndicators")
        }
        let typingIndicators = proto.typingIndicators

        guard proto.hasProxiedLinkPreviews else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: proxiedLinkPreviews")
        }
        let proxiedLinkPreviews = proto.proxiedLinkPreviews

        guard proto.hasNoteToSelfMarkedUnread else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: noteToSelfMarkedUnread")
        }
        let noteToSelfMarkedUnread = proto.noteToSelfMarkedUnread

        guard proto.hasLinkPreviews else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: linkPreviews")
        }
        let linkPreviews = proto.linkPreviews

        guard proto.hasUnlistedPhoneNumber else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: unlistedPhoneNumber")
        }
        let unlistedPhoneNumber = proto.unlistedPhoneNumber

        guard proto.hasPreferContactAvatars else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: preferContactAvatars")
        }
        let preferContactAvatars = proto.preferContactAvatars

        guard proto.hasUniversalExpireTimer else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: universalExpireTimer")
        }
        let universalExpireTimer = proto.universalExpireTimer

        guard proto.hasDisplayBadgesOnProfile else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: displayBadgesOnProfile")
        }
        let displayBadgesOnProfile = proto.displayBadgesOnProfile

        guard proto.hasKeepMutedChatsArchived else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: keepMutedChatsArchived")
        }
        let keepMutedChatsArchived = proto.keepMutedChatsArchived

        guard proto.hasMyStoriesPrivacyHasBeenSet else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: myStoriesPrivacyHasBeenSet")
        }
        let myStoriesPrivacyHasBeenSet = proto.myStoriesPrivacyHasBeenSet

        guard proto.hasOnboardingStoryHasBeenViewed else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: onboardingStoryHasBeenViewed")
        }
        let onboardingStoryHasBeenViewed = proto.onboardingStoryHasBeenViewed

        guard proto.hasStoriesDisabled else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: storiesDisabled")
        }
        let storiesDisabled = proto.storiesDisabled

        guard proto.hasOnboardingStoryHasBeenRead else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: onboardingStoryHasBeenRead")
        }
        let onboardingStoryHasBeenRead = proto.onboardingStoryHasBeenRead

        guard proto.hasGroupStoryEducationSheetHasBeenSet else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: groupStoryEducationSheetHasBeenSet")
        }
        let groupStoryEducationSheetHasBeenSet = proto.groupStoryEducationSheetHasBeenSet

        guard proto.hasUsernameOnboardingHasBeenCompleted else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: usernameOnboardingHasBeenCompleted")
        }
        let usernameOnboardingHasBeenCompleted = proto.usernameOnboardingHasBeenCompleted

        self.init(proto: proto,
                  noteToSelfArchived: noteToSelfArchived,
                  readReceipts: readReceipts,
                  sealedSenderIndicators: sealedSenderIndicators,
                  typingIndicators: typingIndicators,
                  proxiedLinkPreviews: proxiedLinkPreviews,
                  noteToSelfMarkedUnread: noteToSelfMarkedUnread,
                  linkPreviews: linkPreviews,
                  unlistedPhoneNumber: unlistedPhoneNumber,
                  preferContactAvatars: preferContactAvatars,
                  universalExpireTimer: universalExpireTimer,
                  displayBadgesOnProfile: displayBadgesOnProfile,
                  keepMutedChatsArchived: keepMutedChatsArchived,
                  myStoriesPrivacyHasBeenSet: myStoriesPrivacyHasBeenSet,
                  onboardingStoryHasBeenViewed: onboardingStoryHasBeenViewed,
                  storiesDisabled: storiesDisabled,
                  onboardingStoryHasBeenRead: onboardingStoryHasBeenRead,
                  groupStoryEducationSheetHasBeenSet: groupStoryEducationSheetHasBeenSet,
                  usernameOnboardingHasBeenCompleted: usernameOnboardingHasBeenCompleted)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoAccountDataAccountSettings {
    @objc
    public static func builder(noteToSelfArchived: Bool, readReceipts: Bool, sealedSenderIndicators: Bool, typingIndicators: Bool, proxiedLinkPreviews: Bool, noteToSelfMarkedUnread: Bool, linkPreviews: Bool, unlistedPhoneNumber: Bool, preferContactAvatars: Bool, universalExpireTimer: UInt32, displayBadgesOnProfile: Bool, keepMutedChatsArchived: Bool, myStoriesPrivacyHasBeenSet: Bool, onboardingStoryHasBeenViewed: Bool, storiesDisabled: Bool, onboardingStoryHasBeenRead: Bool, groupStoryEducationSheetHasBeenSet: Bool, usernameOnboardingHasBeenCompleted: Bool) -> BackupProtoAccountDataAccountSettingsBuilder {
        return BackupProtoAccountDataAccountSettingsBuilder(noteToSelfArchived: noteToSelfArchived, readReceipts: readReceipts, sealedSenderIndicators: sealedSenderIndicators, typingIndicators: typingIndicators, proxiedLinkPreviews: proxiedLinkPreviews, noteToSelfMarkedUnread: noteToSelfMarkedUnread, linkPreviews: linkPreviews, unlistedPhoneNumber: unlistedPhoneNumber, preferContactAvatars: preferContactAvatars, universalExpireTimer: universalExpireTimer, displayBadgesOnProfile: displayBadgesOnProfile, keepMutedChatsArchived: keepMutedChatsArchived, myStoriesPrivacyHasBeenSet: myStoriesPrivacyHasBeenSet, onboardingStoryHasBeenViewed: onboardingStoryHasBeenViewed, storiesDisabled: storiesDisabled, onboardingStoryHasBeenRead: onboardingStoryHasBeenRead, groupStoryEducationSheetHasBeenSet: groupStoryEducationSheetHasBeenSet, usernameOnboardingHasBeenCompleted: usernameOnboardingHasBeenCompleted)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoAccountDataAccountSettingsBuilder {
        let builder = BackupProtoAccountDataAccountSettingsBuilder(noteToSelfArchived: noteToSelfArchived, readReceipts: readReceipts, sealedSenderIndicators: sealedSenderIndicators, typingIndicators: typingIndicators, proxiedLinkPreviews: proxiedLinkPreviews, noteToSelfMarkedUnread: noteToSelfMarkedUnread, linkPreviews: linkPreviews, unlistedPhoneNumber: unlistedPhoneNumber, preferContactAvatars: preferContactAvatars, universalExpireTimer: universalExpireTimer, displayBadgesOnProfile: displayBadgesOnProfile, keepMutedChatsArchived: keepMutedChatsArchived, myStoriesPrivacyHasBeenSet: myStoriesPrivacyHasBeenSet, onboardingStoryHasBeenViewed: onboardingStoryHasBeenViewed, storiesDisabled: storiesDisabled, onboardingStoryHasBeenRead: onboardingStoryHasBeenRead, groupStoryEducationSheetHasBeenSet: groupStoryEducationSheetHasBeenSet, usernameOnboardingHasBeenCompleted: usernameOnboardingHasBeenCompleted)
        builder.setPreferredReactionEmoji(preferredReactionEmoji)
        if hasStoryViewReceiptsEnabled {
            builder.setStoryViewReceiptsEnabled(storyViewReceiptsEnabled)
        }
        if let _value = phoneNumberSharingMode {
            builder.setPhoneNumberSharingMode(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoAccountDataAccountSettingsBuilder: NSObject {

    private var proto = BackupProtos_AccountData.AccountSettings()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(noteToSelfArchived: Bool, readReceipts: Bool, sealedSenderIndicators: Bool, typingIndicators: Bool, proxiedLinkPreviews: Bool, noteToSelfMarkedUnread: Bool, linkPreviews: Bool, unlistedPhoneNumber: Bool, preferContactAvatars: Bool, universalExpireTimer: UInt32, displayBadgesOnProfile: Bool, keepMutedChatsArchived: Bool, myStoriesPrivacyHasBeenSet: Bool, onboardingStoryHasBeenViewed: Bool, storiesDisabled: Bool, onboardingStoryHasBeenRead: Bool, groupStoryEducationSheetHasBeenSet: Bool, usernameOnboardingHasBeenCompleted: Bool) {
        super.init()

        setNoteToSelfArchived(noteToSelfArchived)
        setReadReceipts(readReceipts)
        setSealedSenderIndicators(sealedSenderIndicators)
        setTypingIndicators(typingIndicators)
        setProxiedLinkPreviews(proxiedLinkPreviews)
        setNoteToSelfMarkedUnread(noteToSelfMarkedUnread)
        setLinkPreviews(linkPreviews)
        setUnlistedPhoneNumber(unlistedPhoneNumber)
        setPreferContactAvatars(preferContactAvatars)
        setUniversalExpireTimer(universalExpireTimer)
        setDisplayBadgesOnProfile(displayBadgesOnProfile)
        setKeepMutedChatsArchived(keepMutedChatsArchived)
        setMyStoriesPrivacyHasBeenSet(myStoriesPrivacyHasBeenSet)
        setOnboardingStoryHasBeenViewed(onboardingStoryHasBeenViewed)
        setStoriesDisabled(storiesDisabled)
        setOnboardingStoryHasBeenRead(onboardingStoryHasBeenRead)
        setGroupStoryEducationSheetHasBeenSet(groupStoryEducationSheetHasBeenSet)
        setUsernameOnboardingHasBeenCompleted(usernameOnboardingHasBeenCompleted)
    }

    @objc
    public func setNoteToSelfArchived(_ valueParam: Bool) {
        proto.noteToSelfArchived = valueParam
    }

    @objc
    public func setReadReceipts(_ valueParam: Bool) {
        proto.readReceipts = valueParam
    }

    @objc
    public func setSealedSenderIndicators(_ valueParam: Bool) {
        proto.sealedSenderIndicators = valueParam
    }

    @objc
    public func setTypingIndicators(_ valueParam: Bool) {
        proto.typingIndicators = valueParam
    }

    @objc
    public func setProxiedLinkPreviews(_ valueParam: Bool) {
        proto.proxiedLinkPreviews = valueParam
    }

    @objc
    public func setNoteToSelfMarkedUnread(_ valueParam: Bool) {
        proto.noteToSelfMarkedUnread = valueParam
    }

    @objc
    public func setLinkPreviews(_ valueParam: Bool) {
        proto.linkPreviews = valueParam
    }

    @objc
    public func setUnlistedPhoneNumber(_ valueParam: Bool) {
        proto.unlistedPhoneNumber = valueParam
    }

    @objc
    public func setPreferContactAvatars(_ valueParam: Bool) {
        proto.preferContactAvatars = valueParam
    }

    @objc
    public func setUniversalExpireTimer(_ valueParam: UInt32) {
        proto.universalExpireTimer = valueParam
    }

    @objc
    public func addPreferredReactionEmoji(_ valueParam: String) {
        proto.preferredReactionEmoji.append(valueParam)
    }

    @objc
    public func setPreferredReactionEmoji(_ wrappedItems: [String]) {
        proto.preferredReactionEmoji = wrappedItems
    }

    @objc
    public func setDisplayBadgesOnProfile(_ valueParam: Bool) {
        proto.displayBadgesOnProfile = valueParam
    }

    @objc
    public func setKeepMutedChatsArchived(_ valueParam: Bool) {
        proto.keepMutedChatsArchived = valueParam
    }

    @objc
    public func setMyStoriesPrivacyHasBeenSet(_ valueParam: Bool) {
        proto.myStoriesPrivacyHasBeenSet = valueParam
    }

    @objc
    public func setOnboardingStoryHasBeenViewed(_ valueParam: Bool) {
        proto.onboardingStoryHasBeenViewed = valueParam
    }

    @objc
    public func setStoriesDisabled(_ valueParam: Bool) {
        proto.storiesDisabled = valueParam
    }

    @objc
    public func setStoryViewReceiptsEnabled(_ valueParam: Bool) {
        proto.storyViewReceiptsEnabled = valueParam
    }

    @objc
    public func setOnboardingStoryHasBeenRead(_ valueParam: Bool) {
        proto.onboardingStoryHasBeenRead = valueParam
    }

    @objc
    public func setGroupStoryEducationSheetHasBeenSet(_ valueParam: Bool) {
        proto.groupStoryEducationSheetHasBeenSet = valueParam
    }

    @objc
    public func setUsernameOnboardingHasBeenCompleted(_ valueParam: Bool) {
        proto.usernameOnboardingHasBeenCompleted = valueParam
    }

    @objc
    public func setPhoneNumberSharingMode(_ valueParam: BackupProtoAccountDataPhoneNumberSharingMode) {
        proto.phoneNumberSharingMode = BackupProtoAccountDataPhoneNumberSharingModeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoAccountDataAccountSettings {
        return try BackupProtoAccountDataAccountSettings(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoAccountDataAccountSettings(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoAccountDataAccountSettings {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoAccountDataAccountSettingsBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoAccountDataAccountSettings? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoAccountDataPhoneNumberSharingMode

@objc
public enum BackupProtoAccountDataPhoneNumberSharingMode: Int32 {
    case everybody = 0
    case contactsOnly = 1
    case nobody = 2
}

private func BackupProtoAccountDataPhoneNumberSharingModeWrap(_ value: BackupProtos_AccountData.PhoneNumberSharingMode) -> BackupProtoAccountDataPhoneNumberSharingMode {
    switch value {
    case .everybody: return .everybody
    case .contactsOnly: return .contactsOnly
    case .nobody: return .nobody
    }
}

private func BackupProtoAccountDataPhoneNumberSharingModeUnwrap(_ value: BackupProtoAccountDataPhoneNumberSharingMode) -> BackupProtos_AccountData.PhoneNumberSharingMode {
    switch value {
    case .everybody: return .everybody
    case .contactsOnly: return .contactsOnly
    case .nobody: return .nobody
    }
}

// MARK: - BackupProtoAccountData

@objc
public class BackupProtoAccountData: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_AccountData

    @objc
    public let aciIdentityPublicKey: Data

    @objc
    public let aciIdentityPrivateKey: Data

    @objc
    public let pniIdentityPublicKey: Data

    @objc
    public let pniIdentityPrivateKey: Data

    @objc
    public let profileKey: Data

    @objc
    public let usernameLink: BackupProtoAccountDataUsernameLink

    @objc
    public let givenName: String

    @objc
    public let familyName: String

    @objc
    public let avatarPath: String

    @objc
    public let subscriberID: Data

    @objc
    public let subscriberCurrencyCode: String

    @objc
    public let subscriptionManuallyCancelled: Bool

    @objc
    public let accountSettings: BackupProtoAccountDataAccountSettings

    @objc
    public let aci: Data

    @objc
    public let pni: Data

    @objc
    public let e164: UInt64

    @objc
    public var username: String? {
        guard hasUsername else {
            return nil
        }
        return proto.username
    }
    @objc
    public var hasUsername: Bool {
        return proto.hasUsername
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_AccountData,
                 aciIdentityPublicKey: Data,
                 aciIdentityPrivateKey: Data,
                 pniIdentityPublicKey: Data,
                 pniIdentityPrivateKey: Data,
                 profileKey: Data,
                 usernameLink: BackupProtoAccountDataUsernameLink,
                 givenName: String,
                 familyName: String,
                 avatarPath: String,
                 subscriberID: Data,
                 subscriberCurrencyCode: String,
                 subscriptionManuallyCancelled: Bool,
                 accountSettings: BackupProtoAccountDataAccountSettings,
                 aci: Data,
                 pni: Data,
                 e164: UInt64) {
        self.proto = proto
        self.aciIdentityPublicKey = aciIdentityPublicKey
        self.aciIdentityPrivateKey = aciIdentityPrivateKey
        self.pniIdentityPublicKey = pniIdentityPublicKey
        self.pniIdentityPrivateKey = pniIdentityPrivateKey
        self.profileKey = profileKey
        self.usernameLink = usernameLink
        self.givenName = givenName
        self.familyName = familyName
        self.avatarPath = avatarPath
        self.subscriberID = subscriberID
        self.subscriberCurrencyCode = subscriberCurrencyCode
        self.subscriptionManuallyCancelled = subscriptionManuallyCancelled
        self.accountSettings = accountSettings
        self.aci = aci
        self.pni = pni
        self.e164 = e164
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_AccountData(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_AccountData) throws {
        guard proto.hasAciIdentityPublicKey else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: aciIdentityPublicKey")
        }
        let aciIdentityPublicKey = proto.aciIdentityPublicKey

        guard proto.hasAciIdentityPrivateKey else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: aciIdentityPrivateKey")
        }
        let aciIdentityPrivateKey = proto.aciIdentityPrivateKey

        guard proto.hasPniIdentityPublicKey else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: pniIdentityPublicKey")
        }
        let pniIdentityPublicKey = proto.pniIdentityPublicKey

        guard proto.hasPniIdentityPrivateKey else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: pniIdentityPrivateKey")
        }
        let pniIdentityPrivateKey = proto.pniIdentityPrivateKey

        guard proto.hasProfileKey else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: profileKey")
        }
        let profileKey = proto.profileKey

        guard proto.hasUsernameLink else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: usernameLink")
        }
        let usernameLink = try BackupProtoAccountDataUsernameLink(proto.usernameLink)

        guard proto.hasGivenName else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: givenName")
        }
        let givenName = proto.givenName

        guard proto.hasFamilyName else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: familyName")
        }
        let familyName = proto.familyName

        guard proto.hasAvatarPath else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: avatarPath")
        }
        let avatarPath = proto.avatarPath

        guard proto.hasSubscriberID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: subscriberID")
        }
        let subscriberID = proto.subscriberID

        guard proto.hasSubscriberCurrencyCode else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: subscriberCurrencyCode")
        }
        let subscriberCurrencyCode = proto.subscriberCurrencyCode

        guard proto.hasSubscriptionManuallyCancelled else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: subscriptionManuallyCancelled")
        }
        let subscriptionManuallyCancelled = proto.subscriptionManuallyCancelled

        guard proto.hasAccountSettings else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: accountSettings")
        }
        let accountSettings = try BackupProtoAccountDataAccountSettings(proto.accountSettings)

        guard proto.hasAci else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: aci")
        }
        let aci = proto.aci

        guard proto.hasPni else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: pni")
        }
        let pni = proto.pni

        guard proto.hasE164 else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: e164")
        }
        let e164 = proto.e164

        self.init(proto: proto,
                  aciIdentityPublicKey: aciIdentityPublicKey,
                  aciIdentityPrivateKey: aciIdentityPrivateKey,
                  pniIdentityPublicKey: pniIdentityPublicKey,
                  pniIdentityPrivateKey: pniIdentityPrivateKey,
                  profileKey: profileKey,
                  usernameLink: usernameLink,
                  givenName: givenName,
                  familyName: familyName,
                  avatarPath: avatarPath,
                  subscriberID: subscriberID,
                  subscriberCurrencyCode: subscriberCurrencyCode,
                  subscriptionManuallyCancelled: subscriptionManuallyCancelled,
                  accountSettings: accountSettings,
                  aci: aci,
                  pni: pni,
                  e164: e164)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoAccountData {
    @objc
    public static func builder(aciIdentityPublicKey: Data, aciIdentityPrivateKey: Data, pniIdentityPublicKey: Data, pniIdentityPrivateKey: Data, profileKey: Data, usernameLink: BackupProtoAccountDataUsernameLink, givenName: String, familyName: String, avatarPath: String, subscriberID: Data, subscriberCurrencyCode: String, subscriptionManuallyCancelled: Bool, accountSettings: BackupProtoAccountDataAccountSettings, aci: Data, pni: Data, e164: UInt64) -> BackupProtoAccountDataBuilder {
        return BackupProtoAccountDataBuilder(aciIdentityPublicKey: aciIdentityPublicKey, aciIdentityPrivateKey: aciIdentityPrivateKey, pniIdentityPublicKey: pniIdentityPublicKey, pniIdentityPrivateKey: pniIdentityPrivateKey, profileKey: profileKey, usernameLink: usernameLink, givenName: givenName, familyName: familyName, avatarPath: avatarPath, subscriberID: subscriberID, subscriberCurrencyCode: subscriberCurrencyCode, subscriptionManuallyCancelled: subscriptionManuallyCancelled, accountSettings: accountSettings, aci: aci, pni: pni, e164: e164)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoAccountDataBuilder {
        let builder = BackupProtoAccountDataBuilder(aciIdentityPublicKey: aciIdentityPublicKey, aciIdentityPrivateKey: aciIdentityPrivateKey, pniIdentityPublicKey: pniIdentityPublicKey, pniIdentityPrivateKey: pniIdentityPrivateKey, profileKey: profileKey, usernameLink: usernameLink, givenName: givenName, familyName: familyName, avatarPath: avatarPath, subscriberID: subscriberID, subscriberCurrencyCode: subscriberCurrencyCode, subscriptionManuallyCancelled: subscriptionManuallyCancelled, accountSettings: accountSettings, aci: aci, pni: pni, e164: e164)
        if let _value = username {
            builder.setUsername(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoAccountDataBuilder: NSObject {

    private var proto = BackupProtos_AccountData()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(aciIdentityPublicKey: Data, aciIdentityPrivateKey: Data, pniIdentityPublicKey: Data, pniIdentityPrivateKey: Data, profileKey: Data, usernameLink: BackupProtoAccountDataUsernameLink, givenName: String, familyName: String, avatarPath: String, subscriberID: Data, subscriberCurrencyCode: String, subscriptionManuallyCancelled: Bool, accountSettings: BackupProtoAccountDataAccountSettings, aci: Data, pni: Data, e164: UInt64) {
        super.init()

        setAciIdentityPublicKey(aciIdentityPublicKey)
        setAciIdentityPrivateKey(aciIdentityPrivateKey)
        setPniIdentityPublicKey(pniIdentityPublicKey)
        setPniIdentityPrivateKey(pniIdentityPrivateKey)
        setProfileKey(profileKey)
        setUsernameLink(usernameLink)
        setGivenName(givenName)
        setFamilyName(familyName)
        setAvatarPath(avatarPath)
        setSubscriberID(subscriberID)
        setSubscriberCurrencyCode(subscriberCurrencyCode)
        setSubscriptionManuallyCancelled(subscriptionManuallyCancelled)
        setAccountSettings(accountSettings)
        setAci(aci)
        setPni(pni)
        setE164(e164)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAciIdentityPublicKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.aciIdentityPublicKey = valueParam
    }

    public func setAciIdentityPublicKey(_ valueParam: Data) {
        proto.aciIdentityPublicKey = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAciIdentityPrivateKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.aciIdentityPrivateKey = valueParam
    }

    public func setAciIdentityPrivateKey(_ valueParam: Data) {
        proto.aciIdentityPrivateKey = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPniIdentityPublicKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.pniIdentityPublicKey = valueParam
    }

    public func setPniIdentityPublicKey(_ valueParam: Data) {
        proto.pniIdentityPublicKey = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPniIdentityPrivateKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.pniIdentityPrivateKey = valueParam
    }

    public func setPniIdentityPrivateKey(_ valueParam: Data) {
        proto.pniIdentityPrivateKey = valueParam
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
    public func setUsername(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.username = valueParam
    }

    public func setUsername(_ valueParam: String) {
        proto.username = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setUsernameLink(_ valueParam: BackupProtoAccountDataUsernameLink?) {
        guard let valueParam = valueParam else { return }
        proto.usernameLink = valueParam.proto
    }

    public func setUsernameLink(_ valueParam: BackupProtoAccountDataUsernameLink) {
        proto.usernameLink = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGivenName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.givenName = valueParam
    }

    public func setGivenName(_ valueParam: String) {
        proto.givenName = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setFamilyName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.familyName = valueParam
    }

    public func setFamilyName(_ valueParam: String) {
        proto.familyName = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAvatarPath(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.avatarPath = valueParam
    }

    public func setAvatarPath(_ valueParam: String) {
        proto.avatarPath = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSubscriberID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.subscriberID = valueParam
    }

    public func setSubscriberID(_ valueParam: Data) {
        proto.subscriberID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSubscriberCurrencyCode(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.subscriberCurrencyCode = valueParam
    }

    public func setSubscriberCurrencyCode(_ valueParam: String) {
        proto.subscriberCurrencyCode = valueParam
    }

    @objc
    public func setSubscriptionManuallyCancelled(_ valueParam: Bool) {
        proto.subscriptionManuallyCancelled = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAccountSettings(_ valueParam: BackupProtoAccountDataAccountSettings?) {
        guard let valueParam = valueParam else { return }
        proto.accountSettings = valueParam.proto
    }

    public func setAccountSettings(_ valueParam: BackupProtoAccountDataAccountSettings) {
        proto.accountSettings = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAci(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.aci = valueParam
    }

    public func setAci(_ valueParam: Data) {
        proto.aci = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPni(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.pni = valueParam
    }

    public func setPni(_ valueParam: Data) {
        proto.pni = valueParam
    }

    @objc
    public func setE164(_ valueParam: UInt64) {
        proto.e164 = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoAccountData {
        return try BackupProtoAccountData(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoAccountData(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoAccountData {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoAccountDataBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoAccountData? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoRecipient

@objc
public class BackupProtoRecipient: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Recipient

    @objc
    public let id: UInt64

    @objc
    public let contact: BackupProtoContact?

    @objc
    public let group: BackupProtoGroup?

    @objc
    public let distributionList: BackupProtoDistributionList?

    @objc
    public let selfRecipient: BackupProtoSelfRecipient?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_Recipient,
                 id: UInt64,
                 contact: BackupProtoContact?,
                 group: BackupProtoGroup?,
                 distributionList: BackupProtoDistributionList?,
                 selfRecipient: BackupProtoSelfRecipient?) {
        self.proto = proto
        self.id = id
        self.contact = contact
        self.group = group
        self.distributionList = distributionList
        self.selfRecipient = selfRecipient
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_Recipient(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Recipient) throws {
        guard proto.hasID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: id")
        }
        let id = proto.id

        var contact: BackupProtoContact?
        if proto.hasContact {
            contact = try BackupProtoContact(proto.contact)
        }

        var group: BackupProtoGroup?
        if proto.hasGroup {
            group = try BackupProtoGroup(proto.group)
        }

        var distributionList: BackupProtoDistributionList?
        if proto.hasDistributionList {
            distributionList = try BackupProtoDistributionList(proto.distributionList)
        }

        var selfRecipient: BackupProtoSelfRecipient?
        if proto.hasSelfRecipient {
            selfRecipient = BackupProtoSelfRecipient(proto.selfRecipient)
        }

        self.init(proto: proto,
                  id: id,
                  contact: contact,
                  group: group,
                  distributionList: distributionList,
                  selfRecipient: selfRecipient)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoRecipient {
    @objc
    public static func builder(id: UInt64) -> BackupProtoRecipientBuilder {
        return BackupProtoRecipientBuilder(id: id)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoRecipientBuilder {
        let builder = BackupProtoRecipientBuilder(id: id)
        if let _value = contact {
            builder.setContact(_value)
        }
        if let _value = group {
            builder.setGroup(_value)
        }
        if let _value = distributionList {
            builder.setDistributionList(_value)
        }
        if let _value = selfRecipient {
            builder.setSelfRecipient(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoRecipientBuilder: NSObject {

    private var proto = BackupProtos_Recipient()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(id: UInt64) {
        super.init()

        setId(id)
    }

    @objc
    public func setId(_ valueParam: UInt64) {
        proto.id = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setContact(_ valueParam: BackupProtoContact?) {
        guard let valueParam = valueParam else { return }
        proto.contact = valueParam.proto
    }

    public func setContact(_ valueParam: BackupProtoContact) {
        proto.contact = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGroup(_ valueParam: BackupProtoGroup?) {
        guard let valueParam = valueParam else { return }
        proto.group = valueParam.proto
    }

    public func setGroup(_ valueParam: BackupProtoGroup) {
        proto.group = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDistributionList(_ valueParam: BackupProtoDistributionList?) {
        guard let valueParam = valueParam else { return }
        proto.distributionList = valueParam.proto
    }

    public func setDistributionList(_ valueParam: BackupProtoDistributionList) {
        proto.distributionList = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSelfRecipient(_ valueParam: BackupProtoSelfRecipient?) {
        guard let valueParam = valueParam else { return }
        proto.selfRecipient = valueParam.proto
    }

    public func setSelfRecipient(_ valueParam: BackupProtoSelfRecipient) {
        proto.selfRecipient = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoRecipient {
        return try BackupProtoRecipient(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoRecipient(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoRecipient {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoRecipientBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoRecipient? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoContactRegistered

@objc
public enum BackupProtoContactRegistered: Int32 {
    case unknown = 0
    case registered = 1
    case notRegistered = 2
}

private func BackupProtoContactRegisteredWrap(_ value: BackupProtos_Contact.Registered) -> BackupProtoContactRegistered {
    switch value {
    case .unknown: return .unknown
    case .registered: return .registered
    case .notRegistered: return .notRegistered
    }
}

private func BackupProtoContactRegisteredUnwrap(_ value: BackupProtoContactRegistered) -> BackupProtos_Contact.Registered {
    switch value {
    case .unknown: return .unknown
    case .registered: return .registered
    case .notRegistered: return .notRegistered
    }
}

// MARK: - BackupProtoContact

@objc
public class BackupProtoContact: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Contact

    @objc
    public let blocked: Bool

    @objc
    public let hidden: Bool

    @objc
    public let unregisteredTimestamp: UInt64

    @objc
    public let profileSharing: Bool

    @objc
    public let hideStory: Bool

    @objc
    public var aci: Data? {
        guard hasAci else {
            return nil
        }
        return proto.aci
    }
    @objc
    public var hasAci: Bool {
        return proto.hasAci
    }

    @objc
    public var pni: Data? {
        guard hasPni else {
            return nil
        }
        return proto.pni
    }
    @objc
    public var hasPni: Bool {
        return proto.hasPni
    }

    @objc
    public var username: String? {
        guard hasUsername else {
            return nil
        }
        return proto.username
    }
    @objc
    public var hasUsername: Bool {
        return proto.hasUsername
    }

    @objc
    public var e164: UInt64 {
        return proto.e164
    }
    @objc
    public var hasE164: Bool {
        return proto.hasE164
    }

    public var registered: BackupProtoContactRegistered? {
        guard hasRegistered else {
            return nil
        }
        return BackupProtoContactRegisteredWrap(proto.registered)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedRegistered: BackupProtoContactRegistered {
        if !hasRegistered {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Contact.registered.")
        }
        return BackupProtoContactRegisteredWrap(proto.registered)
    }
    @objc
    public var hasRegistered: Bool {
        return proto.hasRegistered
    }

    @objc
    public var profileKey: Data? {
        guard hasProfileKey else {
            return nil
        }
        return proto.profileKey
    }
    @objc
    public var hasProfileKey: Bool {
        return proto.hasProfileKey
    }

    @objc
    public var profileGivenName: String? {
        guard hasProfileGivenName else {
            return nil
        }
        return proto.profileGivenName
    }
    @objc
    public var hasProfileGivenName: Bool {
        return proto.hasProfileGivenName
    }

    @objc
    public var profileFamilyName: String? {
        guard hasProfileFamilyName else {
            return nil
        }
        return proto.profileFamilyName
    }
    @objc
    public var hasProfileFamilyName: Bool {
        return proto.hasProfileFamilyName
    }

    @objc
    public var profileJoinedName: String? {
        guard hasProfileJoinedName else {
            return nil
        }
        return proto.profileJoinedName
    }
    @objc
    public var hasProfileJoinedName: Bool {
        return proto.hasProfileJoinedName
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_Contact,
                 blocked: Bool,
                 hidden: Bool,
                 unregisteredTimestamp: UInt64,
                 profileSharing: Bool,
                 hideStory: Bool) {
        self.proto = proto
        self.blocked = blocked
        self.hidden = hidden
        self.unregisteredTimestamp = unregisteredTimestamp
        self.profileSharing = profileSharing
        self.hideStory = hideStory
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_Contact(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Contact) throws {
        guard proto.hasBlocked else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: blocked")
        }
        let blocked = proto.blocked

        guard proto.hasHidden else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: hidden")
        }
        let hidden = proto.hidden

        guard proto.hasUnregisteredTimestamp else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: unregisteredTimestamp")
        }
        let unregisteredTimestamp = proto.unregisteredTimestamp

        guard proto.hasProfileSharing else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: profileSharing")
        }
        let profileSharing = proto.profileSharing

        guard proto.hasHideStory else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: hideStory")
        }
        let hideStory = proto.hideStory

        self.init(proto: proto,
                  blocked: blocked,
                  hidden: hidden,
                  unregisteredTimestamp: unregisteredTimestamp,
                  profileSharing: profileSharing,
                  hideStory: hideStory)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoContact {
    @objc
    public static func builder(blocked: Bool, hidden: Bool, unregisteredTimestamp: UInt64, profileSharing: Bool, hideStory: Bool) -> BackupProtoContactBuilder {
        return BackupProtoContactBuilder(blocked: blocked, hidden: hidden, unregisteredTimestamp: unregisteredTimestamp, profileSharing: profileSharing, hideStory: hideStory)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoContactBuilder {
        let builder = BackupProtoContactBuilder(blocked: blocked, hidden: hidden, unregisteredTimestamp: unregisteredTimestamp, profileSharing: profileSharing, hideStory: hideStory)
        if let _value = aci {
            builder.setAci(_value)
        }
        if let _value = pni {
            builder.setPni(_value)
        }
        if let _value = username {
            builder.setUsername(_value)
        }
        if hasE164 {
            builder.setE164(e164)
        }
        if let _value = registered {
            builder.setRegistered(_value)
        }
        if let _value = profileKey {
            builder.setProfileKey(_value)
        }
        if let _value = profileGivenName {
            builder.setProfileGivenName(_value)
        }
        if let _value = profileFamilyName {
            builder.setProfileFamilyName(_value)
        }
        if let _value = profileJoinedName {
            builder.setProfileJoinedName(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoContactBuilder: NSObject {

    private var proto = BackupProtos_Contact()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(blocked: Bool, hidden: Bool, unregisteredTimestamp: UInt64, profileSharing: Bool, hideStory: Bool) {
        super.init()

        setBlocked(blocked)
        setHidden(hidden)
        setUnregisteredTimestamp(unregisteredTimestamp)
        setProfileSharing(profileSharing)
        setHideStory(hideStory)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAci(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.aci = valueParam
    }

    public func setAci(_ valueParam: Data) {
        proto.aci = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPni(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.pni = valueParam
    }

    public func setPni(_ valueParam: Data) {
        proto.pni = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setUsername(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.username = valueParam
    }

    public func setUsername(_ valueParam: String) {
        proto.username = valueParam
    }

    @objc
    public func setE164(_ valueParam: UInt64) {
        proto.e164 = valueParam
    }

    @objc
    public func setBlocked(_ valueParam: Bool) {
        proto.blocked = valueParam
    }

    @objc
    public func setHidden(_ valueParam: Bool) {
        proto.hidden = valueParam
    }

    @objc
    public func setRegistered(_ valueParam: BackupProtoContactRegistered) {
        proto.registered = BackupProtoContactRegisteredUnwrap(valueParam)
    }

    @objc
    public func setUnregisteredTimestamp(_ valueParam: UInt64) {
        proto.unregisteredTimestamp = valueParam
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
    public func setProfileSharing(_ valueParam: Bool) {
        proto.profileSharing = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setProfileGivenName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.profileGivenName = valueParam
    }

    public func setProfileGivenName(_ valueParam: String) {
        proto.profileGivenName = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setProfileFamilyName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.profileFamilyName = valueParam
    }

    public func setProfileFamilyName(_ valueParam: String) {
        proto.profileFamilyName = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setProfileJoinedName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.profileJoinedName = valueParam
    }

    public func setProfileJoinedName(_ valueParam: String) {
        proto.profileJoinedName = valueParam
    }

    @objc
    public func setHideStory(_ valueParam: Bool) {
        proto.hideStory = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoContact {
        return try BackupProtoContact(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoContact(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoContact {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoContactBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoContact? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoGroupStorySendMode

@objc
public enum BackupProtoGroupStorySendMode: Int32 {
    case `default` = 0
    case disabled = 1
    case enabled = 2
}

private func BackupProtoGroupStorySendModeWrap(_ value: BackupProtos_Group.StorySendMode) -> BackupProtoGroupStorySendMode {
    switch value {
    case .default: return .default
    case .disabled: return .disabled
    case .enabled: return .enabled
    }
}

private func BackupProtoGroupStorySendModeUnwrap(_ value: BackupProtoGroupStorySendMode) -> BackupProtos_Group.StorySendMode {
    switch value {
    case .default: return .default
    case .disabled: return .disabled
    case .enabled: return .enabled
    }
}

// MARK: - BackupProtoGroup

@objc
public class BackupProtoGroup: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Group

    @objc
    public let masterKey: Data

    @objc
    public let whitelisted: Bool

    @objc
    public let hideStory: Bool

    public var storySendMode: BackupProtoGroupStorySendMode? {
        guard hasStorySendMode else {
            return nil
        }
        return BackupProtoGroupStorySendModeWrap(proto.storySendMode)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedStorySendMode: BackupProtoGroupStorySendMode {
        if !hasStorySendMode {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Group.storySendMode.")
        }
        return BackupProtoGroupStorySendModeWrap(proto.storySendMode)
    }
    @objc
    public var hasStorySendMode: Bool {
        return proto.hasStorySendMode
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_Group,
                 masterKey: Data,
                 whitelisted: Bool,
                 hideStory: Bool) {
        self.proto = proto
        self.masterKey = masterKey
        self.whitelisted = whitelisted
        self.hideStory = hideStory
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_Group(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Group) throws {
        guard proto.hasMasterKey else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: masterKey")
        }
        let masterKey = proto.masterKey

        guard proto.hasWhitelisted else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: whitelisted")
        }
        let whitelisted = proto.whitelisted

        guard proto.hasHideStory else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: hideStory")
        }
        let hideStory = proto.hideStory

        self.init(proto: proto,
                  masterKey: masterKey,
                  whitelisted: whitelisted,
                  hideStory: hideStory)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoGroup {
    @objc
    public static func builder(masterKey: Data, whitelisted: Bool, hideStory: Bool) -> BackupProtoGroupBuilder {
        return BackupProtoGroupBuilder(masterKey: masterKey, whitelisted: whitelisted, hideStory: hideStory)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoGroupBuilder {
        let builder = BackupProtoGroupBuilder(masterKey: masterKey, whitelisted: whitelisted, hideStory: hideStory)
        if let _value = storySendMode {
            builder.setStorySendMode(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoGroupBuilder: NSObject {

    private var proto = BackupProtos_Group()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(masterKey: Data, whitelisted: Bool, hideStory: Bool) {
        super.init()

        setMasterKey(masterKey)
        setWhitelisted(whitelisted)
        setHideStory(hideStory)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMasterKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.masterKey = valueParam
    }

    public func setMasterKey(_ valueParam: Data) {
        proto.masterKey = valueParam
    }

    @objc
    public func setWhitelisted(_ valueParam: Bool) {
        proto.whitelisted = valueParam
    }

    @objc
    public func setHideStory(_ valueParam: Bool) {
        proto.hideStory = valueParam
    }

    @objc
    public func setStorySendMode(_ valueParam: BackupProtoGroupStorySendMode) {
        proto.storySendMode = BackupProtoGroupStorySendModeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoGroup {
        return try BackupProtoGroup(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoGroup(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoGroup {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoGroupBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoGroup? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoSelfRecipient

@objc
public class BackupProtoSelfRecipient: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_SelfRecipient

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_SelfRecipient) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_SelfRecipient(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_SelfRecipient) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoSelfRecipient {
    @objc
    public static func builder() -> BackupProtoSelfRecipientBuilder {
        return BackupProtoSelfRecipientBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoSelfRecipientBuilder {
        let builder = BackupProtoSelfRecipientBuilder()
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoSelfRecipientBuilder: NSObject {

    private var proto = BackupProtos_SelfRecipient()

    @objc
    fileprivate override init() {}

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoSelfRecipient {
        return BackupProtoSelfRecipient(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoSelfRecipient {
        return BackupProtoSelfRecipient(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoSelfRecipient(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoSelfRecipient {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoSelfRecipientBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoSelfRecipient? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoChat

@objc
public class BackupProtoChat: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Chat

    @objc
    public let id: UInt64

    @objc
    public let recipientID: UInt64

    @objc
    public let archived: Bool

    @objc
    public let pinned: Bool

    @objc
    public let expirationTimer: UInt64

    @objc
    public let muteUntil: UInt64

    @objc
    public let markedUnread: Bool

    @objc
    public let dontNotifyForMentionsIfMuted: Bool

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_Chat,
                 id: UInt64,
                 recipientID: UInt64,
                 archived: Bool,
                 pinned: Bool,
                 expirationTimer: UInt64,
                 muteUntil: UInt64,
                 markedUnread: Bool,
                 dontNotifyForMentionsIfMuted: Bool) {
        self.proto = proto
        self.id = id
        self.recipientID = recipientID
        self.archived = archived
        self.pinned = pinned
        self.expirationTimer = expirationTimer
        self.muteUntil = muteUntil
        self.markedUnread = markedUnread
        self.dontNotifyForMentionsIfMuted = dontNotifyForMentionsIfMuted
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_Chat(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Chat) throws {
        guard proto.hasID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: id")
        }
        let id = proto.id

        guard proto.hasRecipientID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: recipientID")
        }
        let recipientID = proto.recipientID

        guard proto.hasArchived else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: archived")
        }
        let archived = proto.archived

        guard proto.hasPinned else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: pinned")
        }
        let pinned = proto.pinned

        guard proto.hasExpirationTimer else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: expirationTimer")
        }
        let expirationTimer = proto.expirationTimer

        guard proto.hasMuteUntil else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: muteUntil")
        }
        let muteUntil = proto.muteUntil

        guard proto.hasMarkedUnread else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: markedUnread")
        }
        let markedUnread = proto.markedUnread

        guard proto.hasDontNotifyForMentionsIfMuted else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: dontNotifyForMentionsIfMuted")
        }
        let dontNotifyForMentionsIfMuted = proto.dontNotifyForMentionsIfMuted

        self.init(proto: proto,
                  id: id,
                  recipientID: recipientID,
                  archived: archived,
                  pinned: pinned,
                  expirationTimer: expirationTimer,
                  muteUntil: muteUntil,
                  markedUnread: markedUnread,
                  dontNotifyForMentionsIfMuted: dontNotifyForMentionsIfMuted)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoChat {
    @objc
    public static func builder(id: UInt64, recipientID: UInt64, archived: Bool, pinned: Bool, expirationTimer: UInt64, muteUntil: UInt64, markedUnread: Bool, dontNotifyForMentionsIfMuted: Bool) -> BackupProtoChatBuilder {
        return BackupProtoChatBuilder(id: id, recipientID: recipientID, archived: archived, pinned: pinned, expirationTimer: expirationTimer, muteUntil: muteUntil, markedUnread: markedUnread, dontNotifyForMentionsIfMuted: dontNotifyForMentionsIfMuted)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoChatBuilder {
        let builder = BackupProtoChatBuilder(id: id, recipientID: recipientID, archived: archived, pinned: pinned, expirationTimer: expirationTimer, muteUntil: muteUntil, markedUnread: markedUnread, dontNotifyForMentionsIfMuted: dontNotifyForMentionsIfMuted)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoChatBuilder: NSObject {

    private var proto = BackupProtos_Chat()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(id: UInt64, recipientID: UInt64, archived: Bool, pinned: Bool, expirationTimer: UInt64, muteUntil: UInt64, markedUnread: Bool, dontNotifyForMentionsIfMuted: Bool) {
        super.init()

        setId(id)
        setRecipientID(recipientID)
        setArchived(archived)
        setPinned(pinned)
        setExpirationTimer(expirationTimer)
        setMuteUntil(muteUntil)
        setMarkedUnread(markedUnread)
        setDontNotifyForMentionsIfMuted(dontNotifyForMentionsIfMuted)
    }

    @objc
    public func setId(_ valueParam: UInt64) {
        proto.id = valueParam
    }

    @objc
    public func setRecipientID(_ valueParam: UInt64) {
        proto.recipientID = valueParam
    }

    @objc
    public func setArchived(_ valueParam: Bool) {
        proto.archived = valueParam
    }

    @objc
    public func setPinned(_ valueParam: Bool) {
        proto.pinned = valueParam
    }

    @objc
    public func setExpirationTimer(_ valueParam: UInt64) {
        proto.expirationTimer = valueParam
    }

    @objc
    public func setMuteUntil(_ valueParam: UInt64) {
        proto.muteUntil = valueParam
    }

    @objc
    public func setMarkedUnread(_ valueParam: Bool) {
        proto.markedUnread = valueParam
    }

    @objc
    public func setDontNotifyForMentionsIfMuted(_ valueParam: Bool) {
        proto.dontNotifyForMentionsIfMuted = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoChat {
        return try BackupProtoChat(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoChat(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoChat {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoChatBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoChat? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoDistributionListPrivacyMode

@objc
public enum BackupProtoDistributionListPrivacyMode: Int32 {
    case onlyWith = 0
    case allExcept = 1
    case all = 2
}

private func BackupProtoDistributionListPrivacyModeWrap(_ value: BackupProtos_DistributionList.PrivacyMode) -> BackupProtoDistributionListPrivacyMode {
    switch value {
    case .onlyWith: return .onlyWith
    case .allExcept: return .allExcept
    case .all: return .all
    }
}

private func BackupProtoDistributionListPrivacyModeUnwrap(_ value: BackupProtoDistributionListPrivacyMode) -> BackupProtos_DistributionList.PrivacyMode {
    switch value {
    case .onlyWith: return .onlyWith
    case .allExcept: return .allExcept
    case .all: return .all
    }
}

// MARK: - BackupProtoDistributionList

@objc
public class BackupProtoDistributionList: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_DistributionList

    @objc
    public let name: String

    @objc
    public let distributionID: Data

    @objc
    public let allowReplies: Bool

    @objc
    public let deletionTimestamp: UInt64

    @objc
    public let isUnknown: Bool

    public var privacyMode: BackupProtoDistributionListPrivacyMode? {
        guard hasPrivacyMode else {
            return nil
        }
        return BackupProtoDistributionListPrivacyModeWrap(proto.privacyMode)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedPrivacyMode: BackupProtoDistributionListPrivacyMode {
        if !hasPrivacyMode {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: DistributionList.privacyMode.")
        }
        return BackupProtoDistributionListPrivacyModeWrap(proto.privacyMode)
    }
    @objc
    public var hasPrivacyMode: Bool {
        return proto.hasPrivacyMode
    }

    @objc
    public var memberRecipientIds: [UInt64] {
        return proto.memberRecipientIds
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_DistributionList,
                 name: String,
                 distributionID: Data,
                 allowReplies: Bool,
                 deletionTimestamp: UInt64,
                 isUnknown: Bool) {
        self.proto = proto
        self.name = name
        self.distributionID = distributionID
        self.allowReplies = allowReplies
        self.deletionTimestamp = deletionTimestamp
        self.isUnknown = isUnknown
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_DistributionList(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_DistributionList) throws {
        guard proto.hasName else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: name")
        }
        let name = proto.name

        guard proto.hasDistributionID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: distributionID")
        }
        let distributionID = proto.distributionID

        guard proto.hasAllowReplies else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: allowReplies")
        }
        let allowReplies = proto.allowReplies

        guard proto.hasDeletionTimestamp else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: deletionTimestamp")
        }
        let deletionTimestamp = proto.deletionTimestamp

        guard proto.hasIsUnknown else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: isUnknown")
        }
        let isUnknown = proto.isUnknown

        self.init(proto: proto,
                  name: name,
                  distributionID: distributionID,
                  allowReplies: allowReplies,
                  deletionTimestamp: deletionTimestamp,
                  isUnknown: isUnknown)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoDistributionList {
    @objc
    public static func builder(name: String, distributionID: Data, allowReplies: Bool, deletionTimestamp: UInt64, isUnknown: Bool) -> BackupProtoDistributionListBuilder {
        return BackupProtoDistributionListBuilder(name: name, distributionID: distributionID, allowReplies: allowReplies, deletionTimestamp: deletionTimestamp, isUnknown: isUnknown)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoDistributionListBuilder {
        let builder = BackupProtoDistributionListBuilder(name: name, distributionID: distributionID, allowReplies: allowReplies, deletionTimestamp: deletionTimestamp, isUnknown: isUnknown)
        if let _value = privacyMode {
            builder.setPrivacyMode(_value)
        }
        builder.setMemberRecipientIds(memberRecipientIds)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoDistributionListBuilder: NSObject {

    private var proto = BackupProtos_DistributionList()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(name: String, distributionID: Data, allowReplies: Bool, deletionTimestamp: UInt64, isUnknown: Bool) {
        super.init()

        setName(name)
        setDistributionID(distributionID)
        setAllowReplies(allowReplies)
        setDeletionTimestamp(deletionTimestamp)
        setIsUnknown(isUnknown)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.name = valueParam
    }

    public func setName(_ valueParam: String) {
        proto.name = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDistributionID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.distributionID = valueParam
    }

    public func setDistributionID(_ valueParam: Data) {
        proto.distributionID = valueParam
    }

    @objc
    public func setAllowReplies(_ valueParam: Bool) {
        proto.allowReplies = valueParam
    }

    @objc
    public func setDeletionTimestamp(_ valueParam: UInt64) {
        proto.deletionTimestamp = valueParam
    }

    @objc
    public func setIsUnknown(_ valueParam: Bool) {
        proto.isUnknown = valueParam
    }

    @objc
    public func setPrivacyMode(_ valueParam: BackupProtoDistributionListPrivacyMode) {
        proto.privacyMode = BackupProtoDistributionListPrivacyModeUnwrap(valueParam)
    }

    @objc
    public func addMemberRecipientIds(_ valueParam: UInt64) {
        proto.memberRecipientIds.append(valueParam)
    }

    @objc
    public func setMemberRecipientIds(_ wrappedItems: [UInt64]) {
        proto.memberRecipientIds = wrappedItems
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoDistributionList {
        return try BackupProtoDistributionList(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoDistributionList(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoDistributionList {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoDistributionListBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoDistributionList? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoIdentity

@objc
public class BackupProtoIdentity: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Identity

    @objc
    public let serviceID: Data

    @objc
    public let identityKey: Data

    @objc
    public let timestamp: UInt64

    @objc
    public let firstUse: Bool

    @objc
    public let verified: Bool

    @objc
    public let nonblockingApproval: Bool

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_Identity,
                 serviceID: Data,
                 identityKey: Data,
                 timestamp: UInt64,
                 firstUse: Bool,
                 verified: Bool,
                 nonblockingApproval: Bool) {
        self.proto = proto
        self.serviceID = serviceID
        self.identityKey = identityKey
        self.timestamp = timestamp
        self.firstUse = firstUse
        self.verified = verified
        self.nonblockingApproval = nonblockingApproval
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_Identity(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Identity) throws {
        guard proto.hasServiceID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: serviceID")
        }
        let serviceID = proto.serviceID

        guard proto.hasIdentityKey else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: identityKey")
        }
        let identityKey = proto.identityKey

        guard proto.hasTimestamp else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        guard proto.hasFirstUse else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: firstUse")
        }
        let firstUse = proto.firstUse

        guard proto.hasVerified else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: verified")
        }
        let verified = proto.verified

        guard proto.hasNonblockingApproval else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: nonblockingApproval")
        }
        let nonblockingApproval = proto.nonblockingApproval

        self.init(proto: proto,
                  serviceID: serviceID,
                  identityKey: identityKey,
                  timestamp: timestamp,
                  firstUse: firstUse,
                  verified: verified,
                  nonblockingApproval: nonblockingApproval)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoIdentity {
    @objc
    public static func builder(serviceID: Data, identityKey: Data, timestamp: UInt64, firstUse: Bool, verified: Bool, nonblockingApproval: Bool) -> BackupProtoIdentityBuilder {
        return BackupProtoIdentityBuilder(serviceID: serviceID, identityKey: identityKey, timestamp: timestamp, firstUse: firstUse, verified: verified, nonblockingApproval: nonblockingApproval)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoIdentityBuilder {
        let builder = BackupProtoIdentityBuilder(serviceID: serviceID, identityKey: identityKey, timestamp: timestamp, firstUse: firstUse, verified: verified, nonblockingApproval: nonblockingApproval)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoIdentityBuilder: NSObject {

    private var proto = BackupProtos_Identity()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(serviceID: Data, identityKey: Data, timestamp: UInt64, firstUse: Bool, verified: Bool, nonblockingApproval: Bool) {
        super.init()

        setServiceID(serviceID)
        setIdentityKey(identityKey)
        setTimestamp(timestamp)
        setFirstUse(firstUse)
        setVerified(verified)
        setNonblockingApproval(nonblockingApproval)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setServiceID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.serviceID = valueParam
    }

    public func setServiceID(_ valueParam: Data) {
        proto.serviceID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setIdentityKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.identityKey = valueParam
    }

    public func setIdentityKey(_ valueParam: Data) {
        proto.identityKey = valueParam
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    @objc
    public func setFirstUse(_ valueParam: Bool) {
        proto.firstUse = valueParam
    }

    @objc
    public func setVerified(_ valueParam: Bool) {
        proto.verified = valueParam
    }

    @objc
    public func setNonblockingApproval(_ valueParam: Bool) {
        proto.nonblockingApproval = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoIdentity {
        return try BackupProtoIdentity(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoIdentity(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoIdentity {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoIdentityBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoIdentity? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoCallType

@objc
public enum BackupProtoCallType: Int32 {
    case audioCall = 0
    case videoCall = 1
    case groupCall = 2
    case adHocCall = 3
}

private func BackupProtoCallTypeWrap(_ value: BackupProtos_Call.TypeEnum) -> BackupProtoCallType {
    switch value {
    case .audioCall: return .audioCall
    case .videoCall: return .videoCall
    case .groupCall: return .groupCall
    case .adHocCall: return .adHocCall
    }
}

private func BackupProtoCallTypeUnwrap(_ value: BackupProtoCallType) -> BackupProtos_Call.TypeEnum {
    switch value {
    case .audioCall: return .audioCall
    case .videoCall: return .videoCall
    case .groupCall: return .groupCall
    case .adHocCall: return .adHocCall
    }
}

// MARK: - BackupProtoCallEvent

@objc
public enum BackupProtoCallEvent: Int32 {
    case outgoing = 0
    case accepted = 1
    case notAccepted = 2
    case missed = 3
    case delete = 4
    case genericGroupCall = 5
    case joined = 6
    case ringing = 7
    case declined = 8
    case outgoingRing = 9
}

private func BackupProtoCallEventWrap(_ value: BackupProtos_Call.Event) -> BackupProtoCallEvent {
    switch value {
    case .outgoing: return .outgoing
    case .accepted: return .accepted
    case .notAccepted: return .notAccepted
    case .missed: return .missed
    case .delete: return .delete
    case .genericGroupCall: return .genericGroupCall
    case .joined: return .joined
    case .ringing: return .ringing
    case .declined: return .declined
    case .outgoingRing: return .outgoingRing
    }
}

private func BackupProtoCallEventUnwrap(_ value: BackupProtoCallEvent) -> BackupProtos_Call.Event {
    switch value {
    case .outgoing: return .outgoing
    case .accepted: return .accepted
    case .notAccepted: return .notAccepted
    case .missed: return .missed
    case .delete: return .delete
    case .genericGroupCall: return .genericGroupCall
    case .joined: return .joined
    case .ringing: return .ringing
    case .declined: return .declined
    case .outgoingRing: return .outgoingRing
    }
}

// MARK: - BackupProtoCall

@objc
public class BackupProtoCall: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Call

    @objc
    public let callID: UInt64

    @objc
    public let peerRecipientID: UInt64

    @objc
    public let outgoing: Bool

    @objc
    public let timestamp: UInt64

    @objc
    public let ringerRecipientID: UInt64

    public var type: BackupProtoCallType? {
        guard hasType else {
            return nil
        }
        return BackupProtoCallTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: BackupProtoCallType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Call.type.")
        }
        return BackupProtoCallTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    public var event: BackupProtoCallEvent? {
        guard hasEvent else {
            return nil
        }
        return BackupProtoCallEventWrap(proto.event)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedEvent: BackupProtoCallEvent {
        if !hasEvent {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Call.event.")
        }
        return BackupProtoCallEventWrap(proto.event)
    }
    @objc
    public var hasEvent: Bool {
        return proto.hasEvent
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_Call,
                 callID: UInt64,
                 peerRecipientID: UInt64,
                 outgoing: Bool,
                 timestamp: UInt64,
                 ringerRecipientID: UInt64) {
        self.proto = proto
        self.callID = callID
        self.peerRecipientID = peerRecipientID
        self.outgoing = outgoing
        self.timestamp = timestamp
        self.ringerRecipientID = ringerRecipientID
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_Call(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Call) throws {
        guard proto.hasCallID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: callID")
        }
        let callID = proto.callID

        guard proto.hasPeerRecipientID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: peerRecipientID")
        }
        let peerRecipientID = proto.peerRecipientID

        guard proto.hasOutgoing else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: outgoing")
        }
        let outgoing = proto.outgoing

        guard proto.hasTimestamp else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        guard proto.hasRingerRecipientID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: ringerRecipientID")
        }
        let ringerRecipientID = proto.ringerRecipientID

        self.init(proto: proto,
                  callID: callID,
                  peerRecipientID: peerRecipientID,
                  outgoing: outgoing,
                  timestamp: timestamp,
                  ringerRecipientID: ringerRecipientID)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoCall {
    @objc
    public static func builder(callID: UInt64, peerRecipientID: UInt64, outgoing: Bool, timestamp: UInt64, ringerRecipientID: UInt64) -> BackupProtoCallBuilder {
        return BackupProtoCallBuilder(callID: callID, peerRecipientID: peerRecipientID, outgoing: outgoing, timestamp: timestamp, ringerRecipientID: ringerRecipientID)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoCallBuilder {
        let builder = BackupProtoCallBuilder(callID: callID, peerRecipientID: peerRecipientID, outgoing: outgoing, timestamp: timestamp, ringerRecipientID: ringerRecipientID)
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = event {
            builder.setEvent(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoCallBuilder: NSObject {

    private var proto = BackupProtos_Call()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(callID: UInt64, peerRecipientID: UInt64, outgoing: Bool, timestamp: UInt64, ringerRecipientID: UInt64) {
        super.init()

        setCallID(callID)
        setPeerRecipientID(peerRecipientID)
        setOutgoing(outgoing)
        setTimestamp(timestamp)
        setRingerRecipientID(ringerRecipientID)
    }

    @objc
    public func setCallID(_ valueParam: UInt64) {
        proto.callID = valueParam
    }

    @objc
    public func setPeerRecipientID(_ valueParam: UInt64) {
        proto.peerRecipientID = valueParam
    }

    @objc
    public func setType(_ valueParam: BackupProtoCallType) {
        proto.type = BackupProtoCallTypeUnwrap(valueParam)
    }

    @objc
    public func setOutgoing(_ valueParam: Bool) {
        proto.outgoing = valueParam
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    @objc
    public func setRingerRecipientID(_ valueParam: UInt64) {
        proto.ringerRecipientID = valueParam
    }

    @objc
    public func setEvent(_ valueParam: BackupProtoCallEvent) {
        proto.event = BackupProtoCallEventUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoCall {
        return try BackupProtoCall(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoCall(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoCall {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoCallBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoCall? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoChatItemIncomingMessageDetails

@objc
public class BackupProtoChatItemIncomingMessageDetails: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ChatItem.IncomingMessageDetails

    @objc
    public let dateServerSent: UInt64

    @objc
    public let read: Bool

    @objc
    public let sealedSender: Bool

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ChatItem.IncomingMessageDetails,
                 dateServerSent: UInt64,
                 read: Bool,
                 sealedSender: Bool) {
        self.proto = proto
        self.dateServerSent = dateServerSent
        self.read = read
        self.sealedSender = sealedSender
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ChatItem.IncomingMessageDetails(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ChatItem.IncomingMessageDetails) throws {
        guard proto.hasDateServerSent else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: dateServerSent")
        }
        let dateServerSent = proto.dateServerSent

        guard proto.hasRead else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: read")
        }
        let read = proto.read

        guard proto.hasSealedSender else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: sealedSender")
        }
        let sealedSender = proto.sealedSender

        self.init(proto: proto,
                  dateServerSent: dateServerSent,
                  read: read,
                  sealedSender: sealedSender)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoChatItemIncomingMessageDetails {
    @objc
    public static func builder(dateServerSent: UInt64, read: Bool, sealedSender: Bool) -> BackupProtoChatItemIncomingMessageDetailsBuilder {
        return BackupProtoChatItemIncomingMessageDetailsBuilder(dateServerSent: dateServerSent, read: read, sealedSender: sealedSender)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoChatItemIncomingMessageDetailsBuilder {
        let builder = BackupProtoChatItemIncomingMessageDetailsBuilder(dateServerSent: dateServerSent, read: read, sealedSender: sealedSender)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoChatItemIncomingMessageDetailsBuilder: NSObject {

    private var proto = BackupProtos_ChatItem.IncomingMessageDetails()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(dateServerSent: UInt64, read: Bool, sealedSender: Bool) {
        super.init()

        setDateServerSent(dateServerSent)
        setRead(read)
        setSealedSender(sealedSender)
    }

    @objc
    public func setDateServerSent(_ valueParam: UInt64) {
        proto.dateServerSent = valueParam
    }

    @objc
    public func setRead(_ valueParam: Bool) {
        proto.read = valueParam
    }

    @objc
    public func setSealedSender(_ valueParam: Bool) {
        proto.sealedSender = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoChatItemIncomingMessageDetails {
        return try BackupProtoChatItemIncomingMessageDetails(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoChatItemIncomingMessageDetails(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoChatItemIncomingMessageDetails {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoChatItemIncomingMessageDetailsBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoChatItemIncomingMessageDetails? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoChatItemOutgoingMessageDetails

@objc
public class BackupProtoChatItemOutgoingMessageDetails: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ChatItem.OutgoingMessageDetails

    @objc
    public let sendStatus: [BackupProtoSendStatus]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ChatItem.OutgoingMessageDetails,
                 sendStatus: [BackupProtoSendStatus]) {
        self.proto = proto
        self.sendStatus = sendStatus
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ChatItem.OutgoingMessageDetails(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ChatItem.OutgoingMessageDetails) throws {
        var sendStatus: [BackupProtoSendStatus] = []
        sendStatus = try proto.sendStatus.map { try BackupProtoSendStatus($0) }

        self.init(proto: proto,
                  sendStatus: sendStatus)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoChatItemOutgoingMessageDetails {
    @objc
    public static func builder() -> BackupProtoChatItemOutgoingMessageDetailsBuilder {
        return BackupProtoChatItemOutgoingMessageDetailsBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoChatItemOutgoingMessageDetailsBuilder {
        let builder = BackupProtoChatItemOutgoingMessageDetailsBuilder()
        builder.setSendStatus(sendStatus)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoChatItemOutgoingMessageDetailsBuilder: NSObject {

    private var proto = BackupProtos_ChatItem.OutgoingMessageDetails()

    @objc
    fileprivate override init() {}

    @objc
    public func addSendStatus(_ valueParam: BackupProtoSendStatus) {
        proto.sendStatus.append(valueParam.proto)
    }

    @objc
    public func setSendStatus(_ wrappedItems: [BackupProtoSendStatus]) {
        proto.sendStatus = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoChatItemOutgoingMessageDetails {
        return try BackupProtoChatItemOutgoingMessageDetails(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoChatItemOutgoingMessageDetails(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoChatItemOutgoingMessageDetails {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoChatItemOutgoingMessageDetailsBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoChatItemOutgoingMessageDetails? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoChatItem

@objc
public class BackupProtoChatItem: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ChatItem

    @objc
    public let chatID: UInt64

    @objc
    public let authorID: UInt64

    @objc
    public let dateSent: UInt64

    @objc
    public let dateReceived: UInt64

    @objc
    public let revisions: [BackupProtoChatItem]

    @objc
    public let sms: Bool

    @objc
    public let incoming: BackupProtoChatItemIncomingMessageDetails?

    @objc
    public let outgoing: BackupProtoChatItemOutgoingMessageDetails?

    @objc
    public let standardMessage: BackupProtoStandardMessage?

    @objc
    public let contactMessage: BackupProtoContactMessage?

    @objc
    public let voiceMessage: BackupProtoVoiceMessage?

    @objc
    public let stickerMessage: BackupProtoStickerMessage?

    @objc
    public let remoteDeletedMessage: BackupProtoRemoteDeletedMessage?

    @objc
    public let updateMessage: BackupProtoUpdateMessage?

    @objc
    public var expireStart: UInt64 {
        return proto.expireStart
    }
    @objc
    public var hasExpireStart: Bool {
        return proto.hasExpireStart
    }

    @objc
    public var expiresIn: UInt64 {
        return proto.expiresIn
    }
    @objc
    public var hasExpiresIn: Bool {
        return proto.hasExpiresIn
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ChatItem,
                 chatID: UInt64,
                 authorID: UInt64,
                 dateSent: UInt64,
                 dateReceived: UInt64,
                 revisions: [BackupProtoChatItem],
                 sms: Bool,
                 incoming: BackupProtoChatItemIncomingMessageDetails?,
                 outgoing: BackupProtoChatItemOutgoingMessageDetails?,
                 standardMessage: BackupProtoStandardMessage?,
                 contactMessage: BackupProtoContactMessage?,
                 voiceMessage: BackupProtoVoiceMessage?,
                 stickerMessage: BackupProtoStickerMessage?,
                 remoteDeletedMessage: BackupProtoRemoteDeletedMessage?,
                 updateMessage: BackupProtoUpdateMessage?) {
        self.proto = proto
        self.chatID = chatID
        self.authorID = authorID
        self.dateSent = dateSent
        self.dateReceived = dateReceived
        self.revisions = revisions
        self.sms = sms
        self.incoming = incoming
        self.outgoing = outgoing
        self.standardMessage = standardMessage
        self.contactMessage = contactMessage
        self.voiceMessage = voiceMessage
        self.stickerMessage = stickerMessage
        self.remoteDeletedMessage = remoteDeletedMessage
        self.updateMessage = updateMessage
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ChatItem(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ChatItem) throws {
        guard proto.hasChatID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: chatID")
        }
        let chatID = proto.chatID

        guard proto.hasAuthorID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: authorID")
        }
        let authorID = proto.authorID

        guard proto.hasDateSent else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: dateSent")
        }
        let dateSent = proto.dateSent

        guard proto.hasDateReceived else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: dateReceived")
        }
        let dateReceived = proto.dateReceived

        var revisions: [BackupProtoChatItem] = []
        revisions = try proto.revisions.map { try BackupProtoChatItem($0) }

        guard proto.hasSms else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: sms")
        }
        let sms = proto.sms

        var incoming: BackupProtoChatItemIncomingMessageDetails?
        if proto.hasIncoming {
            incoming = try BackupProtoChatItemIncomingMessageDetails(proto.incoming)
        }

        var outgoing: BackupProtoChatItemOutgoingMessageDetails?
        if proto.hasOutgoing {
            outgoing = try BackupProtoChatItemOutgoingMessageDetails(proto.outgoing)
        }

        var standardMessage: BackupProtoStandardMessage?
        if proto.hasStandardMessage {
            standardMessage = try BackupProtoStandardMessage(proto.standardMessage)
        }

        var contactMessage: BackupProtoContactMessage?
        if proto.hasContactMessage {
            contactMessage = try BackupProtoContactMessage(proto.contactMessage)
        }

        var voiceMessage: BackupProtoVoiceMessage?
        if proto.hasVoiceMessage {
            voiceMessage = try BackupProtoVoiceMessage(proto.voiceMessage)
        }

        var stickerMessage: BackupProtoStickerMessage?
        if proto.hasStickerMessage {
            stickerMessage = try BackupProtoStickerMessage(proto.stickerMessage)
        }

        var remoteDeletedMessage: BackupProtoRemoteDeletedMessage?
        if proto.hasRemoteDeletedMessage {
            remoteDeletedMessage = BackupProtoRemoteDeletedMessage(proto.remoteDeletedMessage)
        }

        var updateMessage: BackupProtoUpdateMessage?
        if proto.hasUpdateMessage {
            updateMessage = try BackupProtoUpdateMessage(proto.updateMessage)
        }

        self.init(proto: proto,
                  chatID: chatID,
                  authorID: authorID,
                  dateSent: dateSent,
                  dateReceived: dateReceived,
                  revisions: revisions,
                  sms: sms,
                  incoming: incoming,
                  outgoing: outgoing,
                  standardMessage: standardMessage,
                  contactMessage: contactMessage,
                  voiceMessage: voiceMessage,
                  stickerMessage: stickerMessage,
                  remoteDeletedMessage: remoteDeletedMessage,
                  updateMessage: updateMessage)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoChatItem {
    @objc
    public static func builder(chatID: UInt64, authorID: UInt64, dateSent: UInt64, dateReceived: UInt64, sms: Bool) -> BackupProtoChatItemBuilder {
        return BackupProtoChatItemBuilder(chatID: chatID, authorID: authorID, dateSent: dateSent, dateReceived: dateReceived, sms: sms)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoChatItemBuilder {
        let builder = BackupProtoChatItemBuilder(chatID: chatID, authorID: authorID, dateSent: dateSent, dateReceived: dateReceived, sms: sms)
        if hasExpireStart {
            builder.setExpireStart(expireStart)
        }
        if hasExpiresIn {
            builder.setExpiresIn(expiresIn)
        }
        builder.setRevisions(revisions)
        if let _value = incoming {
            builder.setIncoming(_value)
        }
        if let _value = outgoing {
            builder.setOutgoing(_value)
        }
        if let _value = standardMessage {
            builder.setStandardMessage(_value)
        }
        if let _value = contactMessage {
            builder.setContactMessage(_value)
        }
        if let _value = voiceMessage {
            builder.setVoiceMessage(_value)
        }
        if let _value = stickerMessage {
            builder.setStickerMessage(_value)
        }
        if let _value = remoteDeletedMessage {
            builder.setRemoteDeletedMessage(_value)
        }
        if let _value = updateMessage {
            builder.setUpdateMessage(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoChatItemBuilder: NSObject {

    private var proto = BackupProtos_ChatItem()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(chatID: UInt64, authorID: UInt64, dateSent: UInt64, dateReceived: UInt64, sms: Bool) {
        super.init()

        setChatID(chatID)
        setAuthorID(authorID)
        setDateSent(dateSent)
        setDateReceived(dateReceived)
        setSms(sms)
    }

    @objc
    public func setChatID(_ valueParam: UInt64) {
        proto.chatID = valueParam
    }

    @objc
    public func setAuthorID(_ valueParam: UInt64) {
        proto.authorID = valueParam
    }

    @objc
    public func setDateSent(_ valueParam: UInt64) {
        proto.dateSent = valueParam
    }

    @objc
    public func setDateReceived(_ valueParam: UInt64) {
        proto.dateReceived = valueParam
    }

    @objc
    public func setExpireStart(_ valueParam: UInt64) {
        proto.expireStart = valueParam
    }

    @objc
    public func setExpiresIn(_ valueParam: UInt64) {
        proto.expiresIn = valueParam
    }

    @objc
    public func addRevisions(_ valueParam: BackupProtoChatItem) {
        proto.revisions.append(valueParam.proto)
    }

    @objc
    public func setRevisions(_ wrappedItems: [BackupProtoChatItem]) {
        proto.revisions = wrappedItems.map { $0.proto }
    }

    @objc
    public func setSms(_ valueParam: Bool) {
        proto.sms = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setIncoming(_ valueParam: BackupProtoChatItemIncomingMessageDetails?) {
        guard let valueParam = valueParam else { return }
        proto.incoming = valueParam.proto
    }

    public func setIncoming(_ valueParam: BackupProtoChatItemIncomingMessageDetails) {
        proto.incoming = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setOutgoing(_ valueParam: BackupProtoChatItemOutgoingMessageDetails?) {
        guard let valueParam = valueParam else { return }
        proto.outgoing = valueParam.proto
    }

    public func setOutgoing(_ valueParam: BackupProtoChatItemOutgoingMessageDetails) {
        proto.outgoing = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setStandardMessage(_ valueParam: BackupProtoStandardMessage?) {
        guard let valueParam = valueParam else { return }
        proto.standardMessage = valueParam.proto
    }

    public func setStandardMessage(_ valueParam: BackupProtoStandardMessage) {
        proto.standardMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setContactMessage(_ valueParam: BackupProtoContactMessage?) {
        guard let valueParam = valueParam else { return }
        proto.contactMessage = valueParam.proto
    }

    public func setContactMessage(_ valueParam: BackupProtoContactMessage) {
        proto.contactMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setVoiceMessage(_ valueParam: BackupProtoVoiceMessage?) {
        guard let valueParam = valueParam else { return }
        proto.voiceMessage = valueParam.proto
    }

    public func setVoiceMessage(_ valueParam: BackupProtoVoiceMessage) {
        proto.voiceMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setStickerMessage(_ valueParam: BackupProtoStickerMessage?) {
        guard let valueParam = valueParam else { return }
        proto.stickerMessage = valueParam.proto
    }

    public func setStickerMessage(_ valueParam: BackupProtoStickerMessage) {
        proto.stickerMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setRemoteDeletedMessage(_ valueParam: BackupProtoRemoteDeletedMessage?) {
        guard let valueParam = valueParam else { return }
        proto.remoteDeletedMessage = valueParam.proto
    }

    public func setRemoteDeletedMessage(_ valueParam: BackupProtoRemoteDeletedMessage) {
        proto.remoteDeletedMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setUpdateMessage(_ valueParam: BackupProtoUpdateMessage?) {
        guard let valueParam = valueParam else { return }
        proto.updateMessage = valueParam.proto
    }

    public func setUpdateMessage(_ valueParam: BackupProtoUpdateMessage) {
        proto.updateMessage = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoChatItem {
        return try BackupProtoChatItem(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoChatItem(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoChatItem {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoChatItemBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoChatItem? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoSendStatusStatus

@objc
public enum BackupProtoSendStatusStatus: Int32 {
    case failed = 0
    case pending = 1
    case sent = 2
    case delivered = 3
    case read = 4
    case viewed = 5
    case skipped = 6
}

private func BackupProtoSendStatusStatusWrap(_ value: BackupProtos_SendStatus.Status) -> BackupProtoSendStatusStatus {
    switch value {
    case .failed: return .failed
    case .pending: return .pending
    case .sent: return .sent
    case .delivered: return .delivered
    case .read: return .read
    case .viewed: return .viewed
    case .skipped: return .skipped
    }
}

private func BackupProtoSendStatusStatusUnwrap(_ value: BackupProtoSendStatusStatus) -> BackupProtos_SendStatus.Status {
    switch value {
    case .failed: return .failed
    case .pending: return .pending
    case .sent: return .sent
    case .delivered: return .delivered
    case .read: return .read
    case .viewed: return .viewed
    case .skipped: return .skipped
    }
}

// MARK: - BackupProtoSendStatus

@objc
public class BackupProtoSendStatus: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_SendStatus

    @objc
    public let recipientID: UInt64

    @objc
    public let networkFailure: Bool

    @objc
    public let identityKeyMismatch: Bool

    @objc
    public let sealedSender: Bool

    @objc
    public let timestamp: UInt64

    public var deliveryStatus: BackupProtoSendStatusStatus? {
        guard hasDeliveryStatus else {
            return nil
        }
        return BackupProtoSendStatusStatusWrap(proto.deliveryStatus)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedDeliveryStatus: BackupProtoSendStatusStatus {
        if !hasDeliveryStatus {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: SendStatus.deliveryStatus.")
        }
        return BackupProtoSendStatusStatusWrap(proto.deliveryStatus)
    }
    @objc
    public var hasDeliveryStatus: Bool {
        return proto.hasDeliveryStatus
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_SendStatus,
                 recipientID: UInt64,
                 networkFailure: Bool,
                 identityKeyMismatch: Bool,
                 sealedSender: Bool,
                 timestamp: UInt64) {
        self.proto = proto
        self.recipientID = recipientID
        self.networkFailure = networkFailure
        self.identityKeyMismatch = identityKeyMismatch
        self.sealedSender = sealedSender
        self.timestamp = timestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_SendStatus(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_SendStatus) throws {
        guard proto.hasRecipientID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: recipientID")
        }
        let recipientID = proto.recipientID

        guard proto.hasNetworkFailure else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: networkFailure")
        }
        let networkFailure = proto.networkFailure

        guard proto.hasIdentityKeyMismatch else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: identityKeyMismatch")
        }
        let identityKeyMismatch = proto.identityKeyMismatch

        guard proto.hasSealedSender else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: sealedSender")
        }
        let sealedSender = proto.sealedSender

        guard proto.hasTimestamp else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: timestamp")
        }
        let timestamp = proto.timestamp

        self.init(proto: proto,
                  recipientID: recipientID,
                  networkFailure: networkFailure,
                  identityKeyMismatch: identityKeyMismatch,
                  sealedSender: sealedSender,
                  timestamp: timestamp)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoSendStatus {
    @objc
    public static func builder(recipientID: UInt64, networkFailure: Bool, identityKeyMismatch: Bool, sealedSender: Bool, timestamp: UInt64) -> BackupProtoSendStatusBuilder {
        return BackupProtoSendStatusBuilder(recipientID: recipientID, networkFailure: networkFailure, identityKeyMismatch: identityKeyMismatch, sealedSender: sealedSender, timestamp: timestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoSendStatusBuilder {
        let builder = BackupProtoSendStatusBuilder(recipientID: recipientID, networkFailure: networkFailure, identityKeyMismatch: identityKeyMismatch, sealedSender: sealedSender, timestamp: timestamp)
        if let _value = deliveryStatus {
            builder.setDeliveryStatus(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoSendStatusBuilder: NSObject {

    private var proto = BackupProtos_SendStatus()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(recipientID: UInt64, networkFailure: Bool, identityKeyMismatch: Bool, sealedSender: Bool, timestamp: UInt64) {
        super.init()

        setRecipientID(recipientID)
        setNetworkFailure(networkFailure)
        setIdentityKeyMismatch(identityKeyMismatch)
        setSealedSender(sealedSender)
        setTimestamp(timestamp)
    }

    @objc
    public func setRecipientID(_ valueParam: UInt64) {
        proto.recipientID = valueParam
    }

    @objc
    public func setDeliveryStatus(_ valueParam: BackupProtoSendStatusStatus) {
        proto.deliveryStatus = BackupProtoSendStatusStatusUnwrap(valueParam)
    }

    @objc
    public func setNetworkFailure(_ valueParam: Bool) {
        proto.networkFailure = valueParam
    }

    @objc
    public func setIdentityKeyMismatch(_ valueParam: Bool) {
        proto.identityKeyMismatch = valueParam
    }

    @objc
    public func setSealedSender(_ valueParam: Bool) {
        proto.sealedSender = valueParam
    }

    @objc
    public func setTimestamp(_ valueParam: UInt64) {
        proto.timestamp = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoSendStatus {
        return try BackupProtoSendStatus(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoSendStatus(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoSendStatus {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoSendStatusBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoSendStatus? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoText

@objc
public class BackupProtoText: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Text

    @objc
    public let body: String

    @objc
    public let bodyRanges: [BackupProtoBodyRange]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_Text,
                 body: String,
                 bodyRanges: [BackupProtoBodyRange]) {
        self.proto = proto
        self.body = body
        self.bodyRanges = bodyRanges
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_Text(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Text) throws {
        guard proto.hasBody else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: body")
        }
        let body = proto.body

        var bodyRanges: [BackupProtoBodyRange] = []
        bodyRanges = proto.bodyRanges.map { BackupProtoBodyRange($0) }

        self.init(proto: proto,
                  body: body,
                  bodyRanges: bodyRanges)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoText {
    @objc
    public static func builder(body: String) -> BackupProtoTextBuilder {
        return BackupProtoTextBuilder(body: body)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoTextBuilder {
        let builder = BackupProtoTextBuilder(body: body)
        builder.setBodyRanges(bodyRanges)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoTextBuilder: NSObject {

    private var proto = BackupProtos_Text()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(body: String) {
        super.init()

        setBody(body)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBody(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.body = valueParam
    }

    public func setBody(_ valueParam: String) {
        proto.body = valueParam
    }

    @objc
    public func addBodyRanges(_ valueParam: BackupProtoBodyRange) {
        proto.bodyRanges.append(valueParam.proto)
    }

    @objc
    public func setBodyRanges(_ wrappedItems: [BackupProtoBodyRange]) {
        proto.bodyRanges = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoText {
        return try BackupProtoText(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoText(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoText {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoTextBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoText? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoStandardMessage

@objc
public class BackupProtoStandardMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_StandardMessage

    @objc
    public let quote: BackupProtoQuote?

    @objc
    public let text: BackupProtoText?

    @objc
    public let attachments: [BackupProtoAttachmentPointer]

    @objc
    public let linkPreview: BackupProtoLinkPreview?

    @objc
    public let longText: BackupProtoAttachmentPointer?

    @objc
    public let reactions: [BackupProtoReaction]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_StandardMessage,
                 quote: BackupProtoQuote?,
                 text: BackupProtoText?,
                 attachments: [BackupProtoAttachmentPointer],
                 linkPreview: BackupProtoLinkPreview?,
                 longText: BackupProtoAttachmentPointer?,
                 reactions: [BackupProtoReaction]) {
        self.proto = proto
        self.quote = quote
        self.text = text
        self.attachments = attachments
        self.linkPreview = linkPreview
        self.longText = longText
        self.reactions = reactions
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_StandardMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_StandardMessage) throws {
        var quote: BackupProtoQuote?
        if proto.hasQuote {
            quote = BackupProtoQuote(proto.quote)
        }

        var text: BackupProtoText?
        if proto.hasText {
            text = try BackupProtoText(proto.text)
        }

        var attachments: [BackupProtoAttachmentPointer] = []
        attachments = proto.attachments.map { BackupProtoAttachmentPointer($0) }

        var linkPreview: BackupProtoLinkPreview?
        if proto.hasLinkPreview {
            linkPreview = BackupProtoLinkPreview(proto.linkPreview)
        }

        var longText: BackupProtoAttachmentPointer?
        if proto.hasLongText {
            longText = BackupProtoAttachmentPointer(proto.longText)
        }

        var reactions: [BackupProtoReaction] = []
        reactions = try proto.reactions.map { try BackupProtoReaction($0) }

        self.init(proto: proto,
                  quote: quote,
                  text: text,
                  attachments: attachments,
                  linkPreview: linkPreview,
                  longText: longText,
                  reactions: reactions)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoStandardMessage {
    @objc
    public static func builder() -> BackupProtoStandardMessageBuilder {
        return BackupProtoStandardMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoStandardMessageBuilder {
        let builder = BackupProtoStandardMessageBuilder()
        if let _value = quote {
            builder.setQuote(_value)
        }
        if let _value = text {
            builder.setText(_value)
        }
        builder.setAttachments(attachments)
        if let _value = linkPreview {
            builder.setLinkPreview(_value)
        }
        if let _value = longText {
            builder.setLongText(_value)
        }
        builder.setReactions(reactions)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoStandardMessageBuilder: NSObject {

    private var proto = BackupProtos_StandardMessage()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setQuote(_ valueParam: BackupProtoQuote?) {
        guard let valueParam = valueParam else { return }
        proto.quote = valueParam.proto
    }

    public func setQuote(_ valueParam: BackupProtoQuote) {
        proto.quote = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setText(_ valueParam: BackupProtoText?) {
        guard let valueParam = valueParam else { return }
        proto.text = valueParam.proto
    }

    public func setText(_ valueParam: BackupProtoText) {
        proto.text = valueParam.proto
    }

    @objc
    public func addAttachments(_ valueParam: BackupProtoAttachmentPointer) {
        proto.attachments.append(valueParam.proto)
    }

    @objc
    public func setAttachments(_ wrappedItems: [BackupProtoAttachmentPointer]) {
        proto.attachments = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setLinkPreview(_ valueParam: BackupProtoLinkPreview?) {
        guard let valueParam = valueParam else { return }
        proto.linkPreview = valueParam.proto
    }

    public func setLinkPreview(_ valueParam: BackupProtoLinkPreview) {
        proto.linkPreview = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setLongText(_ valueParam: BackupProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.longText = valueParam.proto
    }

    public func setLongText(_ valueParam: BackupProtoAttachmentPointer) {
        proto.longText = valueParam.proto
    }

    @objc
    public func addReactions(_ valueParam: BackupProtoReaction) {
        proto.reactions.append(valueParam.proto)
    }

    @objc
    public func setReactions(_ wrappedItems: [BackupProtoReaction]) {
        proto.reactions = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoStandardMessage {
        return try BackupProtoStandardMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoStandardMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoStandardMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoStandardMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoStandardMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoContactMessage

@objc
public class BackupProtoContactMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ContactMessage

    @objc
    public let contact: [BackupProtoContactAttachment]

    @objc
    public let reactions: [BackupProtoReaction]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ContactMessage,
                 contact: [BackupProtoContactAttachment],
                 reactions: [BackupProtoReaction]) {
        self.proto = proto
        self.contact = contact
        self.reactions = reactions
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ContactMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ContactMessage) throws {
        var contact: [BackupProtoContactAttachment] = []
        contact = proto.contact.map { BackupProtoContactAttachment($0) }

        var reactions: [BackupProtoReaction] = []
        reactions = try proto.reactions.map { try BackupProtoReaction($0) }

        self.init(proto: proto,
                  contact: contact,
                  reactions: reactions)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoContactMessage {
    @objc
    public static func builder() -> BackupProtoContactMessageBuilder {
        return BackupProtoContactMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoContactMessageBuilder {
        let builder = BackupProtoContactMessageBuilder()
        builder.setContact(contact)
        builder.setReactions(reactions)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoContactMessageBuilder: NSObject {

    private var proto = BackupProtos_ContactMessage()

    @objc
    fileprivate override init() {}

    @objc
    public func addContact(_ valueParam: BackupProtoContactAttachment) {
        proto.contact.append(valueParam.proto)
    }

    @objc
    public func setContact(_ wrappedItems: [BackupProtoContactAttachment]) {
        proto.contact = wrappedItems.map { $0.proto }
    }

    @objc
    public func addReactions(_ valueParam: BackupProtoReaction) {
        proto.reactions.append(valueParam.proto)
    }

    @objc
    public func setReactions(_ wrappedItems: [BackupProtoReaction]) {
        proto.reactions = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoContactMessage {
        return try BackupProtoContactMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoContactMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoContactMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoContactMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoContactMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoContactAttachmentName

@objc
public class BackupProtoContactAttachmentName: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ContactAttachment.Name

    @objc
    public var givenName: String? {
        guard hasGivenName else {
            return nil
        }
        return proto.givenName
    }
    @objc
    public var hasGivenName: Bool {
        return proto.hasGivenName
    }

    @objc
    public var familyName: String? {
        guard hasFamilyName else {
            return nil
        }
        return proto.familyName
    }
    @objc
    public var hasFamilyName: Bool {
        return proto.hasFamilyName
    }

    @objc
    public var prefix: String? {
        guard hasPrefix else {
            return nil
        }
        return proto.prefix
    }
    @objc
    public var hasPrefix: Bool {
        return proto.hasPrefix
    }

    @objc
    public var suffix: String? {
        guard hasSuffix else {
            return nil
        }
        return proto.suffix
    }
    @objc
    public var hasSuffix: Bool {
        return proto.hasSuffix
    }

    @objc
    public var middleName: String? {
        guard hasMiddleName else {
            return nil
        }
        return proto.middleName
    }
    @objc
    public var hasMiddleName: Bool {
        return proto.hasMiddleName
    }

    @objc
    public var displayName: String? {
        guard hasDisplayName else {
            return nil
        }
        return proto.displayName
    }
    @objc
    public var hasDisplayName: Bool {
        return proto.hasDisplayName
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ContactAttachment.Name) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ContactAttachment.Name(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ContactAttachment.Name) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoContactAttachmentName {
    @objc
    public static func builder() -> BackupProtoContactAttachmentNameBuilder {
        return BackupProtoContactAttachmentNameBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoContactAttachmentNameBuilder {
        let builder = BackupProtoContactAttachmentNameBuilder()
        if let _value = givenName {
            builder.setGivenName(_value)
        }
        if let _value = familyName {
            builder.setFamilyName(_value)
        }
        if let _value = prefix {
            builder.setPrefix(_value)
        }
        if let _value = suffix {
            builder.setSuffix(_value)
        }
        if let _value = middleName {
            builder.setMiddleName(_value)
        }
        if let _value = displayName {
            builder.setDisplayName(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoContactAttachmentNameBuilder: NSObject {

    private var proto = BackupProtos_ContactAttachment.Name()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGivenName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.givenName = valueParam
    }

    public func setGivenName(_ valueParam: String) {
        proto.givenName = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setFamilyName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.familyName = valueParam
    }

    public func setFamilyName(_ valueParam: String) {
        proto.familyName = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPrefix(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.prefix = valueParam
    }

    public func setPrefix(_ valueParam: String) {
        proto.prefix = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSuffix(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.suffix = valueParam
    }

    public func setSuffix(_ valueParam: String) {
        proto.suffix = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMiddleName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.middleName = valueParam
    }

    public func setMiddleName(_ valueParam: String) {
        proto.middleName = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDisplayName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.displayName = valueParam
    }

    public func setDisplayName(_ valueParam: String) {
        proto.displayName = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoContactAttachmentName {
        return BackupProtoContactAttachmentName(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoContactAttachmentName {
        return BackupProtoContactAttachmentName(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoContactAttachmentName(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoContactAttachmentName {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoContactAttachmentNameBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoContactAttachmentName? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoContactAttachmentPhoneType

@objc
public enum BackupProtoContactAttachmentPhoneType: Int32 {
    case home = 0
    case mobile = 1
    case work = 2
    case custom = 3
}

private func BackupProtoContactAttachmentPhoneTypeWrap(_ value: BackupProtos_ContactAttachment.Phone.TypeEnum) -> BackupProtoContactAttachmentPhoneType {
    switch value {
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

private func BackupProtoContactAttachmentPhoneTypeUnwrap(_ value: BackupProtoContactAttachmentPhoneType) -> BackupProtos_ContactAttachment.Phone.TypeEnum {
    switch value {
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

// MARK: - BackupProtoContactAttachmentPhone

@objc
public class BackupProtoContactAttachmentPhone: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ContactAttachment.Phone

    @objc
    public var value: String? {
        guard hasValue else {
            return nil
        }
        return proto.value
    }
    @objc
    public var hasValue: Bool {
        return proto.hasValue
    }

    public var type: BackupProtoContactAttachmentPhoneType? {
        guard hasType else {
            return nil
        }
        return BackupProtoContactAttachmentPhoneTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: BackupProtoContactAttachmentPhoneType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Phone.type.")
        }
        return BackupProtoContactAttachmentPhoneTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    @objc
    public var label: String? {
        guard hasLabel else {
            return nil
        }
        return proto.label
    }
    @objc
    public var hasLabel: Bool {
        return proto.hasLabel
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ContactAttachment.Phone) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ContactAttachment.Phone(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ContactAttachment.Phone) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoContactAttachmentPhone {
    @objc
    public static func builder() -> BackupProtoContactAttachmentPhoneBuilder {
        return BackupProtoContactAttachmentPhoneBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoContactAttachmentPhoneBuilder {
        let builder = BackupProtoContactAttachmentPhoneBuilder()
        if let _value = value {
            builder.setValue(_value)
        }
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = label {
            builder.setLabel(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoContactAttachmentPhoneBuilder: NSObject {

    private var proto = BackupProtos_ContactAttachment.Phone()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setValue(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.value = valueParam
    }

    public func setValue(_ valueParam: String) {
        proto.value = valueParam
    }

    @objc
    public func setType(_ valueParam: BackupProtoContactAttachmentPhoneType) {
        proto.type = BackupProtoContactAttachmentPhoneTypeUnwrap(valueParam)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setLabel(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.label = valueParam
    }

    public func setLabel(_ valueParam: String) {
        proto.label = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoContactAttachmentPhone {
        return BackupProtoContactAttachmentPhone(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoContactAttachmentPhone {
        return BackupProtoContactAttachmentPhone(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoContactAttachmentPhone(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoContactAttachmentPhone {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoContactAttachmentPhoneBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoContactAttachmentPhone? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoContactAttachmentEmailType

@objc
public enum BackupProtoContactAttachmentEmailType: Int32 {
    case home = 0
    case mobile = 1
    case work = 2
    case custom = 3
}

private func BackupProtoContactAttachmentEmailTypeWrap(_ value: BackupProtos_ContactAttachment.Email.TypeEnum) -> BackupProtoContactAttachmentEmailType {
    switch value {
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

private func BackupProtoContactAttachmentEmailTypeUnwrap(_ value: BackupProtoContactAttachmentEmailType) -> BackupProtos_ContactAttachment.Email.TypeEnum {
    switch value {
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

// MARK: - BackupProtoContactAttachmentEmail

@objc
public class BackupProtoContactAttachmentEmail: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ContactAttachment.Email

    @objc
    public var value: String? {
        guard hasValue else {
            return nil
        }
        return proto.value
    }
    @objc
    public var hasValue: Bool {
        return proto.hasValue
    }

    public var type: BackupProtoContactAttachmentEmailType? {
        guard hasType else {
            return nil
        }
        return BackupProtoContactAttachmentEmailTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: BackupProtoContactAttachmentEmailType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Email.type.")
        }
        return BackupProtoContactAttachmentEmailTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    @objc
    public var label: String? {
        guard hasLabel else {
            return nil
        }
        return proto.label
    }
    @objc
    public var hasLabel: Bool {
        return proto.hasLabel
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ContactAttachment.Email) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ContactAttachment.Email(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ContactAttachment.Email) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoContactAttachmentEmail {
    @objc
    public static func builder() -> BackupProtoContactAttachmentEmailBuilder {
        return BackupProtoContactAttachmentEmailBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoContactAttachmentEmailBuilder {
        let builder = BackupProtoContactAttachmentEmailBuilder()
        if let _value = value {
            builder.setValue(_value)
        }
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = label {
            builder.setLabel(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoContactAttachmentEmailBuilder: NSObject {

    private var proto = BackupProtos_ContactAttachment.Email()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setValue(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.value = valueParam
    }

    public func setValue(_ valueParam: String) {
        proto.value = valueParam
    }

    @objc
    public func setType(_ valueParam: BackupProtoContactAttachmentEmailType) {
        proto.type = BackupProtoContactAttachmentEmailTypeUnwrap(valueParam)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setLabel(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.label = valueParam
    }

    public func setLabel(_ valueParam: String) {
        proto.label = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoContactAttachmentEmail {
        return BackupProtoContactAttachmentEmail(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoContactAttachmentEmail {
        return BackupProtoContactAttachmentEmail(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoContactAttachmentEmail(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoContactAttachmentEmail {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoContactAttachmentEmailBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoContactAttachmentEmail? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoContactAttachmentPostalAddressType

@objc
public enum BackupProtoContactAttachmentPostalAddressType: Int32 {
    case home = 0
    case work = 1
    case custom = 2
}

private func BackupProtoContactAttachmentPostalAddressTypeWrap(_ value: BackupProtos_ContactAttachment.PostalAddress.TypeEnum) -> BackupProtoContactAttachmentPostalAddressType {
    switch value {
    case .home: return .home
    case .work: return .work
    case .custom: return .custom
    }
}

private func BackupProtoContactAttachmentPostalAddressTypeUnwrap(_ value: BackupProtoContactAttachmentPostalAddressType) -> BackupProtos_ContactAttachment.PostalAddress.TypeEnum {
    switch value {
    case .home: return .home
    case .work: return .work
    case .custom: return .custom
    }
}

// MARK: - BackupProtoContactAttachmentPostalAddress

@objc
public class BackupProtoContactAttachmentPostalAddress: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ContactAttachment.PostalAddress

    public var type: BackupProtoContactAttachmentPostalAddressType? {
        guard hasType else {
            return nil
        }
        return BackupProtoContactAttachmentPostalAddressTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: BackupProtoContactAttachmentPostalAddressType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: PostalAddress.type.")
        }
        return BackupProtoContactAttachmentPostalAddressTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    @objc
    public var label: String? {
        guard hasLabel else {
            return nil
        }
        return proto.label
    }
    @objc
    public var hasLabel: Bool {
        return proto.hasLabel
    }

    @objc
    public var street: String? {
        guard hasStreet else {
            return nil
        }
        return proto.street
    }
    @objc
    public var hasStreet: Bool {
        return proto.hasStreet
    }

    @objc
    public var pobox: String? {
        guard hasPobox else {
            return nil
        }
        return proto.pobox
    }
    @objc
    public var hasPobox: Bool {
        return proto.hasPobox
    }

    @objc
    public var neighborhood: String? {
        guard hasNeighborhood else {
            return nil
        }
        return proto.neighborhood
    }
    @objc
    public var hasNeighborhood: Bool {
        return proto.hasNeighborhood
    }

    @objc
    public var city: String? {
        guard hasCity else {
            return nil
        }
        return proto.city
    }
    @objc
    public var hasCity: Bool {
        return proto.hasCity
    }

    @objc
    public var region: String? {
        guard hasRegion else {
            return nil
        }
        return proto.region
    }
    @objc
    public var hasRegion: Bool {
        return proto.hasRegion
    }

    @objc
    public var postcode: String? {
        guard hasPostcode else {
            return nil
        }
        return proto.postcode
    }
    @objc
    public var hasPostcode: Bool {
        return proto.hasPostcode
    }

    @objc
    public var country: String? {
        guard hasCountry else {
            return nil
        }
        return proto.country
    }
    @objc
    public var hasCountry: Bool {
        return proto.hasCountry
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ContactAttachment.PostalAddress) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ContactAttachment.PostalAddress(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ContactAttachment.PostalAddress) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoContactAttachmentPostalAddress {
    @objc
    public static func builder() -> BackupProtoContactAttachmentPostalAddressBuilder {
        return BackupProtoContactAttachmentPostalAddressBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoContactAttachmentPostalAddressBuilder {
        let builder = BackupProtoContactAttachmentPostalAddressBuilder()
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = label {
            builder.setLabel(_value)
        }
        if let _value = street {
            builder.setStreet(_value)
        }
        if let _value = pobox {
            builder.setPobox(_value)
        }
        if let _value = neighborhood {
            builder.setNeighborhood(_value)
        }
        if let _value = city {
            builder.setCity(_value)
        }
        if let _value = region {
            builder.setRegion(_value)
        }
        if let _value = postcode {
            builder.setPostcode(_value)
        }
        if let _value = country {
            builder.setCountry(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoContactAttachmentPostalAddressBuilder: NSObject {

    private var proto = BackupProtos_ContactAttachment.PostalAddress()

    @objc
    fileprivate override init() {}

    @objc
    public func setType(_ valueParam: BackupProtoContactAttachmentPostalAddressType) {
        proto.type = BackupProtoContactAttachmentPostalAddressTypeUnwrap(valueParam)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setLabel(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.label = valueParam
    }

    public func setLabel(_ valueParam: String) {
        proto.label = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setStreet(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.street = valueParam
    }

    public func setStreet(_ valueParam: String) {
        proto.street = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPobox(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.pobox = valueParam
    }

    public func setPobox(_ valueParam: String) {
        proto.pobox = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setNeighborhood(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.neighborhood = valueParam
    }

    public func setNeighborhood(_ valueParam: String) {
        proto.neighborhood = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCity(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.city = valueParam
    }

    public func setCity(_ valueParam: String) {
        proto.city = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setRegion(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.region = valueParam
    }

    public func setRegion(_ valueParam: String) {
        proto.region = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPostcode(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.postcode = valueParam
    }

    public func setPostcode(_ valueParam: String) {
        proto.postcode = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCountry(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.country = valueParam
    }

    public func setCountry(_ valueParam: String) {
        proto.country = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoContactAttachmentPostalAddress {
        return BackupProtoContactAttachmentPostalAddress(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoContactAttachmentPostalAddress {
        return BackupProtoContactAttachmentPostalAddress(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoContactAttachmentPostalAddress(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoContactAttachmentPostalAddress {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoContactAttachmentPostalAddressBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoContactAttachmentPostalAddress? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoContactAttachmentAvatar

@objc
public class BackupProtoContactAttachmentAvatar: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ContactAttachment.Avatar

    @objc
    public let avatar: BackupProtoAttachmentPointer?

    @objc
    public var isProfile: Bool {
        return proto.isProfile
    }
    @objc
    public var hasIsProfile: Bool {
        return proto.hasIsProfile
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ContactAttachment.Avatar,
                 avatar: BackupProtoAttachmentPointer?) {
        self.proto = proto
        self.avatar = avatar
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ContactAttachment.Avatar(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ContactAttachment.Avatar) {
        var avatar: BackupProtoAttachmentPointer?
        if proto.hasAvatar {
            avatar = BackupProtoAttachmentPointer(proto.avatar)
        }

        self.init(proto: proto,
                  avatar: avatar)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoContactAttachmentAvatar {
    @objc
    public static func builder() -> BackupProtoContactAttachmentAvatarBuilder {
        return BackupProtoContactAttachmentAvatarBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoContactAttachmentAvatarBuilder {
        let builder = BackupProtoContactAttachmentAvatarBuilder()
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if hasIsProfile {
            builder.setIsProfile(isProfile)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoContactAttachmentAvatarBuilder: NSObject {

    private var proto = BackupProtos_ContactAttachment.Avatar()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAvatar(_ valueParam: BackupProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.avatar = valueParam.proto
    }

    public func setAvatar(_ valueParam: BackupProtoAttachmentPointer) {
        proto.avatar = valueParam.proto
    }

    @objc
    public func setIsProfile(_ valueParam: Bool) {
        proto.isProfile = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoContactAttachmentAvatar {
        return BackupProtoContactAttachmentAvatar(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoContactAttachmentAvatar {
        return BackupProtoContactAttachmentAvatar(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoContactAttachmentAvatar(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoContactAttachmentAvatar {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoContactAttachmentAvatarBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoContactAttachmentAvatar? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoContactAttachment

@objc
public class BackupProtoContactAttachment: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ContactAttachment

    @objc
    public let name: BackupProtoContactAttachmentName?

    @objc
    public let number: [BackupProtoContactAttachmentPhone]

    @objc
    public let email: [BackupProtoContactAttachmentEmail]

    @objc
    public let address: [BackupProtoContactAttachmentPostalAddress]

    @objc
    public let avatar: BackupProtoContactAttachmentAvatar?

    @objc
    public var organization: String? {
        guard hasOrganization else {
            return nil
        }
        return proto.organization
    }
    @objc
    public var hasOrganization: Bool {
        return proto.hasOrganization
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ContactAttachment,
                 name: BackupProtoContactAttachmentName?,
                 number: [BackupProtoContactAttachmentPhone],
                 email: [BackupProtoContactAttachmentEmail],
                 address: [BackupProtoContactAttachmentPostalAddress],
                 avatar: BackupProtoContactAttachmentAvatar?) {
        self.proto = proto
        self.name = name
        self.number = number
        self.email = email
        self.address = address
        self.avatar = avatar
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ContactAttachment(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ContactAttachment) {
        var name: BackupProtoContactAttachmentName?
        if proto.hasName {
            name = BackupProtoContactAttachmentName(proto.name)
        }

        var number: [BackupProtoContactAttachmentPhone] = []
        number = proto.number.map { BackupProtoContactAttachmentPhone($0) }

        var email: [BackupProtoContactAttachmentEmail] = []
        email = proto.email.map { BackupProtoContactAttachmentEmail($0) }

        var address: [BackupProtoContactAttachmentPostalAddress] = []
        address = proto.address.map { BackupProtoContactAttachmentPostalAddress($0) }

        var avatar: BackupProtoContactAttachmentAvatar?
        if proto.hasAvatar {
            avatar = BackupProtoContactAttachmentAvatar(proto.avatar)
        }

        self.init(proto: proto,
                  name: name,
                  number: number,
                  email: email,
                  address: address,
                  avatar: avatar)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoContactAttachment {
    @objc
    public static func builder() -> BackupProtoContactAttachmentBuilder {
        return BackupProtoContactAttachmentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoContactAttachmentBuilder {
        let builder = BackupProtoContactAttachmentBuilder()
        if let _value = name {
            builder.setName(_value)
        }
        builder.setNumber(number)
        builder.setEmail(email)
        builder.setAddress(address)
        if let _value = avatar {
            builder.setAvatar(_value)
        }
        if let _value = organization {
            builder.setOrganization(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoContactAttachmentBuilder: NSObject {

    private var proto = BackupProtos_ContactAttachment()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setName(_ valueParam: BackupProtoContactAttachmentName?) {
        guard let valueParam = valueParam else { return }
        proto.name = valueParam.proto
    }

    public func setName(_ valueParam: BackupProtoContactAttachmentName) {
        proto.name = valueParam.proto
    }

    @objc
    public func addNumber(_ valueParam: BackupProtoContactAttachmentPhone) {
        proto.number.append(valueParam.proto)
    }

    @objc
    public func setNumber(_ wrappedItems: [BackupProtoContactAttachmentPhone]) {
        proto.number = wrappedItems.map { $0.proto }
    }

    @objc
    public func addEmail(_ valueParam: BackupProtoContactAttachmentEmail) {
        proto.email.append(valueParam.proto)
    }

    @objc
    public func setEmail(_ wrappedItems: [BackupProtoContactAttachmentEmail]) {
        proto.email = wrappedItems.map { $0.proto }
    }

    @objc
    public func addAddress(_ valueParam: BackupProtoContactAttachmentPostalAddress) {
        proto.address.append(valueParam.proto)
    }

    @objc
    public func setAddress(_ wrappedItems: [BackupProtoContactAttachmentPostalAddress]) {
        proto.address = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAvatar(_ valueParam: BackupProtoContactAttachmentAvatar?) {
        guard let valueParam = valueParam else { return }
        proto.avatar = valueParam.proto
    }

    public func setAvatar(_ valueParam: BackupProtoContactAttachmentAvatar) {
        proto.avatar = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setOrganization(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.organization = valueParam
    }

    public func setOrganization(_ valueParam: String) {
        proto.organization = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoContactAttachment {
        return BackupProtoContactAttachment(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoContactAttachment {
        return BackupProtoContactAttachment(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoContactAttachment(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoContactAttachment {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoContactAttachmentBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoContactAttachment? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoDocumentMessage

@objc
public class BackupProtoDocumentMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_DocumentMessage

    @objc
    public let text: BackupProtoText

    @objc
    public let document: BackupProtoAttachmentPointer

    @objc
    public let reactions: [BackupProtoReaction]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_DocumentMessage,
                 text: BackupProtoText,
                 document: BackupProtoAttachmentPointer,
                 reactions: [BackupProtoReaction]) {
        self.proto = proto
        self.text = text
        self.document = document
        self.reactions = reactions
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_DocumentMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_DocumentMessage) throws {
        guard proto.hasText else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: text")
        }
        let text = try BackupProtoText(proto.text)

        guard proto.hasDocument else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: document")
        }
        let document = BackupProtoAttachmentPointer(proto.document)

        var reactions: [BackupProtoReaction] = []
        reactions = try proto.reactions.map { try BackupProtoReaction($0) }

        self.init(proto: proto,
                  text: text,
                  document: document,
                  reactions: reactions)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoDocumentMessage {
    @objc
    public static func builder(text: BackupProtoText, document: BackupProtoAttachmentPointer) -> BackupProtoDocumentMessageBuilder {
        return BackupProtoDocumentMessageBuilder(text: text, document: document)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoDocumentMessageBuilder {
        let builder = BackupProtoDocumentMessageBuilder(text: text, document: document)
        builder.setReactions(reactions)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoDocumentMessageBuilder: NSObject {

    private var proto = BackupProtos_DocumentMessage()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(text: BackupProtoText, document: BackupProtoAttachmentPointer) {
        super.init()

        setText(text)
        setDocument(document)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setText(_ valueParam: BackupProtoText?) {
        guard let valueParam = valueParam else { return }
        proto.text = valueParam.proto
    }

    public func setText(_ valueParam: BackupProtoText) {
        proto.text = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDocument(_ valueParam: BackupProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.document = valueParam.proto
    }

    public func setDocument(_ valueParam: BackupProtoAttachmentPointer) {
        proto.document = valueParam.proto
    }

    @objc
    public func addReactions(_ valueParam: BackupProtoReaction) {
        proto.reactions.append(valueParam.proto)
    }

    @objc
    public func setReactions(_ wrappedItems: [BackupProtoReaction]) {
        proto.reactions = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoDocumentMessage {
        return try BackupProtoDocumentMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoDocumentMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoDocumentMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoDocumentMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoDocumentMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoVoiceMessage

@objc
public class BackupProtoVoiceMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_VoiceMessage

    @objc
    public let quote: BackupProtoQuote?

    @objc
    public let audio: BackupProtoAttachmentPointer

    @objc
    public let reactions: [BackupProtoReaction]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_VoiceMessage,
                 quote: BackupProtoQuote?,
                 audio: BackupProtoAttachmentPointer,
                 reactions: [BackupProtoReaction]) {
        self.proto = proto
        self.quote = quote
        self.audio = audio
        self.reactions = reactions
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_VoiceMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_VoiceMessage) throws {
        var quote: BackupProtoQuote?
        if proto.hasQuote {
            quote = BackupProtoQuote(proto.quote)
        }

        guard proto.hasAudio else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: audio")
        }
        let audio = BackupProtoAttachmentPointer(proto.audio)

        var reactions: [BackupProtoReaction] = []
        reactions = try proto.reactions.map { try BackupProtoReaction($0) }

        self.init(proto: proto,
                  quote: quote,
                  audio: audio,
                  reactions: reactions)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoVoiceMessage {
    @objc
    public static func builder(audio: BackupProtoAttachmentPointer) -> BackupProtoVoiceMessageBuilder {
        return BackupProtoVoiceMessageBuilder(audio: audio)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoVoiceMessageBuilder {
        let builder = BackupProtoVoiceMessageBuilder(audio: audio)
        if let _value = quote {
            builder.setQuote(_value)
        }
        builder.setReactions(reactions)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoVoiceMessageBuilder: NSObject {

    private var proto = BackupProtos_VoiceMessage()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(audio: BackupProtoAttachmentPointer) {
        super.init()

        setAudio(audio)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setQuote(_ valueParam: BackupProtoQuote?) {
        guard let valueParam = valueParam else { return }
        proto.quote = valueParam.proto
    }

    public func setQuote(_ valueParam: BackupProtoQuote) {
        proto.quote = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAudio(_ valueParam: BackupProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.audio = valueParam.proto
    }

    public func setAudio(_ valueParam: BackupProtoAttachmentPointer) {
        proto.audio = valueParam.proto
    }

    @objc
    public func addReactions(_ valueParam: BackupProtoReaction) {
        proto.reactions.append(valueParam.proto)
    }

    @objc
    public func setReactions(_ wrappedItems: [BackupProtoReaction]) {
        proto.reactions = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoVoiceMessage {
        return try BackupProtoVoiceMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoVoiceMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoVoiceMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoVoiceMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoVoiceMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoStickerMessage

@objc
public class BackupProtoStickerMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_StickerMessage

    @objc
    public let sticker: BackupProtoSticker

    @objc
    public let reactions: [BackupProtoReaction]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_StickerMessage,
                 sticker: BackupProtoSticker,
                 reactions: [BackupProtoReaction]) {
        self.proto = proto
        self.sticker = sticker
        self.reactions = reactions
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_StickerMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_StickerMessage) throws {
        guard proto.hasSticker else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: sticker")
        }
        let sticker = BackupProtoSticker(proto.sticker)

        var reactions: [BackupProtoReaction] = []
        reactions = try proto.reactions.map { try BackupProtoReaction($0) }

        self.init(proto: proto,
                  sticker: sticker,
                  reactions: reactions)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoStickerMessage {
    @objc
    public static func builder(sticker: BackupProtoSticker) -> BackupProtoStickerMessageBuilder {
        return BackupProtoStickerMessageBuilder(sticker: sticker)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoStickerMessageBuilder {
        let builder = BackupProtoStickerMessageBuilder(sticker: sticker)
        builder.setReactions(reactions)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoStickerMessageBuilder: NSObject {

    private var proto = BackupProtos_StickerMessage()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(sticker: BackupProtoSticker) {
        super.init()

        setSticker(sticker)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSticker(_ valueParam: BackupProtoSticker?) {
        guard let valueParam = valueParam else { return }
        proto.sticker = valueParam.proto
    }

    public func setSticker(_ valueParam: BackupProtoSticker) {
        proto.sticker = valueParam.proto
    }

    @objc
    public func addReactions(_ valueParam: BackupProtoReaction) {
        proto.reactions.append(valueParam.proto)
    }

    @objc
    public func setReactions(_ wrappedItems: [BackupProtoReaction]) {
        proto.reactions = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoStickerMessage {
        return try BackupProtoStickerMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoStickerMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoStickerMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoStickerMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoStickerMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoRemoteDeletedMessage

@objc
public class BackupProtoRemoteDeletedMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_RemoteDeletedMessage

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_RemoteDeletedMessage) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_RemoteDeletedMessage(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_RemoteDeletedMessage) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoRemoteDeletedMessage {
    @objc
    public static func builder() -> BackupProtoRemoteDeletedMessageBuilder {
        return BackupProtoRemoteDeletedMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoRemoteDeletedMessageBuilder {
        let builder = BackupProtoRemoteDeletedMessageBuilder()
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoRemoteDeletedMessageBuilder: NSObject {

    private var proto = BackupProtos_RemoteDeletedMessage()

    @objc
    fileprivate override init() {}

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoRemoteDeletedMessage {
        return BackupProtoRemoteDeletedMessage(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoRemoteDeletedMessage {
        return BackupProtoRemoteDeletedMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoRemoteDeletedMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoRemoteDeletedMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoRemoteDeletedMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoRemoteDeletedMessage? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoScheduledMessage

@objc
public class BackupProtoScheduledMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ScheduledMessage

    @objc
    public let message: BackupProtoChatItem

    @objc
    public let scheduledTime: UInt64

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ScheduledMessage,
                 message: BackupProtoChatItem,
                 scheduledTime: UInt64) {
        self.proto = proto
        self.message = message
        self.scheduledTime = scheduledTime
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ScheduledMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ScheduledMessage) throws {
        guard proto.hasMessage else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: message")
        }
        let message = try BackupProtoChatItem(proto.message)

        guard proto.hasScheduledTime else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: scheduledTime")
        }
        let scheduledTime = proto.scheduledTime

        self.init(proto: proto,
                  message: message,
                  scheduledTime: scheduledTime)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoScheduledMessage {
    @objc
    public static func builder(message: BackupProtoChatItem, scheduledTime: UInt64) -> BackupProtoScheduledMessageBuilder {
        return BackupProtoScheduledMessageBuilder(message: message, scheduledTime: scheduledTime)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoScheduledMessageBuilder {
        let builder = BackupProtoScheduledMessageBuilder(message: message, scheduledTime: scheduledTime)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoScheduledMessageBuilder: NSObject {

    private var proto = BackupProtos_ScheduledMessage()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(message: BackupProtoChatItem, scheduledTime: UInt64) {
        super.init()

        setMessage(message)
        setScheduledTime(scheduledTime)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMessage(_ valueParam: BackupProtoChatItem?) {
        guard let valueParam = valueParam else { return }
        proto.message = valueParam.proto
    }

    public func setMessage(_ valueParam: BackupProtoChatItem) {
        proto.message = valueParam.proto
    }

    @objc
    public func setScheduledTime(_ valueParam: UInt64) {
        proto.scheduledTime = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoScheduledMessage {
        return try BackupProtoScheduledMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoScheduledMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoScheduledMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoScheduledMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoScheduledMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoSticker

@objc
public class BackupProtoSticker: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Sticker

    @objc
    public let data: BackupProtoAttachmentPointer?

    @objc
    public var packID: Data? {
        guard hasPackID else {
            return nil
        }
        return proto.packID
    }
    @objc
    public var hasPackID: Bool {
        return proto.hasPackID
    }

    @objc
    public var packKey: Data? {
        guard hasPackKey else {
            return nil
        }
        return proto.packKey
    }
    @objc
    public var hasPackKey: Bool {
        return proto.hasPackKey
    }

    @objc
    public var stickerID: UInt32 {
        return proto.stickerID
    }
    @objc
    public var hasStickerID: Bool {
        return proto.hasStickerID
    }

    @objc
    public var emoji: String? {
        guard hasEmoji else {
            return nil
        }
        return proto.emoji
    }
    @objc
    public var hasEmoji: Bool {
        return proto.hasEmoji
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_Sticker,
                 data: BackupProtoAttachmentPointer?) {
        self.proto = proto
        self.data = data
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_Sticker(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Sticker) {
        var data: BackupProtoAttachmentPointer?
        if proto.hasData {
            data = BackupProtoAttachmentPointer(proto.data)
        }

        self.init(proto: proto,
                  data: data)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoSticker {
    @objc
    public static func builder() -> BackupProtoStickerBuilder {
        return BackupProtoStickerBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoStickerBuilder {
        let builder = BackupProtoStickerBuilder()
        if let _value = packID {
            builder.setPackID(_value)
        }
        if let _value = packKey {
            builder.setPackKey(_value)
        }
        if hasStickerID {
            builder.setStickerID(stickerID)
        }
        if let _value = data {
            builder.setData(_value)
        }
        if let _value = emoji {
            builder.setEmoji(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoStickerBuilder: NSObject {

    private var proto = BackupProtos_Sticker()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPackID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.packID = valueParam
    }

    public func setPackID(_ valueParam: Data) {
        proto.packID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPackKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.packKey = valueParam
    }

    public func setPackKey(_ valueParam: Data) {
        proto.packKey = valueParam
    }

    @objc
    public func setStickerID(_ valueParam: UInt32) {
        proto.stickerID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setData(_ valueParam: BackupProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.data = valueParam.proto
    }

    public func setData(_ valueParam: BackupProtoAttachmentPointer) {
        proto.data = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setEmoji(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.emoji = valueParam
    }

    public func setEmoji(_ valueParam: String) {
        proto.emoji = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoSticker {
        return BackupProtoSticker(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoSticker {
        return BackupProtoSticker(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoSticker(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoSticker {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoStickerBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoSticker? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoLinkPreview

@objc
public class BackupProtoLinkPreview: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_LinkPreview

    @objc
    public let image: BackupProtoAttachmentPointer?

    @objc
    public var url: String? {
        guard hasURL else {
            return nil
        }
        return proto.url
    }
    @objc
    public var hasURL: Bool {
        return proto.hasURL
    }

    @objc
    public var title: String? {
        guard hasTitle else {
            return nil
        }
        return proto.title
    }
    @objc
    public var hasTitle: Bool {
        return proto.hasTitle
    }

    @objc
    public var descriptionText: String? {
        guard hasDescriptionText else {
            return nil
        }
        return proto.descriptionText
    }
    @objc
    public var hasDescriptionText: Bool {
        return proto.hasDescriptionText
    }

    @objc
    public var date: UInt64 {
        return proto.date
    }
    @objc
    public var hasDate: Bool {
        return proto.hasDate
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_LinkPreview,
                 image: BackupProtoAttachmentPointer?) {
        self.proto = proto
        self.image = image
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_LinkPreview(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_LinkPreview) {
        var image: BackupProtoAttachmentPointer?
        if proto.hasImage {
            image = BackupProtoAttachmentPointer(proto.image)
        }

        self.init(proto: proto,
                  image: image)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoLinkPreview {
    @objc
    public static func builder() -> BackupProtoLinkPreviewBuilder {
        return BackupProtoLinkPreviewBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoLinkPreviewBuilder {
        let builder = BackupProtoLinkPreviewBuilder()
        if let _value = url {
            builder.setUrl(_value)
        }
        if let _value = title {
            builder.setTitle(_value)
        }
        if let _value = image {
            builder.setImage(_value)
        }
        if let _value = descriptionText {
            builder.setDescriptionText(_value)
        }
        if hasDate {
            builder.setDate(date)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoLinkPreviewBuilder: NSObject {

    private var proto = BackupProtos_LinkPreview()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setUrl(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.url = valueParam
    }

    public func setUrl(_ valueParam: String) {
        proto.url = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setTitle(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.title = valueParam
    }

    public func setTitle(_ valueParam: String) {
        proto.title = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setImage(_ valueParam: BackupProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.image = valueParam.proto
    }

    public func setImage(_ valueParam: BackupProtoAttachmentPointer) {
        proto.image = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDescriptionText(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.descriptionText = valueParam
    }

    public func setDescriptionText(_ valueParam: String) {
        proto.descriptionText = valueParam
    }

    @objc
    public func setDate(_ valueParam: UInt64) {
        proto.date = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoLinkPreview {
        return BackupProtoLinkPreview(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoLinkPreview {
        return BackupProtoLinkPreview(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoLinkPreview(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoLinkPreview {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoLinkPreviewBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoLinkPreview? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoAttachmentPointerFlags

@objc
public enum BackupProtoAttachmentPointerFlags: Int32 {
    case voiceMessage = 0
    case borderless = 1
    case gif = 2
}

private func BackupProtoAttachmentPointerFlagsWrap(_ value: BackupProtos_AttachmentPointer.Flags) -> BackupProtoAttachmentPointerFlags {
    switch value {
    case .voiceMessage: return .voiceMessage
    case .borderless: return .borderless
    case .gif: return .gif
    }
}

private func BackupProtoAttachmentPointerFlagsUnwrap(_ value: BackupProtoAttachmentPointerFlags) -> BackupProtos_AttachmentPointer.Flags {
    switch value {
    case .voiceMessage: return .voiceMessage
    case .borderless: return .borderless
    case .gif: return .gif
    }
}

// MARK: - BackupProtoAttachmentPointer

@objc
public class BackupProtoAttachmentPointer: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_AttachmentPointer

    @objc
    public var cdnID: UInt64 {
        return proto.cdnID
    }
    @objc
    public var hasCdnID: Bool {
        return proto.hasCdnID
    }

    @objc
    public var cdnKey: String? {
        guard hasCdnKey else {
            return nil
        }
        return proto.cdnKey
    }
    @objc
    public var hasCdnKey: Bool {
        return proto.hasCdnKey
    }

    @objc
    public var contentType: String? {
        guard hasContentType else {
            return nil
        }
        return proto.contentType
    }
    @objc
    public var hasContentType: Bool {
        return proto.hasContentType
    }

    @objc
    public var key: Data? {
        guard hasKey else {
            return nil
        }
        return proto.key
    }
    @objc
    public var hasKey: Bool {
        return proto.hasKey
    }

    @objc
    public var size: UInt32 {
        return proto.size
    }
    @objc
    public var hasSize: Bool {
        return proto.hasSize
    }

    @objc
    public var digest: Data? {
        guard hasDigest else {
            return nil
        }
        return proto.digest
    }
    @objc
    public var hasDigest: Bool {
        return proto.hasDigest
    }

    @objc
    public var incrementalMac: Data? {
        guard hasIncrementalMac else {
            return nil
        }
        return proto.incrementalMac
    }
    @objc
    public var hasIncrementalMac: Bool {
        return proto.hasIncrementalMac
    }

    @objc
    public var incrementalMacChunkSize: Data? {
        guard hasIncrementalMacChunkSize else {
            return nil
        }
        return proto.incrementalMacChunkSize
    }
    @objc
    public var hasIncrementalMacChunkSize: Bool {
        return proto.hasIncrementalMacChunkSize
    }

    @objc
    public var fileName: String? {
        guard hasFileName else {
            return nil
        }
        return proto.fileName
    }
    @objc
    public var hasFileName: Bool {
        return proto.hasFileName
    }

    @objc
    public var flags: UInt32 {
        return proto.flags
    }
    @objc
    public var hasFlags: Bool {
        return proto.hasFlags
    }

    @objc
    public var width: UInt32 {
        return proto.width
    }
    @objc
    public var hasWidth: Bool {
        return proto.hasWidth
    }

    @objc
    public var height: UInt32 {
        return proto.height
    }
    @objc
    public var hasHeight: Bool {
        return proto.hasHeight
    }

    @objc
    public var caption: String? {
        guard hasCaption else {
            return nil
        }
        return proto.caption
    }
    @objc
    public var hasCaption: Bool {
        return proto.hasCaption
    }

    @objc
    public var blurHash: String? {
        guard hasBlurHash else {
            return nil
        }
        return proto.blurHash
    }
    @objc
    public var hasBlurHash: Bool {
        return proto.hasBlurHash
    }

    @objc
    public var uploadTimestamp: UInt64 {
        return proto.uploadTimestamp
    }
    @objc
    public var hasUploadTimestamp: Bool {
        return proto.hasUploadTimestamp
    }

    @objc
    public var cdnNumber: UInt32 {
        return proto.cdnNumber
    }
    @objc
    public var hasCdnNumber: Bool {
        return proto.hasCdnNumber
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_AttachmentPointer) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_AttachmentPointer(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_AttachmentPointer) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoAttachmentPointer {
    @objc
    public static func builder() -> BackupProtoAttachmentPointerBuilder {
        return BackupProtoAttachmentPointerBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoAttachmentPointerBuilder {
        let builder = BackupProtoAttachmentPointerBuilder()
        if hasCdnID {
            builder.setCdnID(cdnID)
        }
        if let _value = cdnKey {
            builder.setCdnKey(_value)
        }
        if let _value = contentType {
            builder.setContentType(_value)
        }
        if let _value = key {
            builder.setKey(_value)
        }
        if hasSize {
            builder.setSize(size)
        }
        if let _value = digest {
            builder.setDigest(_value)
        }
        if let _value = incrementalMac {
            builder.setIncrementalMac(_value)
        }
        if let _value = incrementalMacChunkSize {
            builder.setIncrementalMacChunkSize(_value)
        }
        if let _value = fileName {
            builder.setFileName(_value)
        }
        if hasFlags {
            builder.setFlags(flags)
        }
        if hasWidth {
            builder.setWidth(width)
        }
        if hasHeight {
            builder.setHeight(height)
        }
        if let _value = caption {
            builder.setCaption(_value)
        }
        if let _value = blurHash {
            builder.setBlurHash(_value)
        }
        if hasUploadTimestamp {
            builder.setUploadTimestamp(uploadTimestamp)
        }
        if hasCdnNumber {
            builder.setCdnNumber(cdnNumber)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoAttachmentPointerBuilder: NSObject {

    private var proto = BackupProtos_AttachmentPointer()

    @objc
    fileprivate override init() {}

    @objc
    public func setCdnID(_ valueParam: UInt64) {
        proto.cdnID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCdnKey(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.cdnKey = valueParam
    }

    public func setCdnKey(_ valueParam: String) {
        proto.cdnKey = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setContentType(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.contentType = valueParam
    }

    public func setContentType(_ valueParam: String) {
        proto.contentType = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.key = valueParam
    }

    public func setKey(_ valueParam: Data) {
        proto.key = valueParam
    }

    @objc
    public func setSize(_ valueParam: UInt32) {
        proto.size = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDigest(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.digest = valueParam
    }

    public func setDigest(_ valueParam: Data) {
        proto.digest = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setIncrementalMac(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.incrementalMac = valueParam
    }

    public func setIncrementalMac(_ valueParam: Data) {
        proto.incrementalMac = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setIncrementalMacChunkSize(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.incrementalMacChunkSize = valueParam
    }

    public func setIncrementalMacChunkSize(_ valueParam: Data) {
        proto.incrementalMacChunkSize = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setFileName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.fileName = valueParam
    }

    public func setFileName(_ valueParam: String) {
        proto.fileName = valueParam
    }

    @objc
    public func setFlags(_ valueParam: UInt32) {
        proto.flags = valueParam
    }

    @objc
    public func setWidth(_ valueParam: UInt32) {
        proto.width = valueParam
    }

    @objc
    public func setHeight(_ valueParam: UInt32) {
        proto.height = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCaption(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.caption = valueParam
    }

    public func setCaption(_ valueParam: String) {
        proto.caption = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBlurHash(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.blurHash = valueParam
    }

    public func setBlurHash(_ valueParam: String) {
        proto.blurHash = valueParam
    }

    @objc
    public func setUploadTimestamp(_ valueParam: UInt64) {
        proto.uploadTimestamp = valueParam
    }

    @objc
    public func setCdnNumber(_ valueParam: UInt32) {
        proto.cdnNumber = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoAttachmentPointer {
        return BackupProtoAttachmentPointer(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoAttachmentPointer {
        return BackupProtoAttachmentPointer(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoAttachmentPointer(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoAttachmentPointer {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoAttachmentPointerBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoAttachmentPointer? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoQuoteQuotedAttachment

@objc
public class BackupProtoQuoteQuotedAttachment: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Quote.QuotedAttachment

    @objc
    public let thumbnail: BackupProtoAttachmentPointer?

    @objc
    public var contentType: String? {
        guard hasContentType else {
            return nil
        }
        return proto.contentType
    }
    @objc
    public var hasContentType: Bool {
        return proto.hasContentType
    }

    @objc
    public var fileName: String? {
        guard hasFileName else {
            return nil
        }
        return proto.fileName
    }
    @objc
    public var hasFileName: Bool {
        return proto.hasFileName
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_Quote.QuotedAttachment,
                 thumbnail: BackupProtoAttachmentPointer?) {
        self.proto = proto
        self.thumbnail = thumbnail
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_Quote.QuotedAttachment(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Quote.QuotedAttachment) {
        var thumbnail: BackupProtoAttachmentPointer?
        if proto.hasThumbnail {
            thumbnail = BackupProtoAttachmentPointer(proto.thumbnail)
        }

        self.init(proto: proto,
                  thumbnail: thumbnail)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoQuoteQuotedAttachment {
    @objc
    public static func builder() -> BackupProtoQuoteQuotedAttachmentBuilder {
        return BackupProtoQuoteQuotedAttachmentBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoQuoteQuotedAttachmentBuilder {
        let builder = BackupProtoQuoteQuotedAttachmentBuilder()
        if let _value = contentType {
            builder.setContentType(_value)
        }
        if let _value = fileName {
            builder.setFileName(_value)
        }
        if let _value = thumbnail {
            builder.setThumbnail(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoQuoteQuotedAttachmentBuilder: NSObject {

    private var proto = BackupProtos_Quote.QuotedAttachment()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setContentType(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.contentType = valueParam
    }

    public func setContentType(_ valueParam: String) {
        proto.contentType = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setFileName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.fileName = valueParam
    }

    public func setFileName(_ valueParam: String) {
        proto.fileName = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setThumbnail(_ valueParam: BackupProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.thumbnail = valueParam.proto
    }

    public func setThumbnail(_ valueParam: BackupProtoAttachmentPointer) {
        proto.thumbnail = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoQuoteQuotedAttachment {
        return BackupProtoQuoteQuotedAttachment(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoQuoteQuotedAttachment {
        return BackupProtoQuoteQuotedAttachment(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoQuoteQuotedAttachment(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoQuoteQuotedAttachment {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoQuoteQuotedAttachmentBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoQuoteQuotedAttachment? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoQuoteType

@objc
public enum BackupProtoQuoteType: Int32 {
    case normal = 0
    case giftbadge = 1
}

private func BackupProtoQuoteTypeWrap(_ value: BackupProtos_Quote.TypeEnum) -> BackupProtoQuoteType {
    switch value {
    case .normal: return .normal
    case .giftbadge: return .giftbadge
    }
}

private func BackupProtoQuoteTypeUnwrap(_ value: BackupProtoQuoteType) -> BackupProtos_Quote.TypeEnum {
    switch value {
    case .normal: return .normal
    case .giftbadge: return .giftbadge
    }
}

// MARK: - BackupProtoQuote

@objc
public class BackupProtoQuote: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Quote

    @objc
    public let attachments: [BackupProtoQuoteQuotedAttachment]

    @objc
    public let bodyRanges: [BackupProtoBodyRange]

    @objc
    public var id: UInt64 {
        return proto.id
    }
    @objc
    public var hasID: Bool {
        return proto.hasID
    }

    @objc
    public var authorID: UInt64 {
        return proto.authorID
    }
    @objc
    public var hasAuthorID: Bool {
        return proto.hasAuthorID
    }

    @objc
    public var text: String? {
        guard hasText else {
            return nil
        }
        return proto.text
    }
    @objc
    public var hasText: Bool {
        return proto.hasText
    }

    public var type: BackupProtoQuoteType? {
        guard hasType else {
            return nil
        }
        return BackupProtoQuoteTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: BackupProtoQuoteType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: Quote.type.")
        }
        return BackupProtoQuoteTypeWrap(proto.type)
    }
    @objc
    public var hasType: Bool {
        return proto.hasType
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_Quote,
                 attachments: [BackupProtoQuoteQuotedAttachment],
                 bodyRanges: [BackupProtoBodyRange]) {
        self.proto = proto
        self.attachments = attachments
        self.bodyRanges = bodyRanges
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_Quote(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Quote) {
        var attachments: [BackupProtoQuoteQuotedAttachment] = []
        attachments = proto.attachments.map { BackupProtoQuoteQuotedAttachment($0) }

        var bodyRanges: [BackupProtoBodyRange] = []
        bodyRanges = proto.bodyRanges.map { BackupProtoBodyRange($0) }

        self.init(proto: proto,
                  attachments: attachments,
                  bodyRanges: bodyRanges)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoQuote {
    @objc
    public static func builder() -> BackupProtoQuoteBuilder {
        return BackupProtoQuoteBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoQuoteBuilder {
        let builder = BackupProtoQuoteBuilder()
        if hasID {
            builder.setId(id)
        }
        if hasAuthorID {
            builder.setAuthorID(authorID)
        }
        if let _value = text {
            builder.setText(_value)
        }
        builder.setAttachments(attachments)
        builder.setBodyRanges(bodyRanges)
        if let _value = type {
            builder.setType(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoQuoteBuilder: NSObject {

    private var proto = BackupProtos_Quote()

    @objc
    fileprivate override init() {}

    @objc
    public func setId(_ valueParam: UInt64) {
        proto.id = valueParam
    }

    @objc
    public func setAuthorID(_ valueParam: UInt64) {
        proto.authorID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setText(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.text = valueParam
    }

    public func setText(_ valueParam: String) {
        proto.text = valueParam
    }

    @objc
    public func addAttachments(_ valueParam: BackupProtoQuoteQuotedAttachment) {
        proto.attachments.append(valueParam.proto)
    }

    @objc
    public func setAttachments(_ wrappedItems: [BackupProtoQuoteQuotedAttachment]) {
        proto.attachments = wrappedItems.map { $0.proto }
    }

    @objc
    public func addBodyRanges(_ valueParam: BackupProtoBodyRange) {
        proto.bodyRanges.append(valueParam.proto)
    }

    @objc
    public func setBodyRanges(_ wrappedItems: [BackupProtoBodyRange]) {
        proto.bodyRanges = wrappedItems.map { $0.proto }
    }

    @objc
    public func setType(_ valueParam: BackupProtoQuoteType) {
        proto.type = BackupProtoQuoteTypeUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoQuote {
        return BackupProtoQuote(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoQuote {
        return BackupProtoQuote(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoQuote(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoQuote {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoQuoteBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoQuote? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoBodyRangeStyle

@objc
public enum BackupProtoBodyRangeStyle: Int32 {
    case none = 0
    case bold = 1
    case italic = 2
    case spoiler = 3
    case strikethrough = 4
    case monospace = 5
}

private func BackupProtoBodyRangeStyleWrap(_ value: BackupProtos_BodyRange.Style) -> BackupProtoBodyRangeStyle {
    switch value {
    case .none: return .none
    case .bold: return .bold
    case .italic: return .italic
    case .spoiler: return .spoiler
    case .strikethrough: return .strikethrough
    case .monospace: return .monospace
    }
}

private func BackupProtoBodyRangeStyleUnwrap(_ value: BackupProtoBodyRangeStyle) -> BackupProtos_BodyRange.Style {
    switch value {
    case .none: return .none
    case .bold: return .bold
    case .italic: return .italic
    case .spoiler: return .spoiler
    case .strikethrough: return .strikethrough
    case .monospace: return .monospace
    }
}

// MARK: - BackupProtoBodyRange

@objc
public class BackupProtoBodyRange: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_BodyRange

    @objc
    public var start: UInt32 {
        return proto.start
    }
    @objc
    public var hasStart: Bool {
        return proto.hasStart
    }

    @objc
    public var length: UInt32 {
        return proto.length
    }
    @objc
    public var hasLength: Bool {
        return proto.hasLength
    }

    @objc
    public var mentionAci: String? {
        guard hasMentionAci else {
            return nil
        }
        return proto.mentionAci
    }
    @objc
    public var hasMentionAci: Bool {
        return proto.hasMentionAci
    }

    public var style: BackupProtoBodyRangeStyle? {
        guard hasStyle else {
            return nil
        }
        return BackupProtoBodyRangeStyleWrap(proto.style)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedStyle: BackupProtoBodyRangeStyle {
        if !hasStyle {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: BodyRange.style.")
        }
        return BackupProtoBodyRangeStyleWrap(proto.style)
    }
    @objc
    public var hasStyle: Bool {
        return proto.hasStyle
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_BodyRange) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_BodyRange(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_BodyRange) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoBodyRange {
    @objc
    public static func builder() -> BackupProtoBodyRangeBuilder {
        return BackupProtoBodyRangeBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoBodyRangeBuilder {
        let builder = BackupProtoBodyRangeBuilder()
        if hasStart {
            builder.setStart(start)
        }
        if hasLength {
            builder.setLength(length)
        }
        if let _value = mentionAci {
            builder.setMentionAci(_value)
        }
        if let _value = style {
            builder.setStyle(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoBodyRangeBuilder: NSObject {

    private var proto = BackupProtos_BodyRange()

    @objc
    fileprivate override init() {}

    @objc
    public func setStart(_ valueParam: UInt32) {
        proto.start = valueParam
    }

    @objc
    public func setLength(_ valueParam: UInt32) {
        proto.length = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMentionAci(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.mentionAci = valueParam
    }

    public func setMentionAci(_ valueParam: String) {
        proto.mentionAci = valueParam
    }

    @objc
    public func setStyle(_ valueParam: BackupProtoBodyRangeStyle) {
        proto.style = BackupProtoBodyRangeStyleUnwrap(valueParam)
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoBodyRange {
        return BackupProtoBodyRange(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoBodyRange {
        return BackupProtoBodyRange(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoBodyRange(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoBodyRange {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoBodyRangeBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoBodyRange? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoReaction

@objc
public class BackupProtoReaction: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Reaction

    @objc
    public let emoji: String

    @objc
    public let authorID: UInt64

    @objc
    public let sentTimestamp: UInt64

    @objc
    public let receivedTimestamp: UInt64

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_Reaction,
                 emoji: String,
                 authorID: UInt64,
                 sentTimestamp: UInt64,
                 receivedTimestamp: UInt64) {
        self.proto = proto
        self.emoji = emoji
        self.authorID = authorID
        self.sentTimestamp = sentTimestamp
        self.receivedTimestamp = receivedTimestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_Reaction(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Reaction) throws {
        guard proto.hasEmoji else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: emoji")
        }
        let emoji = proto.emoji

        guard proto.hasAuthorID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: authorID")
        }
        let authorID = proto.authorID

        guard proto.hasSentTimestamp else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: sentTimestamp")
        }
        let sentTimestamp = proto.sentTimestamp

        guard proto.hasReceivedTimestamp else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: receivedTimestamp")
        }
        let receivedTimestamp = proto.receivedTimestamp

        self.init(proto: proto,
                  emoji: emoji,
                  authorID: authorID,
                  sentTimestamp: sentTimestamp,
                  receivedTimestamp: receivedTimestamp)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoReaction {
    @objc
    public static func builder(emoji: String, authorID: UInt64, sentTimestamp: UInt64, receivedTimestamp: UInt64) -> BackupProtoReactionBuilder {
        return BackupProtoReactionBuilder(emoji: emoji, authorID: authorID, sentTimestamp: sentTimestamp, receivedTimestamp: receivedTimestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoReactionBuilder {
        let builder = BackupProtoReactionBuilder(emoji: emoji, authorID: authorID, sentTimestamp: sentTimestamp, receivedTimestamp: receivedTimestamp)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoReactionBuilder: NSObject {

    private var proto = BackupProtos_Reaction()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(emoji: String, authorID: UInt64, sentTimestamp: UInt64, receivedTimestamp: UInt64) {
        super.init()

        setEmoji(emoji)
        setAuthorID(authorID)
        setSentTimestamp(sentTimestamp)
        setReceivedTimestamp(receivedTimestamp)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setEmoji(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.emoji = valueParam
    }

    public func setEmoji(_ valueParam: String) {
        proto.emoji = valueParam
    }

    @objc
    public func setAuthorID(_ valueParam: UInt64) {
        proto.authorID = valueParam
    }

    @objc
    public func setSentTimestamp(_ valueParam: UInt64) {
        proto.sentTimestamp = valueParam
    }

    @objc
    public func setReceivedTimestamp(_ valueParam: UInt64) {
        proto.receivedTimestamp = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoReaction {
        return try BackupProtoReaction(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoReaction(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoReaction {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoReactionBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoReaction? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoUpdateMessage

@objc
public class BackupProtoUpdateMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_UpdateMessage

    @objc
    public let simpleUpdate: BackupProtoSimpleUpdate?

    @objc
    public let groupDescription: BackupProtoGroupDescriptionUpdate?

    @objc
    public let expirationTimerChange: BackupProtoExpirationTimerChange?

    @objc
    public let profileChange: BackupProtoProfileChange?

    @objc
    public let threadMerge: BackupProtoThreadMergeEvent?

    @objc
    public let sessionSwitchover: BackupProtoSessionSwitchoverEvent?

    @objc
    public let callingMessage: BackupProtoCallingMessage?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_UpdateMessage,
                 simpleUpdate: BackupProtoSimpleUpdate?,
                 groupDescription: BackupProtoGroupDescriptionUpdate?,
                 expirationTimerChange: BackupProtoExpirationTimerChange?,
                 profileChange: BackupProtoProfileChange?,
                 threadMerge: BackupProtoThreadMergeEvent?,
                 sessionSwitchover: BackupProtoSessionSwitchoverEvent?,
                 callingMessage: BackupProtoCallingMessage?) {
        self.proto = proto
        self.simpleUpdate = simpleUpdate
        self.groupDescription = groupDescription
        self.expirationTimerChange = expirationTimerChange
        self.profileChange = profileChange
        self.threadMerge = threadMerge
        self.sessionSwitchover = sessionSwitchover
        self.callingMessage = callingMessage
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_UpdateMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_UpdateMessage) throws {
        var simpleUpdate: BackupProtoSimpleUpdate?
        if proto.hasSimpleUpdate {
            simpleUpdate = BackupProtoSimpleUpdate(proto.simpleUpdate)
        }

        var groupDescription: BackupProtoGroupDescriptionUpdate?
        if proto.hasGroupDescription {
            groupDescription = try BackupProtoGroupDescriptionUpdate(proto.groupDescription)
        }

        var expirationTimerChange: BackupProtoExpirationTimerChange?
        if proto.hasExpirationTimerChange {
            expirationTimerChange = try BackupProtoExpirationTimerChange(proto.expirationTimerChange)
        }

        var profileChange: BackupProtoProfileChange?
        if proto.hasProfileChange {
            profileChange = try BackupProtoProfileChange(proto.profileChange)
        }

        var threadMerge: BackupProtoThreadMergeEvent?
        if proto.hasThreadMerge {
            threadMerge = try BackupProtoThreadMergeEvent(proto.threadMerge)
        }

        var sessionSwitchover: BackupProtoSessionSwitchoverEvent?
        if proto.hasSessionSwitchover {
            sessionSwitchover = try BackupProtoSessionSwitchoverEvent(proto.sessionSwitchover)
        }

        var callingMessage: BackupProtoCallingMessage?
        if proto.hasCallingMessage {
            callingMessage = try BackupProtoCallingMessage(proto.callingMessage)
        }

        self.init(proto: proto,
                  simpleUpdate: simpleUpdate,
                  groupDescription: groupDescription,
                  expirationTimerChange: expirationTimerChange,
                  profileChange: profileChange,
                  threadMerge: threadMerge,
                  sessionSwitchover: sessionSwitchover,
                  callingMessage: callingMessage)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoUpdateMessage {
    @objc
    public static func builder() -> BackupProtoUpdateMessageBuilder {
        return BackupProtoUpdateMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoUpdateMessageBuilder {
        let builder = BackupProtoUpdateMessageBuilder()
        if let _value = simpleUpdate {
            builder.setSimpleUpdate(_value)
        }
        if let _value = groupDescription {
            builder.setGroupDescription(_value)
        }
        if let _value = expirationTimerChange {
            builder.setExpirationTimerChange(_value)
        }
        if let _value = profileChange {
            builder.setProfileChange(_value)
        }
        if let _value = threadMerge {
            builder.setThreadMerge(_value)
        }
        if let _value = sessionSwitchover {
            builder.setSessionSwitchover(_value)
        }
        if let _value = callingMessage {
            builder.setCallingMessage(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoUpdateMessageBuilder: NSObject {

    private var proto = BackupProtos_UpdateMessage()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSimpleUpdate(_ valueParam: BackupProtoSimpleUpdate?) {
        guard let valueParam = valueParam else { return }
        proto.simpleUpdate = valueParam.proto
    }

    public func setSimpleUpdate(_ valueParam: BackupProtoSimpleUpdate) {
        proto.simpleUpdate = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGroupDescription(_ valueParam: BackupProtoGroupDescriptionUpdate?) {
        guard let valueParam = valueParam else { return }
        proto.groupDescription = valueParam.proto
    }

    public func setGroupDescription(_ valueParam: BackupProtoGroupDescriptionUpdate) {
        proto.groupDescription = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setExpirationTimerChange(_ valueParam: BackupProtoExpirationTimerChange?) {
        guard let valueParam = valueParam else { return }
        proto.expirationTimerChange = valueParam.proto
    }

    public func setExpirationTimerChange(_ valueParam: BackupProtoExpirationTimerChange) {
        proto.expirationTimerChange = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setProfileChange(_ valueParam: BackupProtoProfileChange?) {
        guard let valueParam = valueParam else { return }
        proto.profileChange = valueParam.proto
    }

    public func setProfileChange(_ valueParam: BackupProtoProfileChange) {
        proto.profileChange = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setThreadMerge(_ valueParam: BackupProtoThreadMergeEvent?) {
        guard let valueParam = valueParam else { return }
        proto.threadMerge = valueParam.proto
    }

    public func setThreadMerge(_ valueParam: BackupProtoThreadMergeEvent) {
        proto.threadMerge = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setSessionSwitchover(_ valueParam: BackupProtoSessionSwitchoverEvent?) {
        guard let valueParam = valueParam else { return }
        proto.sessionSwitchover = valueParam.proto
    }

    public func setSessionSwitchover(_ valueParam: BackupProtoSessionSwitchoverEvent) {
        proto.sessionSwitchover = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCallingMessage(_ valueParam: BackupProtoCallingMessage?) {
        guard let valueParam = valueParam else { return }
        proto.callingMessage = valueParam.proto
    }

    public func setCallingMessage(_ valueParam: BackupProtoCallingMessage) {
        proto.callingMessage = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoUpdateMessage {
        return try BackupProtoUpdateMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoUpdateMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoUpdateMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoUpdateMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoUpdateMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoCallingMessage

@objc
public class BackupProtoCallingMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_CallingMessage

    @objc
    public let callMessage: BackupProtoCallMessage?

    @objc
    public let groupCall: BackupProtoGroupCallMessage?

    @objc
    public var callID: UInt64 {
        return proto.callID
    }
    @objc
    public var hasCallID: Bool {
        return proto.hasCallID
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_CallingMessage,
                 callMessage: BackupProtoCallMessage?,
                 groupCall: BackupProtoGroupCallMessage?) {
        self.proto = proto
        self.callMessage = callMessage
        self.groupCall = groupCall
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_CallingMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_CallingMessage) throws {
        var callMessage: BackupProtoCallMessage?
        if proto.hasCallMessage {
            callMessage = BackupProtoCallMessage(proto.callMessage)
        }

        var groupCall: BackupProtoGroupCallMessage?
        if proto.hasGroupCall {
            groupCall = try BackupProtoGroupCallMessage(proto.groupCall)
        }

        self.init(proto: proto,
                  callMessage: callMessage,
                  groupCall: groupCall)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoCallingMessage {
    @objc
    public static func builder() -> BackupProtoCallingMessageBuilder {
        return BackupProtoCallingMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoCallingMessageBuilder {
        let builder = BackupProtoCallingMessageBuilder()
        if hasCallID {
            builder.setCallID(callID)
        }
        if let _value = callMessage {
            builder.setCallMessage(_value)
        }
        if let _value = groupCall {
            builder.setGroupCall(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoCallingMessageBuilder: NSObject {

    private var proto = BackupProtos_CallingMessage()

    @objc
    fileprivate override init() {}

    @objc
    public func setCallID(_ valueParam: UInt64) {
        proto.callID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setCallMessage(_ valueParam: BackupProtoCallMessage?) {
        guard let valueParam = valueParam else { return }
        proto.callMessage = valueParam.proto
    }

    public func setCallMessage(_ valueParam: BackupProtoCallMessage) {
        proto.callMessage = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setGroupCall(_ valueParam: BackupProtoGroupCallMessage?) {
        guard let valueParam = valueParam else { return }
        proto.groupCall = valueParam.proto
    }

    public func setGroupCall(_ valueParam: BackupProtoGroupCallMessage) {
        proto.groupCall = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoCallingMessage {
        return try BackupProtoCallingMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoCallingMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoCallingMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoCallingMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoCallingMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoCallMessageType

@objc
public enum BackupProtoCallMessageType: Int32 {
    case incomingAudioCall = 0
    case incomingVideoCall = 1
    case outgoingAudioCall = 2
    case outgoingVideoCall = 3
    case missedAudioCall = 4
    case missedVideoCall = 5
}

private func BackupProtoCallMessageTypeWrap(_ value: BackupProtos_CallMessage.TypeEnum) -> BackupProtoCallMessageType {
    switch value {
    case .incomingAudioCall: return .incomingAudioCall
    case .incomingVideoCall: return .incomingVideoCall
    case .outgoingAudioCall: return .outgoingAudioCall
    case .outgoingVideoCall: return .outgoingVideoCall
    case .missedAudioCall: return .missedAudioCall
    case .missedVideoCall: return .missedVideoCall
    }
}

private func BackupProtoCallMessageTypeUnwrap(_ value: BackupProtoCallMessageType) -> BackupProtos_CallMessage.TypeEnum {
    switch value {
    case .incomingAudioCall: return .incomingAudioCall
    case .incomingVideoCall: return .incomingVideoCall
    case .outgoingAudioCall: return .outgoingAudioCall
    case .outgoingVideoCall: return .outgoingVideoCall
    case .missedAudioCall: return .missedAudioCall
    case .missedVideoCall: return .missedVideoCall
    }
}

// MARK: - BackupProtoCallMessage

@objc
public class BackupProtoCallMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_CallMessage

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_CallMessage) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_CallMessage(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_CallMessage) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoCallMessage {
    @objc
    public static func builder() -> BackupProtoCallMessageBuilder {
        return BackupProtoCallMessageBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoCallMessageBuilder {
        let builder = BackupProtoCallMessageBuilder()
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoCallMessageBuilder: NSObject {

    private var proto = BackupProtos_CallMessage()

    @objc
    fileprivate override init() {}

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoCallMessage {
        return BackupProtoCallMessage(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoCallMessage {
        return BackupProtoCallMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoCallMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoCallMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoCallMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoCallMessage? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoGroupCallMessage

@objc
public class BackupProtoGroupCallMessage: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_GroupCallMessage

    @objc
    public let startedCallUuid: Data

    @objc
    public let startedCallTimestamp: UInt64

    @objc
    public let isCallFull: Bool

    @objc
    public var inCallUuids: [Data] {
        return proto.inCallUuids
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_GroupCallMessage,
                 startedCallUuid: Data,
                 startedCallTimestamp: UInt64,
                 isCallFull: Bool) {
        self.proto = proto
        self.startedCallUuid = startedCallUuid
        self.startedCallTimestamp = startedCallTimestamp
        self.isCallFull = isCallFull
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_GroupCallMessage(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_GroupCallMessage) throws {
        guard proto.hasStartedCallUuid else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: startedCallUuid")
        }
        let startedCallUuid = proto.startedCallUuid

        guard proto.hasStartedCallTimestamp else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: startedCallTimestamp")
        }
        let startedCallTimestamp = proto.startedCallTimestamp

        guard proto.hasIsCallFull else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: isCallFull")
        }
        let isCallFull = proto.isCallFull

        self.init(proto: proto,
                  startedCallUuid: startedCallUuid,
                  startedCallTimestamp: startedCallTimestamp,
                  isCallFull: isCallFull)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoGroupCallMessage {
    @objc
    public static func builder(startedCallUuid: Data, startedCallTimestamp: UInt64, isCallFull: Bool) -> BackupProtoGroupCallMessageBuilder {
        return BackupProtoGroupCallMessageBuilder(startedCallUuid: startedCallUuid, startedCallTimestamp: startedCallTimestamp, isCallFull: isCallFull)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoGroupCallMessageBuilder {
        let builder = BackupProtoGroupCallMessageBuilder(startedCallUuid: startedCallUuid, startedCallTimestamp: startedCallTimestamp, isCallFull: isCallFull)
        builder.setInCallUuids(inCallUuids)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoGroupCallMessageBuilder: NSObject {

    private var proto = BackupProtos_GroupCallMessage()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(startedCallUuid: Data, startedCallTimestamp: UInt64, isCallFull: Bool) {
        super.init()

        setStartedCallUuid(startedCallUuid)
        setStartedCallTimestamp(startedCallTimestamp)
        setIsCallFull(isCallFull)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setStartedCallUuid(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.startedCallUuid = valueParam
    }

    public func setStartedCallUuid(_ valueParam: Data) {
        proto.startedCallUuid = valueParam
    }

    @objc
    public func setStartedCallTimestamp(_ valueParam: UInt64) {
        proto.startedCallTimestamp = valueParam
    }

    @objc
    public func addInCallUuids(_ valueParam: Data) {
        proto.inCallUuids.append(valueParam)
    }

    @objc
    public func setInCallUuids(_ wrappedItems: [Data]) {
        proto.inCallUuids = wrappedItems
    }

    @objc
    public func setIsCallFull(_ valueParam: Bool) {
        proto.isCallFull = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoGroupCallMessage {
        return try BackupProtoGroupCallMessage(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoGroupCallMessage(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoGroupCallMessage {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoGroupCallMessageBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoGroupCallMessage? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoSimpleUpdateType

@objc
public enum BackupProtoSimpleUpdateType: Int32 {
    case joinedSignal = 0
    case identityUpdate = 1
    case identityVerified = 2
    case identityDefault = 3
    case changeNumber = 4
    case boostRequest = 5
    case endSession = 6
    case chatSessionRefresh = 7
    case badDecrypt = 8
    case paymentsActivated = 9
    case paymentActivationRequest = 10
}

private func BackupProtoSimpleUpdateTypeWrap(_ value: BackupProtos_SimpleUpdate.TypeEnum) -> BackupProtoSimpleUpdateType {
    switch value {
    case .joinedSignal: return .joinedSignal
    case .identityUpdate: return .identityUpdate
    case .identityVerified: return .identityVerified
    case .identityDefault: return .identityDefault
    case .changeNumber: return .changeNumber
    case .boostRequest: return .boostRequest
    case .endSession: return .endSession
    case .chatSessionRefresh: return .chatSessionRefresh
    case .badDecrypt: return .badDecrypt
    case .paymentsActivated: return .paymentsActivated
    case .paymentActivationRequest: return .paymentActivationRequest
    }
}

private func BackupProtoSimpleUpdateTypeUnwrap(_ value: BackupProtoSimpleUpdateType) -> BackupProtos_SimpleUpdate.TypeEnum {
    switch value {
    case .joinedSignal: return .joinedSignal
    case .identityUpdate: return .identityUpdate
    case .identityVerified: return .identityVerified
    case .identityDefault: return .identityDefault
    case .changeNumber: return .changeNumber
    case .boostRequest: return .boostRequest
    case .endSession: return .endSession
    case .chatSessionRefresh: return .chatSessionRefresh
    case .badDecrypt: return .badDecrypt
    case .paymentsActivated: return .paymentsActivated
    case .paymentActivationRequest: return .paymentActivationRequest
    }
}

// MARK: - BackupProtoSimpleUpdate

@objc
public class BackupProtoSimpleUpdate: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_SimpleUpdate

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_SimpleUpdate) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_SimpleUpdate(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_SimpleUpdate) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoSimpleUpdate {
    @objc
    public static func builder() -> BackupProtoSimpleUpdateBuilder {
        return BackupProtoSimpleUpdateBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoSimpleUpdateBuilder {
        let builder = BackupProtoSimpleUpdateBuilder()
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoSimpleUpdateBuilder: NSObject {

    private var proto = BackupProtos_SimpleUpdate()

    @objc
    fileprivate override init() {}

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoSimpleUpdate {
        return BackupProtoSimpleUpdate(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoSimpleUpdate {
        return BackupProtoSimpleUpdate(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoSimpleUpdate(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoSimpleUpdate {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoSimpleUpdateBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoSimpleUpdate? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoGroupDescriptionUpdate

@objc
public class BackupProtoGroupDescriptionUpdate: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_GroupDescriptionUpdate

    @objc
    public let body: String

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_GroupDescriptionUpdate,
                 body: String) {
        self.proto = proto
        self.body = body
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_GroupDescriptionUpdate(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_GroupDescriptionUpdate) throws {
        guard proto.hasBody else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: body")
        }
        let body = proto.body

        self.init(proto: proto,
                  body: body)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoGroupDescriptionUpdate {
    @objc
    public static func builder(body: String) -> BackupProtoGroupDescriptionUpdateBuilder {
        return BackupProtoGroupDescriptionUpdateBuilder(body: body)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoGroupDescriptionUpdateBuilder {
        let builder = BackupProtoGroupDescriptionUpdateBuilder(body: body)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoGroupDescriptionUpdateBuilder: NSObject {

    private var proto = BackupProtos_GroupDescriptionUpdate()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(body: String) {
        super.init()

        setBody(body)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBody(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.body = valueParam
    }

    public func setBody(_ valueParam: String) {
        proto.body = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoGroupDescriptionUpdate {
        return try BackupProtoGroupDescriptionUpdate(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoGroupDescriptionUpdate(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoGroupDescriptionUpdate {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoGroupDescriptionUpdateBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoGroupDescriptionUpdate? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoExpirationTimerChange

@objc
public class BackupProtoExpirationTimerChange: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ExpirationTimerChange

    @objc
    public let expiresIn: UInt32

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ExpirationTimerChange,
                 expiresIn: UInt32) {
        self.proto = proto
        self.expiresIn = expiresIn
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ExpirationTimerChange(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ExpirationTimerChange) throws {
        guard proto.hasExpiresIn else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: expiresIn")
        }
        let expiresIn = proto.expiresIn

        self.init(proto: proto,
                  expiresIn: expiresIn)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoExpirationTimerChange {
    @objc
    public static func builder(expiresIn: UInt32) -> BackupProtoExpirationTimerChangeBuilder {
        return BackupProtoExpirationTimerChangeBuilder(expiresIn: expiresIn)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoExpirationTimerChangeBuilder {
        let builder = BackupProtoExpirationTimerChangeBuilder(expiresIn: expiresIn)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoExpirationTimerChangeBuilder: NSObject {

    private var proto = BackupProtos_ExpirationTimerChange()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(expiresIn: UInt32) {
        super.init()

        setExpiresIn(expiresIn)
    }

    @objc
    public func setExpiresIn(_ valueParam: UInt32) {
        proto.expiresIn = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoExpirationTimerChange {
        return try BackupProtoExpirationTimerChange(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoExpirationTimerChange(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoExpirationTimerChange {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoExpirationTimerChangeBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoExpirationTimerChange? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoProfileChange

@objc
public class BackupProtoProfileChange: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ProfileChange

    @objc
    public let previousName: String

    @objc
    public let newName: String

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ProfileChange,
                 previousName: String,
                 newName: String) {
        self.proto = proto
        self.previousName = previousName
        self.newName = newName
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ProfileChange(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ProfileChange) throws {
        guard proto.hasPreviousName else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: previousName")
        }
        let previousName = proto.previousName

        guard proto.hasNewName else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: newName")
        }
        let newName = proto.newName

        self.init(proto: proto,
                  previousName: previousName,
                  newName: newName)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoProfileChange {
    @objc
    public static func builder(previousName: String, newName: String) -> BackupProtoProfileChangeBuilder {
        return BackupProtoProfileChangeBuilder(previousName: previousName, newName: newName)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoProfileChangeBuilder {
        let builder = BackupProtoProfileChangeBuilder(previousName: previousName, newName: newName)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoProfileChangeBuilder: NSObject {

    private var proto = BackupProtos_ProfileChange()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(previousName: String, newName: String) {
        super.init()

        setPreviousName(previousName)
        setNewName(newName)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPreviousName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.previousName = valueParam
    }

    public func setPreviousName(_ valueParam: String) {
        proto.previousName = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setNewName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.newName = valueParam
    }

    public func setNewName(_ valueParam: String) {
        proto.newName = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoProfileChange {
        return try BackupProtoProfileChange(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoProfileChange(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoProfileChange {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoProfileChangeBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoProfileChange? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoThreadMergeEvent

@objc
public class BackupProtoThreadMergeEvent: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ThreadMergeEvent

    @objc
    public let previousE164: UInt64

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ThreadMergeEvent,
                 previousE164: UInt64) {
        self.proto = proto
        self.previousE164 = previousE164
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ThreadMergeEvent(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ThreadMergeEvent) throws {
        guard proto.hasPreviousE164 else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: previousE164")
        }
        let previousE164 = proto.previousE164

        self.init(proto: proto,
                  previousE164: previousE164)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoThreadMergeEvent {
    @objc
    public static func builder(previousE164: UInt64) -> BackupProtoThreadMergeEventBuilder {
        return BackupProtoThreadMergeEventBuilder(previousE164: previousE164)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoThreadMergeEventBuilder {
        let builder = BackupProtoThreadMergeEventBuilder(previousE164: previousE164)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoThreadMergeEventBuilder: NSObject {

    private var proto = BackupProtos_ThreadMergeEvent()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(previousE164: UInt64) {
        super.init()

        setPreviousE164(previousE164)
    }

    @objc
    public func setPreviousE164(_ valueParam: UInt64) {
        proto.previousE164 = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoThreadMergeEvent {
        return try BackupProtoThreadMergeEvent(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoThreadMergeEvent(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoThreadMergeEvent {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoThreadMergeEventBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoThreadMergeEvent? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoSessionSwitchoverEvent

@objc
public class BackupProtoSessionSwitchoverEvent: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_SessionSwitchoverEvent

    @objc
    public let e164: UInt64

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_SessionSwitchoverEvent,
                 e164: UInt64) {
        self.proto = proto
        self.e164 = e164
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_SessionSwitchoverEvent(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_SessionSwitchoverEvent) throws {
        guard proto.hasE164 else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: e164")
        }
        let e164 = proto.e164

        self.init(proto: proto,
                  e164: e164)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoSessionSwitchoverEvent {
    @objc
    public static func builder(e164: UInt64) -> BackupProtoSessionSwitchoverEventBuilder {
        return BackupProtoSessionSwitchoverEventBuilder(e164: e164)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoSessionSwitchoverEventBuilder {
        let builder = BackupProtoSessionSwitchoverEventBuilder(e164: e164)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoSessionSwitchoverEventBuilder: NSObject {

    private var proto = BackupProtos_SessionSwitchoverEvent()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(e164: UInt64) {
        super.init()

        setE164(e164)
    }

    @objc
    public func setE164(_ valueParam: UInt64) {
        proto.e164 = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoSessionSwitchoverEvent {
        return try BackupProtoSessionSwitchoverEvent(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoSessionSwitchoverEvent(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoSessionSwitchoverEvent {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoSessionSwitchoverEventBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoSessionSwitchoverEvent? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoStickerPack

@objc
public class BackupProtoStickerPack: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_StickerPack

    @objc
    public let id: Data

    @objc
    public let key: Data

    @objc
    public let title: String

    @objc
    public let author: String

    @objc
    public let stickers: [BackupProtoStickerPackSticker]

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_StickerPack,
                 id: Data,
                 key: Data,
                 title: String,
                 author: String,
                 stickers: [BackupProtoStickerPackSticker]) {
        self.proto = proto
        self.id = id
        self.key = key
        self.title = title
        self.author = author
        self.stickers = stickers
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_StickerPack(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_StickerPack) throws {
        guard proto.hasID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: id")
        }
        let id = proto.id

        guard proto.hasKey else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: key")
        }
        let key = proto.key

        guard proto.hasTitle else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: title")
        }
        let title = proto.title

        guard proto.hasAuthor else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: author")
        }
        let author = proto.author

        var stickers: [BackupProtoStickerPackSticker] = []
        stickers = try proto.stickers.map { try BackupProtoStickerPackSticker($0) }

        self.init(proto: proto,
                  id: id,
                  key: key,
                  title: title,
                  author: author,
                  stickers: stickers)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoStickerPack {
    @objc
    public static func builder(id: Data, key: Data, title: String, author: String) -> BackupProtoStickerPackBuilder {
        return BackupProtoStickerPackBuilder(id: id, key: key, title: title, author: author)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoStickerPackBuilder {
        let builder = BackupProtoStickerPackBuilder(id: id, key: key, title: title, author: author)
        builder.setStickers(stickers)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoStickerPackBuilder: NSObject {

    private var proto = BackupProtos_StickerPack()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(id: Data, key: Data, title: String, author: String) {
        super.init()

        setId(id)
        setKey(key)
        setTitle(title)
        setAuthor(author)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setId(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.id = valueParam
    }

    public func setId(_ valueParam: Data) {
        proto.id = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setKey(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.key = valueParam
    }

    public func setKey(_ valueParam: Data) {
        proto.key = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setTitle(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.title = valueParam
    }

    public func setTitle(_ valueParam: String) {
        proto.title = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAuthor(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.author = valueParam
    }

    public func setAuthor(_ valueParam: String) {
        proto.author = valueParam
    }

    @objc
    public func addStickers(_ valueParam: BackupProtoStickerPackSticker) {
        proto.stickers.append(valueParam.proto)
    }

    @objc
    public func setStickers(_ wrappedItems: [BackupProtoStickerPackSticker]) {
        proto.stickers = wrappedItems.map { $0.proto }
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoStickerPack {
        return try BackupProtoStickerPack(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoStickerPack(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoStickerPack {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoStickerPackBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoStickerPack? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoStickerPackSticker

@objc
public class BackupProtoStickerPackSticker: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_StickerPackSticker

    @objc
    public let data: BackupProtoAttachmentPointer

    @objc
    public let emoji: String

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_StickerPackSticker,
                 data: BackupProtoAttachmentPointer,
                 emoji: String) {
        self.proto = proto
        self.data = data
        self.emoji = emoji
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_StickerPackSticker(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_StickerPackSticker) throws {
        guard proto.hasData else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: data")
        }
        let data = BackupProtoAttachmentPointer(proto.data)

        guard proto.hasEmoji else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: emoji")
        }
        let emoji = proto.emoji

        self.init(proto: proto,
                  data: data,
                  emoji: emoji)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension BackupProtoStickerPackSticker {
    @objc
    public static func builder(data: BackupProtoAttachmentPointer, emoji: String) -> BackupProtoStickerPackStickerBuilder {
        return BackupProtoStickerPackStickerBuilder(data: data, emoji: emoji)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoStickerPackStickerBuilder {
        let builder = BackupProtoStickerPackStickerBuilder(data: data, emoji: emoji)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoStickerPackStickerBuilder: NSObject {

    private var proto = BackupProtos_StickerPackSticker()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(data: BackupProtoAttachmentPointer, emoji: String) {
        super.init()

        setData(data)
        setEmoji(emoji)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setData(_ valueParam: BackupProtoAttachmentPointer?) {
        guard let valueParam = valueParam else { return }
        proto.data = valueParam.proto
    }

    public func setData(_ valueParam: BackupProtoAttachmentPointer) {
        proto.data = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setEmoji(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.emoji = valueParam
    }

    public func setEmoji(_ valueParam: String) {
        proto.emoji = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoStickerPackSticker {
        return try BackupProtoStickerPackSticker(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoStickerPackSticker(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoStickerPackSticker {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoStickerPackStickerBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoStickerPackSticker? {
        return try! self.build()
    }
}

#endif
