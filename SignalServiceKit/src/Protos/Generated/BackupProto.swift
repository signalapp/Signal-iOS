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
    public let backupTimeMs: UInt64

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_BackupInfo,
                 version: UInt64,
                 backupTimeMs: UInt64) {
        self.proto = proto
        self.version = version
        self.backupTimeMs = backupTimeMs
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

        guard proto.hasBackupTimeMs else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: backupTimeMs")
        }
        let backupTimeMs = proto.backupTimeMs

        self.init(proto: proto,
                  version: version,
                  backupTimeMs: backupTimeMs)
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
    public static func builder(version: UInt64, backupTimeMs: UInt64) -> BackupProtoBackupInfoBuilder {
        return BackupProtoBackupInfoBuilder(version: version, backupTimeMs: backupTimeMs)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoBackupInfoBuilder {
        let builder = BackupProtoBackupInfoBuilder(version: version, backupTimeMs: backupTimeMs)
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
    fileprivate init(version: UInt64, backupTimeMs: UInt64) {
        super.init()

        setVersion(version)
        setBackupTimeMs(backupTimeMs)
    }

    @objc
    public func setVersion(_ valueParam: UInt64) {
        proto.version = valueParam
    }

    @objc
    public func setBackupTimeMs(_ valueParam: UInt64) {
        proto.backupTimeMs = valueParam
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
    public let readReceipts: Bool

    @objc
    public let sealedSenderIndicators: Bool

    @objc
    public let typingIndicators: Bool

    @objc
    public let noteToSelfMarkedUnread: Bool

    @objc
    public let linkPreviews: Bool

    @objc
    public let unlistedPhoneeumber: Bool

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
    public let groupStoryEducationSheetHasBeenSeen: Bool

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
                 readReceipts: Bool,
                 sealedSenderIndicators: Bool,
                 typingIndicators: Bool,
                 noteToSelfMarkedUnread: Bool,
                 linkPreviews: Bool,
                 unlistedPhoneeumber: Bool,
                 preferContactAvatars: Bool,
                 universalExpireTimer: UInt32,
                 displayBadgesOnProfile: Bool,
                 keepMutedChatsArchived: Bool,
                 myStoriesPrivacyHasBeenSet: Bool,
                 onboardingStoryHasBeenViewed: Bool,
                 storiesDisabled: Bool,
                 groupStoryEducationSheetHasBeenSeen: Bool,
                 usernameOnboardingHasBeenCompleted: Bool) {
        self.proto = proto
        self.readReceipts = readReceipts
        self.sealedSenderIndicators = sealedSenderIndicators
        self.typingIndicators = typingIndicators
        self.noteToSelfMarkedUnread = noteToSelfMarkedUnread
        self.linkPreviews = linkPreviews
        self.unlistedPhoneeumber = unlistedPhoneeumber
        self.preferContactAvatars = preferContactAvatars
        self.universalExpireTimer = universalExpireTimer
        self.displayBadgesOnProfile = displayBadgesOnProfile
        self.keepMutedChatsArchived = keepMutedChatsArchived
        self.myStoriesPrivacyHasBeenSet = myStoriesPrivacyHasBeenSet
        self.onboardingStoryHasBeenViewed = onboardingStoryHasBeenViewed
        self.storiesDisabled = storiesDisabled
        self.groupStoryEducationSheetHasBeenSeen = groupStoryEducationSheetHasBeenSeen
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

        guard proto.hasNoteToSelfMarkedUnread else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: noteToSelfMarkedUnread")
        }
        let noteToSelfMarkedUnread = proto.noteToSelfMarkedUnread

        guard proto.hasLinkPreviews else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: linkPreviews")
        }
        let linkPreviews = proto.linkPreviews

        guard proto.hasUnlistedPhoneeumber else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: unlistedPhoneeumber")
        }
        let unlistedPhoneeumber = proto.unlistedPhoneeumber

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

        guard proto.hasGroupStoryEducationSheetHasBeenSeen else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: groupStoryEducationSheetHasBeenSeen")
        }
        let groupStoryEducationSheetHasBeenSeen = proto.groupStoryEducationSheetHasBeenSeen

        guard proto.hasUsernameOnboardingHasBeenCompleted else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: usernameOnboardingHasBeenCompleted")
        }
        let usernameOnboardingHasBeenCompleted = proto.usernameOnboardingHasBeenCompleted

        self.init(proto: proto,
                  readReceipts: readReceipts,
                  sealedSenderIndicators: sealedSenderIndicators,
                  typingIndicators: typingIndicators,
                  noteToSelfMarkedUnread: noteToSelfMarkedUnread,
                  linkPreviews: linkPreviews,
                  unlistedPhoneeumber: unlistedPhoneeumber,
                  preferContactAvatars: preferContactAvatars,
                  universalExpireTimer: universalExpireTimer,
                  displayBadgesOnProfile: displayBadgesOnProfile,
                  keepMutedChatsArchived: keepMutedChatsArchived,
                  myStoriesPrivacyHasBeenSet: myStoriesPrivacyHasBeenSet,
                  onboardingStoryHasBeenViewed: onboardingStoryHasBeenViewed,
                  storiesDisabled: storiesDisabled,
                  groupStoryEducationSheetHasBeenSeen: groupStoryEducationSheetHasBeenSeen,
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
    public static func builder(readReceipts: Bool, sealedSenderIndicators: Bool, typingIndicators: Bool, noteToSelfMarkedUnread: Bool, linkPreviews: Bool, unlistedPhoneeumber: Bool, preferContactAvatars: Bool, universalExpireTimer: UInt32, displayBadgesOnProfile: Bool, keepMutedChatsArchived: Bool, myStoriesPrivacyHasBeenSet: Bool, onboardingStoryHasBeenViewed: Bool, storiesDisabled: Bool, groupStoryEducationSheetHasBeenSeen: Bool, usernameOnboardingHasBeenCompleted: Bool) -> BackupProtoAccountDataAccountSettingsBuilder {
        return BackupProtoAccountDataAccountSettingsBuilder(readReceipts: readReceipts, sealedSenderIndicators: sealedSenderIndicators, typingIndicators: typingIndicators, noteToSelfMarkedUnread: noteToSelfMarkedUnread, linkPreviews: linkPreviews, unlistedPhoneeumber: unlistedPhoneeumber, preferContactAvatars: preferContactAvatars, universalExpireTimer: universalExpireTimer, displayBadgesOnProfile: displayBadgesOnProfile, keepMutedChatsArchived: keepMutedChatsArchived, myStoriesPrivacyHasBeenSet: myStoriesPrivacyHasBeenSet, onboardingStoryHasBeenViewed: onboardingStoryHasBeenViewed, storiesDisabled: storiesDisabled, groupStoryEducationSheetHasBeenSeen: groupStoryEducationSheetHasBeenSeen, usernameOnboardingHasBeenCompleted: usernameOnboardingHasBeenCompleted)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoAccountDataAccountSettingsBuilder {
        let builder = BackupProtoAccountDataAccountSettingsBuilder(readReceipts: readReceipts, sealedSenderIndicators: sealedSenderIndicators, typingIndicators: typingIndicators, noteToSelfMarkedUnread: noteToSelfMarkedUnread, linkPreviews: linkPreviews, unlistedPhoneeumber: unlistedPhoneeumber, preferContactAvatars: preferContactAvatars, universalExpireTimer: universalExpireTimer, displayBadgesOnProfile: displayBadgesOnProfile, keepMutedChatsArchived: keepMutedChatsArchived, myStoriesPrivacyHasBeenSet: myStoriesPrivacyHasBeenSet, onboardingStoryHasBeenViewed: onboardingStoryHasBeenViewed, storiesDisabled: storiesDisabled, groupStoryEducationSheetHasBeenSeen: groupStoryEducationSheetHasBeenSeen, usernameOnboardingHasBeenCompleted: usernameOnboardingHasBeenCompleted)
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
    fileprivate init(readReceipts: Bool, sealedSenderIndicators: Bool, typingIndicators: Bool, noteToSelfMarkedUnread: Bool, linkPreviews: Bool, unlistedPhoneeumber: Bool, preferContactAvatars: Bool, universalExpireTimer: UInt32, displayBadgesOnProfile: Bool, keepMutedChatsArchived: Bool, myStoriesPrivacyHasBeenSet: Bool, onboardingStoryHasBeenViewed: Bool, storiesDisabled: Bool, groupStoryEducationSheetHasBeenSeen: Bool, usernameOnboardingHasBeenCompleted: Bool) {
        super.init()

        setReadReceipts(readReceipts)
        setSealedSenderIndicators(sealedSenderIndicators)
        setTypingIndicators(typingIndicators)
        setNoteToSelfMarkedUnread(noteToSelfMarkedUnread)
        setLinkPreviews(linkPreviews)
        setUnlistedPhoneeumber(unlistedPhoneeumber)
        setPreferContactAvatars(preferContactAvatars)
        setUniversalExpireTimer(universalExpireTimer)
        setDisplayBadgesOnProfile(displayBadgesOnProfile)
        setKeepMutedChatsArchived(keepMutedChatsArchived)
        setMyStoriesPrivacyHasBeenSet(myStoriesPrivacyHasBeenSet)
        setOnboardingStoryHasBeenViewed(onboardingStoryHasBeenViewed)
        setStoriesDisabled(storiesDisabled)
        setGroupStoryEducationSheetHasBeenSeen(groupStoryEducationSheetHasBeenSeen)
        setUsernameOnboardingHasBeenCompleted(usernameOnboardingHasBeenCompleted)
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
    public func setNoteToSelfMarkedUnread(_ valueParam: Bool) {
        proto.noteToSelfMarkedUnread = valueParam
    }

    @objc
    public func setLinkPreviews(_ valueParam: Bool) {
        proto.linkPreviews = valueParam
    }

    @objc
    public func setUnlistedPhoneeumber(_ valueParam: Bool) {
        proto.unlistedPhoneeumber = valueParam
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
    public func setGroupStoryEducationSheetHasBeenSeen(_ valueParam: Bool) {
        proto.groupStoryEducationSheetHasBeenSeen = valueParam
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
    case unknown = 0
    case everybody = 1
    case nobody = 2
}

private func BackupProtoAccountDataPhoneNumberSharingModeWrap(_ value: BackupProtos_AccountData.PhoneNumberSharingMode) -> BackupProtoAccountDataPhoneNumberSharingMode {
    switch value {
    case .unknown: return .unknown
    case .everybody: return .everybody
    case .nobody: return .nobody
    }
}

private func BackupProtoAccountDataPhoneNumberSharingModeUnwrap(_ value: BackupProtoAccountDataPhoneNumberSharingMode) -> BackupProtos_AccountData.PhoneNumberSharingMode {
    switch value {
    case .unknown: return .unknown
    case .everybody: return .everybody
    case .nobody: return .nobody
    }
}

// MARK: - BackupProtoAccountData

@objc
public class BackupProtoAccountData: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_AccountData

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
                 profileKey: Data,
                 usernameLink: BackupProtoAccountDataUsernameLink,
                 givenName: String,
                 familyName: String,
                 avatarPath: String,
                 subscriberID: Data,
                 subscriberCurrencyCode: String,
                 subscriptionManuallyCancelled: Bool,
                 accountSettings: BackupProtoAccountDataAccountSettings) {
        self.proto = proto
        self.profileKey = profileKey
        self.usernameLink = usernameLink
        self.givenName = givenName
        self.familyName = familyName
        self.avatarPath = avatarPath
        self.subscriberID = subscriberID
        self.subscriberCurrencyCode = subscriberCurrencyCode
        self.subscriptionManuallyCancelled = subscriptionManuallyCancelled
        self.accountSettings = accountSettings
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

        self.init(proto: proto,
                  profileKey: profileKey,
                  usernameLink: usernameLink,
                  givenName: givenName,
                  familyName: familyName,
                  avatarPath: avatarPath,
                  subscriberID: subscriberID,
                  subscriberCurrencyCode: subscriberCurrencyCode,
                  subscriptionManuallyCancelled: subscriptionManuallyCancelled,
                  accountSettings: accountSettings)
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
    public static func builder(profileKey: Data, usernameLink: BackupProtoAccountDataUsernameLink, givenName: String, familyName: String, avatarPath: String, subscriberID: Data, subscriberCurrencyCode: String, subscriptionManuallyCancelled: Bool, accountSettings: BackupProtoAccountDataAccountSettings) -> BackupProtoAccountDataBuilder {
        return BackupProtoAccountDataBuilder(profileKey: profileKey, usernameLink: usernameLink, givenName: givenName, familyName: familyName, avatarPath: avatarPath, subscriberID: subscriberID, subscriberCurrencyCode: subscriberCurrencyCode, subscriptionManuallyCancelled: subscriptionManuallyCancelled, accountSettings: accountSettings)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoAccountDataBuilder {
        let builder = BackupProtoAccountDataBuilder(profileKey: profileKey, usernameLink: usernameLink, givenName: givenName, familyName: familyName, avatarPath: avatarPath, subscriberID: subscriberID, subscriberCurrencyCode: subscriberCurrencyCode, subscriptionManuallyCancelled: subscriptionManuallyCancelled, accountSettings: accountSettings)
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
    fileprivate init(profileKey: Data, usernameLink: BackupProtoAccountDataUsernameLink, givenName: String, familyName: String, avatarPath: String, subscriberID: Data, subscriberCurrencyCode: String, subscriptionManuallyCancelled: Bool, accountSettings: BackupProtoAccountDataAccountSettings) {
        super.init()

        setProfileKey(profileKey)
        setUsernameLink(usernameLink)
        setGivenName(givenName)
        setFamilyName(familyName)
        setAvatarPath(avatarPath)
        setSubscriberID(subscriberID)
        setSubscriberCurrencyCode(subscriberCurrencyCode)
        setSubscriptionManuallyCancelled(subscriptionManuallyCancelled)
        setAccountSettings(accountSettings)
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

    @objc
    public let releaseNotes: BackupProtoReleaseNotes?

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
                 selfRecipient: BackupProtoSelfRecipient?,
                 releaseNotes: BackupProtoReleaseNotes?) {
        self.proto = proto
        self.id = id
        self.contact = contact
        self.group = group
        self.distributionList = distributionList
        self.selfRecipient = selfRecipient
        self.releaseNotes = releaseNotes
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

        var releaseNotes: BackupProtoReleaseNotes?
        if proto.hasReleaseNotes {
            releaseNotes = BackupProtoReleaseNotes(proto.releaseNotes)
        }

        self.init(proto: proto,
                  id: id,
                  contact: contact,
                  group: group,
                  distributionList: distributionList,
                  selfRecipient: selfRecipient,
                  releaseNotes: releaseNotes)
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
        if let _value = releaseNotes {
            builder.setReleaseNotes(_value)
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

    @objc
    @available(swift, obsoleted: 1.0)
    public func setReleaseNotes(_ valueParam: BackupProtoReleaseNotes?) {
        guard let valueParam = valueParam else { return }
        proto.releaseNotes = valueParam.proto
    }

    public func setReleaseNotes(_ valueParam: BackupProtoReleaseNotes) {
        proto.releaseNotes = valueParam.proto
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

// MARK: - BackupProtoReleaseNotes

@objc
public class BackupProtoReleaseNotes: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_ReleaseNotes

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ReleaseNotes) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_ReleaseNotes(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ReleaseNotes) {
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

extension BackupProtoReleaseNotes {
    @objc
    public static func builder() -> BackupProtoReleaseNotesBuilder {
        return BackupProtoReleaseNotesBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoReleaseNotesBuilder {
        let builder = BackupProtoReleaseNotesBuilder()
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoReleaseNotesBuilder: NSObject {

    private var proto = BackupProtos_ReleaseNotes()

    @objc
    fileprivate override init() {}

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoReleaseNotes {
        return BackupProtoReleaseNotes(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoReleaseNotes {
        return BackupProtoReleaseNotes(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoReleaseNotes(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoReleaseNotes {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoReleaseNotesBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoReleaseNotes? {
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
    public let pinnedOrder: UInt32

    @objc
    public let expirationTimerMs: UInt64

    @objc
    public let muteUntilMs: UInt64

    @objc
    public let markedUnread: Bool

    @objc
    public let dontNotifyForMentionsIfMuted: Bool

    @objc
    public let wallpaper: BackupProtoFilePointer?

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
                 pinnedOrder: UInt32,
                 expirationTimerMs: UInt64,
                 muteUntilMs: UInt64,
                 markedUnread: Bool,
                 dontNotifyForMentionsIfMuted: Bool,
                 wallpaper: BackupProtoFilePointer?) {
        self.proto = proto
        self.id = id
        self.recipientID = recipientID
        self.archived = archived
        self.pinnedOrder = pinnedOrder
        self.expirationTimerMs = expirationTimerMs
        self.muteUntilMs = muteUntilMs
        self.markedUnread = markedUnread
        self.dontNotifyForMentionsIfMuted = dontNotifyForMentionsIfMuted
        self.wallpaper = wallpaper
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

        guard proto.hasPinnedOrder else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: pinnedOrder")
        }
        let pinnedOrder = proto.pinnedOrder

        guard proto.hasExpirationTimerMs else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: expirationTimerMs")
        }
        let expirationTimerMs = proto.expirationTimerMs

        guard proto.hasMuteUntilMs else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: muteUntilMs")
        }
        let muteUntilMs = proto.muteUntilMs

        guard proto.hasMarkedUnread else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: markedUnread")
        }
        let markedUnread = proto.markedUnread

        guard proto.hasDontNotifyForMentionsIfMuted else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: dontNotifyForMentionsIfMuted")
        }
        let dontNotifyForMentionsIfMuted = proto.dontNotifyForMentionsIfMuted

        var wallpaper: BackupProtoFilePointer?
        if proto.hasWallpaper {
            wallpaper = try BackupProtoFilePointer(proto.wallpaper)
        }

        self.init(proto: proto,
                  id: id,
                  recipientID: recipientID,
                  archived: archived,
                  pinnedOrder: pinnedOrder,
                  expirationTimerMs: expirationTimerMs,
                  muteUntilMs: muteUntilMs,
                  markedUnread: markedUnread,
                  dontNotifyForMentionsIfMuted: dontNotifyForMentionsIfMuted,
                  wallpaper: wallpaper)
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
    public static func builder(id: UInt64, recipientID: UInt64, archived: Bool, pinnedOrder: UInt32, expirationTimerMs: UInt64, muteUntilMs: UInt64, markedUnread: Bool, dontNotifyForMentionsIfMuted: Bool) -> BackupProtoChatBuilder {
        return BackupProtoChatBuilder(id: id, recipientID: recipientID, archived: archived, pinnedOrder: pinnedOrder, expirationTimerMs: expirationTimerMs, muteUntilMs: muteUntilMs, markedUnread: markedUnread, dontNotifyForMentionsIfMuted: dontNotifyForMentionsIfMuted)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoChatBuilder {
        let builder = BackupProtoChatBuilder(id: id, recipientID: recipientID, archived: archived, pinnedOrder: pinnedOrder, expirationTimerMs: expirationTimerMs, muteUntilMs: muteUntilMs, markedUnread: markedUnread, dontNotifyForMentionsIfMuted: dontNotifyForMentionsIfMuted)
        if let _value = wallpaper {
            builder.setWallpaper(_value)
        }
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
    fileprivate init(id: UInt64, recipientID: UInt64, archived: Bool, pinnedOrder: UInt32, expirationTimerMs: UInt64, muteUntilMs: UInt64, markedUnread: Bool, dontNotifyForMentionsIfMuted: Bool) {
        super.init()

        setId(id)
        setRecipientID(recipientID)
        setArchived(archived)
        setPinnedOrder(pinnedOrder)
        setExpirationTimerMs(expirationTimerMs)
        setMuteUntilMs(muteUntilMs)
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
    public func setPinnedOrder(_ valueParam: UInt32) {
        proto.pinnedOrder = valueParam
    }

    @objc
    public func setExpirationTimerMs(_ valueParam: UInt64) {
        proto.expirationTimerMs = valueParam
    }

    @objc
    public func setMuteUntilMs(_ valueParam: UInt64) {
        proto.muteUntilMs = valueParam
    }

    @objc
    public func setMarkedUnread(_ valueParam: Bool) {
        proto.markedUnread = valueParam
    }

    @objc
    public func setDontNotifyForMentionsIfMuted(_ valueParam: Bool) {
        proto.dontNotifyForMentionsIfMuted = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setWallpaper(_ valueParam: BackupProtoFilePointer?) {
        guard let valueParam = valueParam else { return }
        proto.wallpaper = valueParam.proto
    }

    public func setWallpaper(_ valueParam: BackupProtoFilePointer) {
        proto.wallpaper = valueParam.proto
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
    case unknown = 0
    case onlyWith = 1
    case allExcept = 2
    case all = 3
}

private func BackupProtoDistributionListPrivacyModeWrap(_ value: BackupProtos_DistributionList.PrivacyMode) -> BackupProtoDistributionListPrivacyMode {
    switch value {
    case .unknown: return .unknown
    case .onlyWith: return .onlyWith
    case .allExcept: return .allExcept
    case .all: return .all
    }
}

private func BackupProtoDistributionListPrivacyModeUnwrap(_ value: BackupProtoDistributionListPrivacyMode) -> BackupProtos_DistributionList.PrivacyMode {
    switch value {
    case .unknown: return .unknown
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
                 deletionTimestamp: UInt64) {
        self.proto = proto
        self.name = name
        self.distributionID = distributionID
        self.allowReplies = allowReplies
        self.deletionTimestamp = deletionTimestamp
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

        self.init(proto: proto,
                  name: name,
                  distributionID: distributionID,
                  allowReplies: allowReplies,
                  deletionTimestamp: deletionTimestamp)
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
    public static func builder(name: String, distributionID: Data, allowReplies: Bool, deletionTimestamp: UInt64) -> BackupProtoDistributionListBuilder {
        return BackupProtoDistributionListBuilder(name: name, distributionID: distributionID, allowReplies: allowReplies, deletionTimestamp: deletionTimestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoDistributionListBuilder {
        let builder = BackupProtoDistributionListBuilder(name: name, distributionID: distributionID, allowReplies: allowReplies, deletionTimestamp: deletionTimestamp)
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
    fileprivate init(name: String, distributionID: Data, allowReplies: Bool, deletionTimestamp: UInt64) {
        super.init()

        setName(name)
        setDistributionID(distributionID)
        setAllowReplies(allowReplies)
        setDeletionTimestamp(deletionTimestamp)
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
    case unknownType = 0
    case audioCall = 1
    case videoCall = 2
    case groupCall = 3
    case adHocCall = 4
}

private func BackupProtoCallTypeWrap(_ value: BackupProtos_Call.TypeEnum) -> BackupProtoCallType {
    switch value {
    case .unknownType: return .unknownType
    case .audioCall: return .audioCall
    case .videoCall: return .videoCall
    case .groupCall: return .groupCall
    case .adHocCall: return .adHocCall
    }
}

private func BackupProtoCallTypeUnwrap(_ value: BackupProtoCallType) -> BackupProtos_Call.TypeEnum {
    switch value {
    case .unknownType: return .unknownType
    case .audioCall: return .audioCall
    case .videoCall: return .videoCall
    case .groupCall: return .groupCall
    case .adHocCall: return .adHocCall
    }
}

// MARK: - BackupProtoCallEvent

@objc
public enum BackupProtoCallEvent: Int32 {
    case unknownEvent = 0
    case outgoing = 1
    case accepted = 2
    case notAccepted = 3
    case missed = 4
    case delete = 5
    case genericGroupCall = 6
    case joined = 7
    case declined = 8
    case outgoingRing = 9
}

private func BackupProtoCallEventWrap(_ value: BackupProtos_Call.Event) -> BackupProtoCallEvent {
    switch value {
    case .unknownEvent: return .unknownEvent
    case .outgoing: return .outgoing
    case .accepted: return .accepted
    case .notAccepted: return .notAccepted
    case .missed: return .missed
    case .delete: return .delete
    case .genericGroupCall: return .genericGroupCall
    case .joined: return .joined
    case .declined: return .declined
    case .outgoingRing: return .outgoingRing
    }
}

private func BackupProtoCallEventUnwrap(_ value: BackupProtoCallEvent) -> BackupProtos_Call.Event {
    switch value {
    case .unknownEvent: return .unknownEvent
    case .outgoing: return .outgoing
    case .accepted: return .accepted
    case .notAccepted: return .notAccepted
    case .missed: return .missed
    case .delete: return .delete
    case .genericGroupCall: return .genericGroupCall
    case .joined: return .joined
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
    public let conversationRecipientID: UInt64

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
                 conversationRecipientID: UInt64,
                 outgoing: Bool,
                 timestamp: UInt64,
                 ringerRecipientID: UInt64) {
        self.proto = proto
        self.callID = callID
        self.conversationRecipientID = conversationRecipientID
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

        guard proto.hasConversationRecipientID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: conversationRecipientID")
        }
        let conversationRecipientID = proto.conversationRecipientID

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
                  conversationRecipientID: conversationRecipientID,
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
    public static func builder(callID: UInt64, conversationRecipientID: UInt64, outgoing: Bool, timestamp: UInt64, ringerRecipientID: UInt64) -> BackupProtoCallBuilder {
        return BackupProtoCallBuilder(callID: callID, conversationRecipientID: conversationRecipientID, outgoing: outgoing, timestamp: timestamp, ringerRecipientID: ringerRecipientID)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoCallBuilder {
        let builder = BackupProtoCallBuilder(callID: callID, conversationRecipientID: conversationRecipientID, outgoing: outgoing, timestamp: timestamp, ringerRecipientID: ringerRecipientID)
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
    fileprivate init(callID: UInt64, conversationRecipientID: UInt64, outgoing: Bool, timestamp: UInt64, ringerRecipientID: UInt64) {
        super.init()

        setCallID(callID)
        setConversationRecipientID(conversationRecipientID)
        setOutgoing(outgoing)
        setTimestamp(timestamp)
        setRingerRecipientID(ringerRecipientID)
    }

    @objc
    public func setCallID(_ valueParam: UInt64) {
        proto.callID = valueParam
    }

    @objc
    public func setConversationRecipientID(_ valueParam: UInt64) {
        proto.conversationRecipientID = valueParam
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
    public let dateReceived: UInt64

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
                 dateReceived: UInt64,
                 dateServerSent: UInt64,
                 read: Bool,
                 sealedSender: Bool) {
        self.proto = proto
        self.dateReceived = dateReceived
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
        guard proto.hasDateReceived else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: dateReceived")
        }
        let dateReceived = proto.dateReceived

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
                  dateReceived: dateReceived,
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
    public static func builder(dateReceived: UInt64, dateServerSent: UInt64, read: Bool, sealedSender: Bool) -> BackupProtoChatItemIncomingMessageDetailsBuilder {
        return BackupProtoChatItemIncomingMessageDetailsBuilder(dateReceived: dateReceived, dateServerSent: dateServerSent, read: read, sealedSender: sealedSender)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoChatItemIncomingMessageDetailsBuilder {
        let builder = BackupProtoChatItemIncomingMessageDetailsBuilder(dateReceived: dateReceived, dateServerSent: dateServerSent, read: read, sealedSender: sealedSender)
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
    fileprivate init(dateReceived: UInt64, dateServerSent: UInt64, read: Bool, sealedSender: Bool) {
        super.init()

        setDateReceived(dateReceived)
        setDateServerSent(dateServerSent)
        setRead(read)
        setSealedSender(sealedSender)
    }

    @objc
    public func setDateReceived(_ valueParam: UInt64) {
        proto.dateReceived = valueParam
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
    public var expireStartMs: UInt64 {
        return proto.expireStartMs
    }
    @objc
    public var hasExpireStartMs: Bool {
        return proto.hasExpireStartMs
    }

    @objc
    public var expiresInMs: UInt64 {
        return proto.expiresInMs
    }
    @objc
    public var hasExpiresInMs: Bool {
        return proto.hasExpiresInMs
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
    public static func builder(chatID: UInt64, authorID: UInt64, dateSent: UInt64, sms: Bool) -> BackupProtoChatItemBuilder {
        return BackupProtoChatItemBuilder(chatID: chatID, authorID: authorID, dateSent: dateSent, sms: sms)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoChatItemBuilder {
        let builder = BackupProtoChatItemBuilder(chatID: chatID, authorID: authorID, dateSent: dateSent, sms: sms)
        if hasExpireStartMs {
            builder.setExpireStartMs(expireStartMs)
        }
        if hasExpiresInMs {
            builder.setExpiresInMs(expiresInMs)
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
    fileprivate init(chatID: UInt64, authorID: UInt64, dateSent: UInt64, sms: Bool) {
        super.init()

        setChatID(chatID)
        setAuthorID(authorID)
        setDateSent(dateSent)
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
    public func setExpireStartMs(_ valueParam: UInt64) {
        proto.expireStartMs = valueParam
    }

    @objc
    public func setExpiresInMs(_ valueParam: UInt64) {
        proto.expiresInMs = valueParam
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
    case unknown = 0
    case failed = 1
    case pending = 2
    case sent = 3
    case delivered = 4
    case read = 5
    case viewed = 6
    case skipped = 7
}

private func BackupProtoSendStatusStatusWrap(_ value: BackupProtos_SendStatus.Status) -> BackupProtoSendStatusStatus {
    switch value {
    case .unknown: return .unknown
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
    case .unknown: return .unknown
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
    public let attachments: [BackupProtoFilePointer]

    @objc
    public let linkPreview: [BackupProtoLinkPreview]

    @objc
    public let longText: BackupProtoFilePointer?

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
                 attachments: [BackupProtoFilePointer],
                 linkPreview: [BackupProtoLinkPreview],
                 longText: BackupProtoFilePointer?,
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
            quote = try BackupProtoQuote(proto.quote)
        }

        var text: BackupProtoText?
        if proto.hasText {
            text = try BackupProtoText(proto.text)
        }

        var attachments: [BackupProtoFilePointer] = []
        attachments = try proto.attachments.map { try BackupProtoFilePointer($0) }

        var linkPreview: [BackupProtoLinkPreview] = []
        linkPreview = try proto.linkPreview.map { try BackupProtoLinkPreview($0) }

        var longText: BackupProtoFilePointer?
        if proto.hasLongText {
            longText = try BackupProtoFilePointer(proto.longText)
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
        builder.setLinkPreview(linkPreview)
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
    public func addAttachments(_ valueParam: BackupProtoFilePointer) {
        proto.attachments.append(valueParam.proto)
    }

    @objc
    public func setAttachments(_ wrappedItems: [BackupProtoFilePointer]) {
        proto.attachments = wrappedItems.map { $0.proto }
    }

    @objc
    public func addLinkPreview(_ valueParam: BackupProtoLinkPreview) {
        proto.linkPreview.append(valueParam.proto)
    }

    @objc
    public func setLinkPreview(_ wrappedItems: [BackupProtoLinkPreview]) {
        proto.linkPreview = wrappedItems.map { $0.proto }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setLongText(_ valueParam: BackupProtoFilePointer?) {
        guard let valueParam = valueParam else { return }
        proto.longText = valueParam.proto
    }

    public func setLongText(_ valueParam: BackupProtoFilePointer) {
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
        contact = try proto.contact.map { try BackupProtoContactAttachment($0) }

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
    case unknown = 0
    case home = 1
    case mobile = 2
    case work = 3
    case custom = 4
}

private func BackupProtoContactAttachmentPhoneTypeWrap(_ value: BackupProtos_ContactAttachment.Phone.TypeEnum) -> BackupProtoContactAttachmentPhoneType {
    switch value {
    case .unknown: return .unknown
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

private func BackupProtoContactAttachmentPhoneTypeUnwrap(_ value: BackupProtoContactAttachmentPhoneType) -> BackupProtos_ContactAttachment.Phone.TypeEnum {
    switch value {
    case .unknown: return .unknown
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
    case unknown = 0
    case home = 1
    case mobile = 2
    case work = 3
    case custom = 4
}

private func BackupProtoContactAttachmentEmailTypeWrap(_ value: BackupProtos_ContactAttachment.Email.TypeEnum) -> BackupProtoContactAttachmentEmailType {
    switch value {
    case .unknown: return .unknown
    case .home: return .home
    case .mobile: return .mobile
    case .work: return .work
    case .custom: return .custom
    }
}

private func BackupProtoContactAttachmentEmailTypeUnwrap(_ value: BackupProtoContactAttachmentEmailType) -> BackupProtos_ContactAttachment.Email.TypeEnum {
    switch value {
    case .unknown: return .unknown
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
    case unknown = 0
    case home = 1
    case work = 2
    case custom = 3
}

private func BackupProtoContactAttachmentPostalAddressTypeWrap(_ value: BackupProtos_ContactAttachment.PostalAddress.TypeEnum) -> BackupProtoContactAttachmentPostalAddressType {
    switch value {
    case .unknown: return .unknown
    case .home: return .home
    case .work: return .work
    case .custom: return .custom
    }
}

private func BackupProtoContactAttachmentPostalAddressTypeUnwrap(_ value: BackupProtoContactAttachmentPostalAddressType) -> BackupProtos_ContactAttachment.PostalAddress.TypeEnum {
    switch value {
    case .unknown: return .unknown
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
    public let avatar: BackupProtoFilePointer

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ContactAttachment.Avatar,
                 avatar: BackupProtoFilePointer) {
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
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ContactAttachment.Avatar) throws {
        guard proto.hasAvatar else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: avatar")
        }
        let avatar = try BackupProtoFilePointer(proto.avatar)

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
    public static func builder(avatar: BackupProtoFilePointer) -> BackupProtoContactAttachmentAvatarBuilder {
        return BackupProtoContactAttachmentAvatarBuilder(avatar: avatar)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoContactAttachmentAvatarBuilder {
        let builder = BackupProtoContactAttachmentAvatarBuilder(avatar: avatar)
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
    fileprivate init(avatar: BackupProtoFilePointer) {
        super.init()

        setAvatar(avatar)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAvatar(_ valueParam: BackupProtoFilePointer?) {
        guard let valueParam = valueParam else { return }
        proto.avatar = valueParam.proto
    }

    public func setAvatar(_ valueParam: BackupProtoFilePointer) {
        proto.avatar = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoContactAttachmentAvatar {
        return try BackupProtoContactAttachmentAvatar(proto)
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
        return try! self.build()
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
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_ContactAttachment) throws {
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
            avatar = try BackupProtoContactAttachmentAvatar(proto.avatar)
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
        return try BackupProtoContactAttachment(proto)
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
        return try! self.build()
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
    public let document: BackupProtoFilePointer

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
                 document: BackupProtoFilePointer,
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
        let document = try BackupProtoFilePointer(proto.document)

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
    public static func builder(text: BackupProtoText, document: BackupProtoFilePointer) -> BackupProtoDocumentMessageBuilder {
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
    fileprivate init(text: BackupProtoText, document: BackupProtoFilePointer) {
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
    public func setDocument(_ valueParam: BackupProtoFilePointer?) {
        guard let valueParam = valueParam else { return }
        proto.document = valueParam.proto
    }

    public func setDocument(_ valueParam: BackupProtoFilePointer) {
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
    public let audio: BackupProtoFilePointer

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
                 audio: BackupProtoFilePointer,
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
            quote = try BackupProtoQuote(proto.quote)
        }

        guard proto.hasAudio else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: audio")
        }
        let audio = try BackupProtoFilePointer(proto.audio)

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
    public static func builder(audio: BackupProtoFilePointer) -> BackupProtoVoiceMessageBuilder {
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
    fileprivate init(audio: BackupProtoFilePointer) {
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
    public func setAudio(_ valueParam: BackupProtoFilePointer?) {
        guard let valueParam = valueParam else { return }
        proto.audio = valueParam.proto
    }

    public func setAudio(_ valueParam: BackupProtoFilePointer) {
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
        let sticker = try BackupProtoSticker(proto.sticker)

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
    public let packID: Data

    @objc
    public let packKey: Data

    @objc
    public let stickerID: UInt32

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
                 packID: Data,
                 packKey: Data,
                 stickerID: UInt32) {
        self.proto = proto
        self.packID = packID
        self.packKey = packKey
        self.stickerID = stickerID
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_Sticker(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Sticker) throws {
        guard proto.hasPackID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: packID")
        }
        let packID = proto.packID

        guard proto.hasPackKey else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: packKey")
        }
        let packKey = proto.packKey

        guard proto.hasStickerID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: stickerID")
        }
        let stickerID = proto.stickerID

        self.init(proto: proto,
                  packID: packID,
                  packKey: packKey,
                  stickerID: stickerID)
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
    public static func builder(packID: Data, packKey: Data, stickerID: UInt32) -> BackupProtoStickerBuilder {
        return BackupProtoStickerBuilder(packID: packID, packKey: packKey, stickerID: stickerID)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoStickerBuilder {
        let builder = BackupProtoStickerBuilder(packID: packID, packKey: packKey, stickerID: stickerID)
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
    fileprivate init(packID: Data, packKey: Data, stickerID: UInt32) {
        super.init()

        setPackID(packID)
        setPackKey(packKey)
        setStickerID(stickerID)
    }

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
        return try BackupProtoSticker(proto)
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
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoLinkPreview

@objc
public class BackupProtoLinkPreview: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_LinkPreview

    @objc
    public let url: String

    @objc
    public let image: BackupProtoFilePointer?

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
                 url: String,
                 image: BackupProtoFilePointer?) {
        self.proto = proto
        self.url = url
        self.image = image
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_LinkPreview(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_LinkPreview) throws {
        guard proto.hasURL else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: url")
        }
        let url = proto.url

        var image: BackupProtoFilePointer?
        if proto.hasImage {
            image = try BackupProtoFilePointer(proto.image)
        }

        self.init(proto: proto,
                  url: url,
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
    public static func builder(url: String) -> BackupProtoLinkPreviewBuilder {
        return BackupProtoLinkPreviewBuilder(url: url)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoLinkPreviewBuilder {
        let builder = BackupProtoLinkPreviewBuilder(url: url)
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
    fileprivate init(url: String) {
        super.init()

        setUrl(url)
    }

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
    public func setImage(_ valueParam: BackupProtoFilePointer?) {
        guard let valueParam = valueParam else { return }
        proto.image = valueParam.proto
    }

    public func setImage(_ valueParam: BackupProtoFilePointer) {
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
        return try BackupProtoLinkPreview(proto)
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
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoFilePointerBackupLocator

@objc
public class BackupProtoFilePointerBackupLocator: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_FilePointer.BackupLocator

    @objc
    public let mediaName: String

    @objc
    public let cdnNumber: UInt32

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_FilePointer.BackupLocator,
                 mediaName: String,
                 cdnNumber: UInt32) {
        self.proto = proto
        self.mediaName = mediaName
        self.cdnNumber = cdnNumber
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_FilePointer.BackupLocator(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_FilePointer.BackupLocator) throws {
        guard proto.hasMediaName else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: mediaName")
        }
        let mediaName = proto.mediaName

        guard proto.hasCdnNumber else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: cdnNumber")
        }
        let cdnNumber = proto.cdnNumber

        self.init(proto: proto,
                  mediaName: mediaName,
                  cdnNumber: cdnNumber)
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

extension BackupProtoFilePointerBackupLocator {
    @objc
    public static func builder(mediaName: String, cdnNumber: UInt32) -> BackupProtoFilePointerBackupLocatorBuilder {
        return BackupProtoFilePointerBackupLocatorBuilder(mediaName: mediaName, cdnNumber: cdnNumber)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoFilePointerBackupLocatorBuilder {
        let builder = BackupProtoFilePointerBackupLocatorBuilder(mediaName: mediaName, cdnNumber: cdnNumber)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoFilePointerBackupLocatorBuilder: NSObject {

    private var proto = BackupProtos_FilePointer.BackupLocator()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(mediaName: String, cdnNumber: UInt32) {
        super.init()

        setMediaName(mediaName)
        setCdnNumber(cdnNumber)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setMediaName(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.mediaName = valueParam
    }

    public func setMediaName(_ valueParam: String) {
        proto.mediaName = valueParam
    }

    @objc
    public func setCdnNumber(_ valueParam: UInt32) {
        proto.cdnNumber = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoFilePointerBackupLocator {
        return try BackupProtoFilePointerBackupLocator(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoFilePointerBackupLocator(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoFilePointerBackupLocator {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoFilePointerBackupLocatorBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoFilePointerBackupLocator? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoFilePointerAttachmentLocator

@objc
public class BackupProtoFilePointerAttachmentLocator: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_FilePointer.AttachmentLocator

    @objc
    public let cdnKey: String

    @objc
    public let cdnNumber: UInt32

    @objc
    public let uploadTimestamp: UInt64

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_FilePointer.AttachmentLocator,
                 cdnKey: String,
                 cdnNumber: UInt32,
                 uploadTimestamp: UInt64) {
        self.proto = proto
        self.cdnKey = cdnKey
        self.cdnNumber = cdnNumber
        self.uploadTimestamp = uploadTimestamp
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_FilePointer.AttachmentLocator(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_FilePointer.AttachmentLocator) throws {
        guard proto.hasCdnKey else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: cdnKey")
        }
        let cdnKey = proto.cdnKey

        guard proto.hasCdnNumber else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: cdnNumber")
        }
        let cdnNumber = proto.cdnNumber

        guard proto.hasUploadTimestamp else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: uploadTimestamp")
        }
        let uploadTimestamp = proto.uploadTimestamp

        self.init(proto: proto,
                  cdnKey: cdnKey,
                  cdnNumber: cdnNumber,
                  uploadTimestamp: uploadTimestamp)
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

extension BackupProtoFilePointerAttachmentLocator {
    @objc
    public static func builder(cdnKey: String, cdnNumber: UInt32, uploadTimestamp: UInt64) -> BackupProtoFilePointerAttachmentLocatorBuilder {
        return BackupProtoFilePointerAttachmentLocatorBuilder(cdnKey: cdnKey, cdnNumber: cdnNumber, uploadTimestamp: uploadTimestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoFilePointerAttachmentLocatorBuilder {
        let builder = BackupProtoFilePointerAttachmentLocatorBuilder(cdnKey: cdnKey, cdnNumber: cdnNumber, uploadTimestamp: uploadTimestamp)
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoFilePointerAttachmentLocatorBuilder: NSObject {

    private var proto = BackupProtos_FilePointer.AttachmentLocator()

    @objc
    fileprivate override init() {}

    @objc
    fileprivate init(cdnKey: String, cdnNumber: UInt32, uploadTimestamp: UInt64) {
        super.init()

        setCdnKey(cdnKey)
        setCdnNumber(cdnNumber)
        setUploadTimestamp(uploadTimestamp)
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
    public func setCdnNumber(_ valueParam: UInt32) {
        proto.cdnNumber = valueParam
    }

    @objc
    public func setUploadTimestamp(_ valueParam: UInt64) {
        proto.uploadTimestamp = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoFilePointerAttachmentLocator {
        return try BackupProtoFilePointerAttachmentLocator(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoFilePointerAttachmentLocator(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoFilePointerAttachmentLocator {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoFilePointerAttachmentLocatorBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoFilePointerAttachmentLocator? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoFilePointerLegacyAttachmentLocator

@objc
public class BackupProtoFilePointerLegacyAttachmentLocator: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_FilePointer.LegacyAttachmentLocator

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_FilePointer.LegacyAttachmentLocator) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_FilePointer.LegacyAttachmentLocator(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_FilePointer.LegacyAttachmentLocator) {
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

extension BackupProtoFilePointerLegacyAttachmentLocator {
    @objc
    public static func builder() -> BackupProtoFilePointerLegacyAttachmentLocatorBuilder {
        return BackupProtoFilePointerLegacyAttachmentLocatorBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoFilePointerLegacyAttachmentLocatorBuilder {
        let builder = BackupProtoFilePointerLegacyAttachmentLocatorBuilder()
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoFilePointerLegacyAttachmentLocatorBuilder: NSObject {

    private var proto = BackupProtos_FilePointer.LegacyAttachmentLocator()

    @objc
    fileprivate override init() {}

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoFilePointerLegacyAttachmentLocator {
        return BackupProtoFilePointerLegacyAttachmentLocator(proto)
    }

    @objc
    public func buildInfallibly() -> BackupProtoFilePointerLegacyAttachmentLocator {
        return BackupProtoFilePointerLegacyAttachmentLocator(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoFilePointerLegacyAttachmentLocator(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoFilePointerLegacyAttachmentLocator {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoFilePointerLegacyAttachmentLocatorBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoFilePointerLegacyAttachmentLocator? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - BackupProtoFilePointerFlags

@objc
public enum BackupProtoFilePointerFlags: Int32 {
    case voiceMessage = 0
    case borderless = 1
    case gif = 2
}

private func BackupProtoFilePointerFlagsWrap(_ value: BackupProtos_FilePointer.Flags) -> BackupProtoFilePointerFlags {
    switch value {
    case .voiceMessage: return .voiceMessage
    case .borderless: return .borderless
    case .gif: return .gif
    }
}

private func BackupProtoFilePointerFlagsUnwrap(_ value: BackupProtoFilePointerFlags) -> BackupProtos_FilePointer.Flags {
    switch value {
    case .voiceMessage: return .voiceMessage
    case .borderless: return .borderless
    case .gif: return .gif
    }
}

// MARK: - BackupProtoFilePointer

@objc
public class BackupProtoFilePointer: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_FilePointer

    @objc
    public let backupLocator: BackupProtoFilePointerBackupLocator?

    @objc
    public let attachmentLocator: BackupProtoFilePointerAttachmentLocator?

    @objc
    public let legacyAttachmentLocator: BackupProtoFilePointerLegacyAttachmentLocator?

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

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_FilePointer,
                 backupLocator: BackupProtoFilePointerBackupLocator?,
                 attachmentLocator: BackupProtoFilePointerAttachmentLocator?,
                 legacyAttachmentLocator: BackupProtoFilePointerLegacyAttachmentLocator?) {
        self.proto = proto
        self.backupLocator = backupLocator
        self.attachmentLocator = attachmentLocator
        self.legacyAttachmentLocator = legacyAttachmentLocator
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try BackupProtos_FilePointer(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_FilePointer) throws {
        var backupLocator: BackupProtoFilePointerBackupLocator?
        if proto.hasBackupLocator {
            backupLocator = try BackupProtoFilePointerBackupLocator(proto.backupLocator)
        }

        var attachmentLocator: BackupProtoFilePointerAttachmentLocator?
        if proto.hasAttachmentLocator {
            attachmentLocator = try BackupProtoFilePointerAttachmentLocator(proto.attachmentLocator)
        }

        var legacyAttachmentLocator: BackupProtoFilePointerLegacyAttachmentLocator?
        if proto.hasLegacyAttachmentLocator {
            legacyAttachmentLocator = BackupProtoFilePointerLegacyAttachmentLocator(proto.legacyAttachmentLocator)
        }

        self.init(proto: proto,
                  backupLocator: backupLocator,
                  attachmentLocator: attachmentLocator,
                  legacyAttachmentLocator: legacyAttachmentLocator)
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

extension BackupProtoFilePointer {
    @objc
    public static func builder() -> BackupProtoFilePointerBuilder {
        return BackupProtoFilePointerBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoFilePointerBuilder {
        let builder = BackupProtoFilePointerBuilder()
        if let _value = backupLocator {
            builder.setBackupLocator(_value)
        }
        if let _value = attachmentLocator {
            builder.setAttachmentLocator(_value)
        }
        if let _value = legacyAttachmentLocator {
            builder.setLegacyAttachmentLocator(_value)
        }
        if let _value = key {
            builder.setKey(_value)
        }
        if let _value = contentType {
            builder.setContentType(_value)
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
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class BackupProtoFilePointerBuilder: NSObject {

    private var proto = BackupProtos_FilePointer()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBackupLocator(_ valueParam: BackupProtoFilePointerBackupLocator?) {
        guard let valueParam = valueParam else { return }
        proto.backupLocator = valueParam.proto
    }

    public func setBackupLocator(_ valueParam: BackupProtoFilePointerBackupLocator) {
        proto.backupLocator = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setAttachmentLocator(_ valueParam: BackupProtoFilePointerAttachmentLocator?) {
        guard let valueParam = valueParam else { return }
        proto.attachmentLocator = valueParam.proto
    }

    public func setAttachmentLocator(_ valueParam: BackupProtoFilePointerAttachmentLocator) {
        proto.attachmentLocator = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setLegacyAttachmentLocator(_ valueParam: BackupProtoFilePointerLegacyAttachmentLocator?) {
        guard let valueParam = valueParam else { return }
        proto.legacyAttachmentLocator = valueParam.proto
    }

    public func setLegacyAttachmentLocator(_ valueParam: BackupProtoFilePointerLegacyAttachmentLocator) {
        proto.legacyAttachmentLocator = valueParam.proto
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
    public func setContentType(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.contentType = valueParam
    }

    public func setContentType(_ valueParam: String) {
        proto.contentType = valueParam
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

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoFilePointer {
        return try BackupProtoFilePointer(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try BackupProtoFilePointer(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension BackupProtoFilePointer {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension BackupProtoFilePointerBuilder {
    @objc
    public func buildIgnoringErrors() -> BackupProtoFilePointer? {
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoQuoteQuotedAttachment

@objc
public class BackupProtoQuoteQuotedAttachment: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Quote.QuotedAttachment

    @objc
    public let thumbnail: BackupProtoFilePointer?

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
                 thumbnail: BackupProtoFilePointer?) {
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
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Quote.QuotedAttachment) throws {
        var thumbnail: BackupProtoFilePointer?
        if proto.hasThumbnail {
            thumbnail = try BackupProtoFilePointer(proto.thumbnail)
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
    public func setThumbnail(_ valueParam: BackupProtoFilePointer?) {
        guard let valueParam = valueParam else { return }
        proto.thumbnail = valueParam.proto
    }

    public func setThumbnail(_ valueParam: BackupProtoFilePointer) {
        proto.thumbnail = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> BackupProtoQuoteQuotedAttachment {
        return try BackupProtoQuoteQuotedAttachment(proto)
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
        return try! self.build()
    }
}

#endif

// MARK: - BackupProtoQuoteType

@objc
public enum BackupProtoQuoteType: Int32 {
    case unknown = 0
    case normal = 1
    case giftbadge = 2
}

private func BackupProtoQuoteTypeWrap(_ value: BackupProtos_Quote.TypeEnum) -> BackupProtoQuoteType {
    switch value {
    case .unknown: return .unknown
    case .normal: return .normal
    case .giftbadge: return .giftbadge
    }
}

private func BackupProtoQuoteTypeUnwrap(_ value: BackupProtoQuoteType) -> BackupProtos_Quote.TypeEnum {
    switch value {
    case .unknown: return .unknown
    case .normal: return .normal
    case .giftbadge: return .giftbadge
    }
}

// MARK: - BackupProtoQuote

@objc
public class BackupProtoQuote: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: BackupProtos_Quote

    @objc
    public let authorID: UInt64

    @objc
    public let attachments: [BackupProtoQuoteQuotedAttachment]

    @objc
    public let bodyRanges: [BackupProtoBodyRange]

    @objc
    public var targetSentTimestamp: UInt64 {
        return proto.targetSentTimestamp
    }
    @objc
    public var hasTargetSentTimestamp: Bool {
        return proto.hasTargetSentTimestamp
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
                 authorID: UInt64,
                 attachments: [BackupProtoQuoteQuotedAttachment],
                 bodyRanges: [BackupProtoBodyRange]) {
        self.proto = proto
        self.authorID = authorID
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
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: BackupProtos_Quote) throws {
        guard proto.hasAuthorID else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: authorID")
        }
        let authorID = proto.authorID

        var attachments: [BackupProtoQuoteQuotedAttachment] = []
        attachments = try proto.attachments.map { try BackupProtoQuoteQuotedAttachment($0) }

        var bodyRanges: [BackupProtoBodyRange] = []
        bodyRanges = proto.bodyRanges.map { BackupProtoBodyRange($0) }

        self.init(proto: proto,
                  authorID: authorID,
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
    public static func builder(authorID: UInt64) -> BackupProtoQuoteBuilder {
        return BackupProtoQuoteBuilder(authorID: authorID)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoQuoteBuilder {
        let builder = BackupProtoQuoteBuilder(authorID: authorID)
        if hasTargetSentTimestamp {
            builder.setTargetSentTimestamp(targetSentTimestamp)
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
    fileprivate init(authorID: UInt64) {
        super.init()

        setAuthorID(authorID)
    }

    @objc
    public func setTargetSentTimestamp(_ valueParam: UInt64) {
        proto.targetSentTimestamp = valueParam
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
        return try BackupProtoQuote(proto)
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
        return try! self.build()
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
    public var mentionAci: Data? {
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
    public func setMentionAci(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.mentionAci = valueParam
    }

    public func setMentionAci(_ valueParam: Data) {
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
    case unknown = 0
    case incomingAudioCall = 1
    case incomingVideoCall = 2
    case outgoingAudioCall = 3
    case outgoingVideoCall = 4
    case missedAudioCall = 5
    case missedVideoCall = 6
}

private func BackupProtoCallMessageTypeWrap(_ value: BackupProtos_CallMessage.TypeEnum) -> BackupProtoCallMessageType {
    switch value {
    case .unknown: return .unknown
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
    case .unknown: return .unknown
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
    public let startedCallAci: Data

    @objc
    public let startedCallTimestamp: UInt64

    @objc
    public var inCallAcis: [Data] {
        return proto.inCallAcis
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_GroupCallMessage,
                 startedCallAci: Data,
                 startedCallTimestamp: UInt64) {
        self.proto = proto
        self.startedCallAci = startedCallAci
        self.startedCallTimestamp = startedCallTimestamp
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
        guard proto.hasStartedCallAci else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: startedCallAci")
        }
        let startedCallAci = proto.startedCallAci

        guard proto.hasStartedCallTimestamp else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: startedCallTimestamp")
        }
        let startedCallTimestamp = proto.startedCallTimestamp

        self.init(proto: proto,
                  startedCallAci: startedCallAci,
                  startedCallTimestamp: startedCallTimestamp)
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
    public static func builder(startedCallAci: Data, startedCallTimestamp: UInt64) -> BackupProtoGroupCallMessageBuilder {
        return BackupProtoGroupCallMessageBuilder(startedCallAci: startedCallAci, startedCallTimestamp: startedCallTimestamp)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoGroupCallMessageBuilder {
        let builder = BackupProtoGroupCallMessageBuilder(startedCallAci: startedCallAci, startedCallTimestamp: startedCallTimestamp)
        builder.setInCallAcis(inCallAcis)
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
    fileprivate init(startedCallAci: Data, startedCallTimestamp: UInt64) {
        super.init()

        setStartedCallAci(startedCallAci)
        setStartedCallTimestamp(startedCallTimestamp)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setStartedCallAci(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.startedCallAci = valueParam
    }

    public func setStartedCallAci(_ valueParam: Data) {
        proto.startedCallAci = valueParam
    }

    @objc
    public func setStartedCallTimestamp(_ valueParam: UInt64) {
        proto.startedCallTimestamp = valueParam
    }

    @objc
    public func addInCallAcis(_ valueParam: Data) {
        proto.inCallAcis.append(valueParam)
    }

    @objc
    public func setInCallAcis(_ wrappedItems: [Data]) {
        proto.inCallAcis = wrappedItems
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
    case unknown = 0
    case joinedSignal = 1
    case identityUpdate = 2
    case identityVerified = 3
    case identityDefault = 4
    case changeNumber = 5
    case boostRequest = 6
    case endSession = 7
    case chatSessionRefresh = 8
    case badDecrypt = 9
    case paymentsActivated = 10
    case paymentActivationRequest = 11
}

private func BackupProtoSimpleUpdateTypeWrap(_ value: BackupProtos_SimpleUpdate.TypeEnum) -> BackupProtoSimpleUpdateType {
    switch value {
    case .unknown: return .unknown
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
    case .unknown: return .unknown
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

    public var type: BackupProtoSimpleUpdateType? {
        guard hasType else {
            return nil
        }
        return BackupProtoSimpleUpdateTypeWrap(proto.type)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedType: BackupProtoSimpleUpdateType {
        if !hasType {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: SimpleUpdate.type.")
        }
        return BackupProtoSimpleUpdateTypeWrap(proto.type)
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
public class BackupProtoSimpleUpdateBuilder: NSObject {

    private var proto = BackupProtos_SimpleUpdate()

    @objc
    fileprivate override init() {}

    @objc
    public func setType(_ valueParam: BackupProtoSimpleUpdateType) {
        proto.type = BackupProtoSimpleUpdateTypeUnwrap(valueParam)
    }

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
    public let newDescription: String

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_GroupDescriptionUpdate,
                 newDescription: String) {
        self.proto = proto
        self.newDescription = newDescription
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
        guard proto.hasNewDescription else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: newDescription")
        }
        let newDescription = proto.newDescription

        self.init(proto: proto,
                  newDescription: newDescription)
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
    public static func builder(newDescription: String) -> BackupProtoGroupDescriptionUpdateBuilder {
        return BackupProtoGroupDescriptionUpdateBuilder(newDescription: newDescription)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoGroupDescriptionUpdateBuilder {
        let builder = BackupProtoGroupDescriptionUpdateBuilder(newDescription: newDescription)
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
    fileprivate init(newDescription: String) {
        super.init()

        setNewDescription(newDescription)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setNewDescription(_ valueParam: String?) {
        guard let valueParam = valueParam else { return }
        proto.newDescription = valueParam
    }

    public func setNewDescription(_ valueParam: String) {
        proto.newDescription = valueParam
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
    public let expiresInMs: UInt32

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: BackupProtos_ExpirationTimerChange,
                 expiresInMs: UInt32) {
        self.proto = proto
        self.expiresInMs = expiresInMs
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
        guard proto.hasExpiresInMs else {
            throw BackupProtoError.invalidProtobuf(description: "\(Self.logTag()) missing required field: expiresInMs")
        }
        let expiresInMs = proto.expiresInMs

        self.init(proto: proto,
                  expiresInMs: expiresInMs)
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
    public static func builder(expiresInMs: UInt32) -> BackupProtoExpirationTimerChangeBuilder {
        return BackupProtoExpirationTimerChangeBuilder(expiresInMs: expiresInMs)
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> BackupProtoExpirationTimerChangeBuilder {
        let builder = BackupProtoExpirationTimerChangeBuilder(expiresInMs: expiresInMs)
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
    fileprivate init(expiresInMs: UInt32) {
        super.init()

        setExpiresInMs(expiresInMs)
    }

    @objc
    public func setExpiresInMs(_ valueParam: UInt32) {
        proto.expiresInMs = valueParam
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
    public let data: BackupProtoFilePointer

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
                 data: BackupProtoFilePointer,
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
        let data = try BackupProtoFilePointer(proto.data)

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
    public static func builder(data: BackupProtoFilePointer, emoji: String) -> BackupProtoStickerPackStickerBuilder {
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
    fileprivate init(data: BackupProtoFilePointer, emoji: String) {
        super.init()

        setData(data)
        setEmoji(emoji)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setData(_ valueParam: BackupProtoFilePointer?) {
        guard let valueParam = valueParam else { return }
        proto.data = valueParam.proto
    }

    public func setData(_ valueParam: BackupProtoFilePointer) {
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
