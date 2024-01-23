//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension MessageBackup {

    public typealias RawError = Swift.Error

    // MARK: - Archiving

    /// Error archiving a frame.
    ///
    /// You don't construct these directly; instead use ``ArchiveFrameError``
    /// which captures the callsite line information for logging.
    fileprivate enum ArchiveFrameErrorType {

        // MARK: Backup generation errors

        case protoSerializationError(RawError)
        case fileIOError(RawError)

        /// The object we are archiving references a recipient that should already have an id assigned
        /// from having been archived, but does not.
        /// e.g. we try to archive a message to a recipient aci, but that aci has no ``MessageBackup.RecipientId``.
        case referencedRecipientIdMissing(RecipientArchivingContext.Address)

        /// The object we are archiving references a chat that should already have an id assigned
        /// from having been archived, but does not.
        /// e.g. we try to archive a message to a thread, but that group has no ``MessageBackup.ChatId``.
        case referencedThreadIdMissing(ThreadUniqueId)

        // MARK: DB read errors

        /// An error generating the master key for a group, causing the group to be skipped.
        case groupMasterKeyError(RawError)

        /// A contact thread has an invalid or missing address information, causing the
        /// thread to be skipped.
        case contactThreadMissingAddress

        /// An incoming message has an invalid or missing author address information,
        /// causing the message to be skipped.
        case invalidIncomingMessageAuthor
        /// An outgoing message has an invalid or missing recipient address information,
        /// causing the message to be skipped.
        case invalidOutgoingMessageRecipient
        /// An quote has an invalid or missing author address information,
        /// causing the containing message to be skipped.
        case invalidQuoteAuthor

        /// A reaction has an invalid or missing author address information, causing the
        /// reaction to be skipped.
        case invalidReactionAddress

        /// A group update message with no updates actually inside it, which is invalid.
        case emptyGroupUpdate
    }

    /// Error archiving an entire category of frames; not attributable to one single frame.
    ///
    /// You don't construct these directly; instead use ``FatalArchivingError``
    /// which captures the callsite line information for logging.
    fileprivate enum FatalArchivingErrorType {
        /// Error iterating over all threads for backup purposes.
        case threadIteratorError(RawError)

        /// Some unrecognized thread was found when iterating over all threads.
        case unrecognizedThreadType

        /// Error iterating over all interactions for backup purposes.
        case interactionIteratorError(RawError)

        /// These should never happen; it means some invariant in the backup code
        /// we could not enforce with the type system was broken. Nothing was wrong with
        /// the proto or local database; its the iOS backup code that has a bug somewhere.
        case developerError(OWSAssertionError)
    }

    // MARK: - Restoring

    /// Error restoring a frame.
    ///
    /// You don't construct these directly; instead use ``RestoreFrameError``
    /// which captures the callsite line information for logging.
    fileprivate enum RestoreFrameErrorType {

        // MARK: Invalid proto contents

        /// The proto contained invalid or self-contradictory data, e.g an invalid ACI.
        case invalidProtoData(InvalidProtoDataError)

        // MARK: Restoration errors

        /// The object being restored depended on a TSThread that should have been created earlier but was not.
        /// This could be either a group or contact thread, we are restoring a frame that doesn't care (e.g. a ChatItem).
        case referencedChatThreadNotFound(ThreadUniqueId)
        /// The object being inserted depended on a TSGroupThread that should have been created earlier but was not.
        /// The overlap with referencedChatThreadNotFound is confusing, but this is for restoring group-specific metadata.
        case referencedGroupThreadNotFound(GroupId)
        case databaseInsertionFailed(RawError)

        /// These should never happen; it means some invariant we could not
        /// enforce with the type system was broken. Nothing was wrong with
        /// the proto; its the iOS code that has a bug somewhere.
        case developerError(OWSAssertionError)

        // TODO: remove once all known types are handled.
        case unimplemented
    }

    /// Sub-type for ``RestoreFrameErrorType``, specifically for errors in
    /// the backup proto.
    public enum InvalidProtoDataError {
        /// Some recipient identifier being referenced was not present earlier in the backup file.
        case recipientIdNotFound(RecipientId)
        /// Some chat identifier being referenced was not present earlier in the backup file.
        case chatIdNotFound(ChatId)

        /// Could not parse an Aci. Includes the class of the offending proto.
        case invalidAci(protoClass: Any.Type)
        /// Could not parse an Pni. Includes the class of the offending proto.
        case invalidPni(protoClass: Any.Type)
        /// Could not parse an Aci. Includes the class of the offending proto.
        case invalidServiceId(protoClass: Any.Type)
        /// Could not parse an E164. Includes the class of the offending proto.
        case invalidE164(protoClass: Any.Type)

        /// A BackupProtoContact with no aci, pni, or e164.
        case contactWithoutIdentifiers
        /// A BackupProtoRecipient with an unrecognized sub-type.
        case unrecognizedRecipientType

        /// A message must come from either an Aci or an E164.
        /// One in the backup did not.
        case incomingMessageNotFromAciOrE164
        /// Outgoing message's BackupProtoSendStatus can only be for BackupProtoContacts.
        /// One in the backup was to a group, self recipient, or something else.
        case outgoingNonContactMessageRecipient
        /// A BackupProtoSendStatus had an unregonized BackupProtoSendStatusStatus.
        case unrecognizedMessageSendStatus
        /// A BackupProtoChatItem with an unregonized item type.
        case unrecognizedChatItemType

        /// BackupProtoReaction must come from either an Aci or an E164.
        /// One in the backup did not.
        case reactionNotFromAciOrE164

        /// A BackupProtoBodyRange with a missing or unrecognized style.
        case unrecognizedBodyRangeStyle

        /// A BackupProtoGroup's gv2 master key could not be parsed by libsignal.
        case invalidGV2MasterKey

        /// A BackupProtoGroupChangeChatUpdate ChatItem with a non-group-chat chatId.
        case groupUpdateMessageInNonGroupChat
        /// A BackupProtoGroupChangeChatUpdate ChatItem without any updates!
        case emptyGroupUpdates
        /// A BackupProtoGroupSequenceOfRequestsAndCancelsUpdate where
        /// the requester is the local user, which isn't allowed.
        case sequenceOfRequestsAndCancelsWithLocalAci
        /// An unrecognized BackupProtoGroupChangeChatUpdate.
        case unrecognizedGroupUpdate
    }
}

extension MessageBackup.ArchiveFrameErrorType {

    var logString: String {
        switch self {
        case .protoSerializationError(let rawError):
            // Logging the raw error is safe; its just proto field names.
            return "Proto serialization error: \(rawError)"
        case .fileIOError(let rawError):
            // Logging the raw error is safe; we generate the file we stream
            // without user input so its filename is not risky.
            return "Output stream file i/o error \(rawError)"
        case .referencedRecipientIdMissing(let address):
            switch address {
            case .contact(let contactAddress):
                return "Referenced contact recipient id missing, "
                    + "aci:\(contactAddress.aci?.logString ?? "?") "
                    + "pni:\(contactAddress.pni?.logString ?? "?") "
                    // Rely on the log scrubber to scrub the e164.
                    + "e164:\(contactAddress.e164?.stringValue ?? "?")"
            case .group(let groupId):
                // Rely on the log scrubber to scrub the group id.
                return "Referenced group recipient id missing: \(groupId)"
            }
        case .referencedThreadIdMissing(let threadUniqueId):
            return "Referenced thread id missing: \(threadUniqueId.value)"
        case .groupMasterKeyError(let rawError):
            // Rely on the log scrubber to scrub any group ids in the error.
            return "Group master key generation error: \(rawError)"
        case .contactThreadMissingAddress:
            return "Found TSContactThread with missing/invalid contact address"
        case .invalidIncomingMessageAuthor:
            return "Found incoming message with missing/invalid author"
        case .invalidOutgoingMessageRecipient:
            return "Found outgoing message with missing/invalid recipient(s)"
        case .invalidQuoteAuthor:
            return "Found TSQuotedMessage with missing invalid author"
        case .invalidReactionAddress:
            return "Found OWSReaction with missing/invalid author"
        case .emptyGroupUpdate:
            return "Found group update TSInfoMessage with no updates"
        }
    }
}

extension MessageBackup.FatalArchivingErrorType {

    var logString: String {
        switch self {
        case .threadIteratorError(let rawError):
            return "Error enumerating all TSThreads: \(rawError)"
        case .unrecognizedThreadType:
            return "Unrecognized TSThread subclass found when iterating all TSThreads"
        case .interactionIteratorError(let rawError):
            return "Error enumerating all TSInteractions \(rawError)"
        case .developerError(let owsAssertionError):
            return "Developer error: \(owsAssertionError.description)"
        }
    }
}

extension MessageBackup.RestoreFrameErrorType {

    var logString: String {
        switch self {
        case .invalidProtoData(let invalidProtoDataError):
            switch invalidProtoDataError {
            case .recipientIdNotFound(let recipientId):
                return "Recipient id not found: \(recipientId.value)"
            case .chatIdNotFound(let chatId):
                return "Chat id not found: \(chatId.value)"
            case .invalidAci(let protoClass):
                return "Invalid aci in \(String(describing: protoClass)) proto"
            case .invalidPni(let protoClass):
                return "Invalid pni in \(String(describing: protoClass)) proto"
            case .invalidServiceId(let protoClass):
                return "Invalid service id in \(String(describing: protoClass)) proto"
            case .invalidE164(let protoClass):
                return "Invalid e164 in \(String(describing: protoClass)) proto"
            case .contactWithoutIdentifiers:
                return "Contact proto missing aci, pni and e164"
            case .unrecognizedRecipientType:
                return "Unrecognized recipient type"
            case .incomingMessageNotFromAciOrE164:
                return "Incoming message from pni (not aci or e164)"
            case .outgoingNonContactMessageRecipient:
                return "Outgoing message recipient is group, story, or other non-contact"
            case .unrecognizedMessageSendStatus:
                return "Unrecognized message send status"
            case .unrecognizedChatItemType:
                return "Unrecognized ChatItem type"
            case .reactionNotFromAciOrE164:
                return "Reaction from pni (not aci or e164)"
            case .unrecognizedBodyRangeStyle:
                return "Unrecognized body range style type"
            case .invalidGV2MasterKey:
                return "Invalid GV2 master key data"
            case .groupUpdateMessageInNonGroupChat:
                return "Group update message found in 1:1 chat"
            case .emptyGroupUpdates:
                return "Group update message with empty updates"
            case .sequenceOfRequestsAndCancelsWithLocalAci:
                return "Collapsed sequence of requests and cancels with local user's aci"
            case .unrecognizedGroupUpdate:
                return "Unrecognized group update type"
            }
        case .referencedChatThreadNotFound(let threadUniqueId):
            return "Referenced thread with id not found: \(threadUniqueId.value)"
        case .referencedGroupThreadNotFound(let groupId):
            // Rely on the log scrubber to scrub the group id.
            return "Referenced TSGroupThread with group id not found: \(groupId)"
        case .databaseInsertionFailed(let rawError):
            return "DB insertion error: \(rawError)"
        case .developerError(let owsAssertionError):
            return "Developer error: \(owsAssertionError.description)"
        case .unimplemented:
            return "UNIMPLEMENTED!"
        }
    }
}

// MARK: - Log Collapsing

internal protocol MessageBackupLoggableError {
    var typeLogString: String { get }
    var idLogString: String { get }
    var callsiteLogString: String { get }

    /// We want to collapse certain logs. Imagine a Chat is missing from a backup; we don't
    /// want to print "Chat 1234 missing" for every message in that chat, that would be thousands
    /// of log lines.
    /// Instead we collapse these similar logs together, keep a count, and log that.
    /// If this is non-nil, we do that collapsing, otherwise we log as-is.
    var collapseKey: String? { get }
}

extension MessageBackup {

    internal static func log<T: MessageBackupLoggableError>(_ errors: [T]) {
        var logAsIs = [String]()
        var collapsedLogs = OrderedDictionary<String, CollapsedErrorLog>()
        for error in errors {
            guard let collapseKey = error.collapseKey else {
                logAsIs.append(
                    error.typeLogString + " "
                    + error.idLogString + " "
                    + error.callsiteLogString
                )
                continue
            }
            var collapsedLog = collapsedLogs[collapseKey] ?? CollapsedErrorLog()
            collapsedLog.collapse(error)
            collapsedLogs.replace(key: collapseKey, value: collapsedLog)
        }

        logAsIs.forEach { Logger.error($0) }
        collapsedLogs.orderedValues.forEach { $0.log() }
    }

    fileprivate static let maxCollapsedIdLogCount = 10

    fileprivate struct CollapsedErrorLog {
        var typeLogString: String?
        var exampleCallsiteString: String?
        var errorCount: UInt = 0
        var idLogStrings: [String] = []

        mutating func collapse(_ error: MessageBackupLoggableError) {
            self.errorCount += 1
            self.typeLogString = self.typeLogString ?? error.typeLogString
            self.exampleCallsiteString = self.exampleCallsiteString ?? error.callsiteLogString
            if idLogStrings.count < MessageBackup.maxCollapsedIdLogCount {
                idLogStrings.append(error.idLogString)
            }
        }

        func log() {
            Logger.error(
                (typeLogString ?? "") + " "
                + "Repeated \(errorCount) times. "
                + "from: \(idLogStrings) "
                + "example callsite: \(exampleCallsiteString ?? "none")"
            )
        }
    }
}

extension MessageBackup {

    /// Transparent wrapper around ``ArchiveFrameErrorType`` that has custom
    /// initializers that captures file, function, line callsite info for logging (impossible with a pure enum).
    public struct ArchiveFrameError<AppIdType: MessageBackupLoggableId>: MessageBackupLoggableError {

        fileprivate let type: ArchiveFrameErrorType
        fileprivate let id: AppIdType
        fileprivate let file: StaticString
        fileprivate let function: StaticString
        fileprivate let line: UInt

        fileprivate init(
            _ id: AppIdType,
            _ type: ArchiveFrameErrorType,
            _ file: StaticString,
            _ function: StaticString,
            _ line: UInt
        ) {
            self.id = id
            self.type = type
            self.file = file
            self.function = function
            self.line = line
        }

        public var typeLogString: String {
            return "Frame Archiving Error: \(type.logString)"
        }

        public var idLogString: String {
            return "\(id.typeLogString).\(id.idLogString)"
        }

        public var callsiteLogString: String {
            return "\(file):\(function) line \(line)"
        }

        public var collapseKey: String? {
            switch type {
            case .protoSerializationError(let rawError):
                // We don't want to re-log every instance of this we see.
                // Collapse them by the raw error itself.
                return "\(rawError)"

            case .referencedRecipientIdMissing, .referencedThreadIdMissing:
                // Collapse these by the id they refer to, which is in the "type".
                return typeLogString

            case
                    .fileIOError,
                    .groupMasterKeyError,
                    .contactThreadMissingAddress,
                    .invalidIncomingMessageAuthor,
                    .invalidOutgoingMessageRecipient,
                    .invalidQuoteAuthor,
                    .invalidReactionAddress,
                    .emptyGroupUpdate:
                // Log each of these as we see them.
                return nil
            }
        }

        public static func protoSerializationError(
            _ id: AppIdType,
            _ error: RawError,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .protoSerializationError(error), file, function, line)
        }

        public static func fileIOError(
            _ id: AppIdType,
            _ error: RawError,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .fileIOError(error), file, function, line)
        }

        public static func referencedRecipientIdMissing(
            _ id: AppIdType,
            _ address: RecipientArchivingContext.Address,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .referencedRecipientIdMissing(address), file, function, line)
        }

        public static func referencedThreadIdMissing(
            _ id: AppIdType,
            _ threadId: ThreadUniqueId,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .referencedThreadIdMissing(threadId), file, function, line)
        }

        public static func groupMasterKeyError(
            _ id: AppIdType,
            _ error: RawError,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .groupMasterKeyError(error), file, function, line)
        }

        public static func contactThreadMissingAddress(
            _ id: AppIdType,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .contactThreadMissingAddress, file, function, line)
        }

        public static func invalidIncomingMessageAuthor(
            _ id: AppIdType,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .invalidIncomingMessageAuthor, file, function, line)
        }

        public static func invalidOutgoingMessageRecipient(
            _ id: AppIdType,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .invalidOutgoingMessageRecipient, file, function, line)
        }

        public static func invalidQuoteAuthor(
            _ id: AppIdType,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .invalidQuoteAuthor, file, function, line)
        }

        public static func invalidReactionAddress(
            _ id: AppIdType,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .invalidReactionAddress, file, function, line)
        }

        public static func emptyGroupUpdate(
            _ id: AppIdType,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .emptyGroupUpdate, file, function, line)
        }
    }

    /// Transparent wrapper around ``FatalArchivingErrorType`` that has custom
    /// initializers that captures file, function, line callsite info for logging (impossible with a pure enum).
    public struct FatalArchivingError: MessageBackupLoggableError {

        fileprivate let type: FatalArchivingErrorType
        fileprivate let file: StaticString
        fileprivate let function: StaticString
        fileprivate let line: UInt

        fileprivate init(
            _ type: FatalArchivingErrorType,
            _ file: StaticString,
            _ function: StaticString,
            _ line: UInt
        ) {
            self.type = type
            self.file = file
            self.function = function
            self.line = line
        }

        public var typeLogString: String {
            return "Fatal Archiving Error: \(type.logString)"
        }

        public var idLogString: String {
            return ""
        }

        public var callsiteLogString: String {
            return "\(file):\(function) line \(line)"
        }

        public var collapseKey: String? {
            // Log each of these as we see them.
            return nil
        }

        public static func threadIteratorError(
            _ error: RawError,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(.threadIteratorError(error), file, function, line)
        }

        public static func unrecognizedThreadType(
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(.unrecognizedThreadType, file, function, line)
        }

        public static func interactionIteratorError(
            _ error: RawError,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(.interactionIteratorError(error), file, function, line)
        }

        public static func developerError(
            _ error: OWSAssertionError,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(.developerError(error), file, function, line)
        }
    }

    /// Transparent wrapper around ``RestoreFrameErrorType`` that has custom
    /// initializers that captures file, function, line callsite info for logging (impossible with a pure enum).
    public struct RestoreFrameError<ProtoIdType: MessageBackupLoggableId>: MessageBackupLoggableError {

        fileprivate let type: RestoreFrameErrorType
        fileprivate let id: ProtoIdType
        fileprivate let file: StaticString
        fileprivate let function: StaticString
        fileprivate let line: UInt

        fileprivate init(
            _ id: ProtoIdType,
            _ type: RestoreFrameErrorType,
            _ file: StaticString,
            _ function: StaticString,
            _ line: UInt
        ) {
            self.id = id
            self.type = type
            self.file = file
            self.function = function
            self.line = line
        }

        public var typeLogString: String {
            return "Frame Restoring Error: \(type.logString)"
        }

        public var idLogString: String {
            return "\(id.typeLogString).\(id.idLogString)"
        }

        public var callsiteLogString: String {
            return "\(file):\(function) line \(line)"
        }

        public var collapseKey: String? {
            switch type {
            case .invalidProtoData(let invalidProtoDataError):
                switch invalidProtoDataError {
                case .recipientIdNotFound, .chatIdNotFound:
                    // Collapse these by the id they refer to, which is in the "type".
                    return typeLogString
                case
                        .invalidAci,
                        .invalidPni,
                        .invalidServiceId,
                        .invalidE164,
                        .contactWithoutIdentifiers,
                        .unrecognizedRecipientType,
                        .incomingMessageNotFromAciOrE164,
                        .outgoingNonContactMessageRecipient,
                        .unrecognizedMessageSendStatus,
                        .unrecognizedChatItemType,
                        .reactionNotFromAciOrE164,
                        .unrecognizedBodyRangeStyle,
                        .invalidGV2MasterKey,
                        .groupUpdateMessageInNonGroupChat,
                        .emptyGroupUpdates,
                        .sequenceOfRequestsAndCancelsWithLocalAci,
                        .unrecognizedGroupUpdate:
                    // Collapse these by the id of the containing frame.
                    return idLogString
                }
            case .referencedChatThreadNotFound, .referencedGroupThreadNotFound:
                // Collapse these by the id they refer to, which is in the "type".
                return typeLogString
            case .databaseInsertionFailed(let rawError):
                // We don't want to re-log every instance of this we see if they repeat.
                // Collapse them by the raw error itself.
                return "\(rawError)"
            case .developerError:
                // Log each of these as we see them.
                return nil
            case .unimplemented:
                // Collapse these by the callsite.
                return callsiteLogString
            }
        }

        public static func invalidProtoData(
            _ id: ProtoIdType,
            _ error: InvalidProtoDataError,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .invalidProtoData(error), file, function, line)
        }

        public static func referencedChatThreadNotFound(
            _ id: ProtoIdType,
            _ threadId: ThreadUniqueId,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .referencedChatThreadNotFound(threadId), file, function, line)
        }

        public static func referencedGroupThreadNotFound(
            _ id: ProtoIdType,
            _ groupId: GroupId,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .referencedGroupThreadNotFound(groupId), file, function, line)
        }

        public static func databaseInsertionFailed(
            _ id: ProtoIdType,
            _ error: RawError,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .databaseInsertionFailed(error), file, function, line)
        }

        public static func developerError(
            _ id: ProtoIdType,
            _ error: OWSAssertionError,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .developerError(error), file, function, line)
        }

        public static func unimplemented(
            _ id: ProtoIdType,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> Self {
            return .init(id, .unimplemented, file, function, line)
        }
    }
}
