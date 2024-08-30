//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {

    public typealias RawError = Swift.Error

    // MARK: - Archiving

    /// Error while archiving a single frame.
    public struct ArchiveFrameError<AppIdType: MessageBackupLoggableId>: MessageBackupLoggableError {
        public enum ErrorType {
            /// An error occurred serializing the proto.
            /// - Note
            /// Logging the raw error is safe, as it'll just contain proto field
            /// names.
            case protoSerializationError(RawError)
            /// An error occurred during file IO.
            /// - Note
            /// Logging the raw error is safe, as we generate the file we stream
            /// without user input.
            case fileIOError(RawError)

            /// The object we are archiving references a recipient that should already have an id assigned
            /// from having been archived, but does not.
            /// e.g. we try to archive a message to a recipient aci, but that aci has no ``MessageBackup.RecipientId``.
            case referencedRecipientIdMissing(RecipientArchivingContext.Address)

            /// The object we are archiving references a chat that should already have an id assigned
            /// from having been archived, but does not.
            /// e.g. we try to archive a message to a thread, but that group has no ``MessageBackup.ChatId``.
            case referencedThreadIdMissing(ThreadUniqueId)

            /// An error generating the master key for a group, causing the group to be skipped.
            case groupMasterKeyError(RawError)

            /// A contact thread has an invalid or missing address information, causing the
            /// thread to be skipped.
            case contactThreadMissingAddress

            /// Custom chat colors should never have light/dark theme. The UI
            /// disallows it and the proto cannot represent it.
            case themedCustomChatColor

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

            /// The profile for the local user is missing.
            case missingLocalProfile
            /// The profile key for the local user is missing.
            case missingLocalProfileKey

            /// Parameters required to archive a GV2 group member are missing
            case missingRequiredGroupMemberParams

            /// A group call record had an invalid individual-call status.
            case groupCallRecordHadIndividualCallStatus

            /// A distributionListIdentifier memberRecipientId was invalid
            case invalidDistributionListMemberAddress
            /// The story distribution list contained memberRecipientIds for a privacy mode
            /// that didn't expect any.
            case distributionListUnexpectedRecipients
            /// The story distribution list was marked as deleted but missing a deletion timestamp
            case distributionListMissingDeletionTimestamp
            /// The story distribution list was missing memberRecipiendIds for a privacy mode
            /// where they should be present.
            case distributionListMissingRecipients

            /// An interaction used to create a verification-state update was
            /// missing info as to its author.
            case verificationStateUpdateInteractionMissingAuthor
            /// An interaction used to create a phone number change was missing
            /// info as to its author.
            case phoneNumberChangeInteractionMissingAuthor
            /// An interaction used to create a payment activation request was
            /// missing info as to its author.
            case paymentActivationRequestInteractionMissingAuthor
            /// An interaction used to create a payments-activated request was
            /// missing info as to its author.
            case paymentsActivatedInteractionMissingAuthor
            /// An interaction used to create an identity-key change was missing
            /// info as to its author.
            case identityKeyChangeInteractionMissingAuthor
            /// An interaction used to create a session-refresh update was
            /// missing info as to its author.
            case sessionRefreshInteractionMissingAuthor
            /// An interaction used to create a decryption error update was
            /// missing info as to its author.
            case decryptionErrorInteractionMissingAuthor
            /// We found a non-simple chat update type when expecting a simple
            /// chat update.
            case foundComplexChatUpdateTypeWhenExpectingSimple
            /// A "verification state change" info message was not of the
            /// expected SDS record type, ``OWSVerificationStateChangeMessage``.
            case verificationStateChangeNotExpectedSDSRecordType
            /// An "unknown protocol version" info message was not of the
            /// expected SDS record type, ``OWSUnknownProtocolVersionMessage``.
            case unknownProtocolVersionNotExpectedSDSRecordType
            /// A simple chat update message that was expected to be in a 1:1
            /// thread was not, in fact, in a 1:1 thread.
            case simpleChatUpdateMessageNotInContactThread

            /// The payment message was missing required additional payment information.
            case missingPaymentInformation

            /// A "disappearing message config update" info message was not of
            /// the expected SDS record type, ``OWSDisappearingConfigurationUpdateInfoMessage``.
            case disappearingMessageConfigUpdateNotExpectedSDSRecordType
            /// An ``OWSDisappearingConfigurationUpdateInfoMessage`` info
            /// message was unexpectedly found in a non-contact thread.
            /// - Note
            /// Disappearing message timer updates for groups are handled by
            /// "group update metadata" on ``TSInfoMessage``s.
            case disappearingMessageConfigUpdateNotInContactThread
            /// An ``OWSDisappearingConfigurationUpdateInfoMessage`` info
            /// message was unexpectedly missing author info.
            case disappearingMessageConfigUpdateMissingAuthor

            /// A "profile change update" info message was missing author info.
            case profileChangeUpdateMissingAuthor
            /// A "profile change update" info message was missing the before or
            /// after profile name.
            case profileChangeUpdateMissingNames

            /// A "thread merge update" info message was missing info as to the
            /// contact whose threads were merged.
            case threadMergeUpdateMissingAuthor

            /// A "session switchover update" info message was missing info as
            /// to the switched-over-from session.
            case sessionSwitchoverUpdateMissingAuthor

            /// A "learned profile update" info message was missing the display
            /// name from before we learned the profile.
            case learnedProfileUpdateMissingPreviousName
            /// A "learned profile update" info message contained an invalid
            /// E164 as its "previous name".
            case learnedProfileUpdateInvalidE164
            /// A "learned profile update" info message was missing info as to
            /// the profile that was learned.
            case learnedProfileUpdateMissingAuthor

            /// We failed to fetch the edit history for a message.
            case editHistoryFailedToFetch
        }

        private let type: ErrorType
        private let id: AppIdType
        private let file: StaticString
        private let function: StaticString
        private let line: UInt

        /// Create a new error instance.
        ///
        /// Exposed as a static method rather than an initializer to help
        /// callsites have some context without needing to put the exhaustive
        /// (namespaced) type name at each site.
        public static func archiveFrameError(
            _ type: ErrorType,
            _ id: AppIdType,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> ArchiveFrameError {
            return ArchiveFrameError(type: type, id: id, file: file, function: function, line: line)
        }

        // MARK: MessageBackupLoggableError

        public var typeLogString: String {
            return "ArchiveFrameError: \(String(describing: type))"
        }

        public var idLogString: String {
            return "\(id.typeLogString).\(id.idLogString)"
        }

        public var callsiteLogString: String {
            return "\(file):\(function):\(line)"
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
                    .distributionListMissingDeletionTimestamp,
                    .distributionListMissingRecipients,
                    .distributionListUnexpectedRecipients,
                    .fileIOError,
                    .groupMasterKeyError,
                    .contactThreadMissingAddress,
                    .themedCustomChatColor,
                    .invalidDistributionListMemberAddress,
                    .invalidIncomingMessageAuthor,
                    .invalidOutgoingMessageRecipient,
                    .invalidQuoteAuthor,
                    .invalidReactionAddress,
                    .emptyGroupUpdate,
                    .missingLocalProfile,
                    .missingLocalProfileKey,
                    .missingRequiredGroupMemberParams,
                    .groupCallRecordHadIndividualCallStatus,
                    .verificationStateUpdateInteractionMissingAuthor,
                    .phoneNumberChangeInteractionMissingAuthor,
                    .identityKeyChangeInteractionMissingAuthor,
                    .sessionRefreshInteractionMissingAuthor,
                    .decryptionErrorInteractionMissingAuthor,
                    .paymentActivationRequestInteractionMissingAuthor,
                    .paymentsActivatedInteractionMissingAuthor,
                    .foundComplexChatUpdateTypeWhenExpectingSimple,
                    .verificationStateChangeNotExpectedSDSRecordType,
                    .unknownProtocolVersionNotExpectedSDSRecordType,
                    .simpleChatUpdateMessageNotInContactThread,
                    .missingPaymentInformation,
                    .disappearingMessageConfigUpdateNotExpectedSDSRecordType,
                    .disappearingMessageConfigUpdateNotInContactThread,
                    .disappearingMessageConfigUpdateMissingAuthor,
                    .profileChangeUpdateMissingAuthor,
                    .profileChangeUpdateMissingNames,
                    .threadMergeUpdateMissingAuthor,
                    .sessionSwitchoverUpdateMissingAuthor,
                    .learnedProfileUpdateMissingPreviousName,
                    .learnedProfileUpdateInvalidE164,
                    .learnedProfileUpdateMissingAuthor,
                    .editHistoryFailedToFetch:
                // Log any others as we see them.
                return nil
            }
        }
    }

    /// Error archiving an entire category of frames; not attributable to a
    /// single frame.
    public struct FatalArchivingError: MessageBackupLoggableError {
        public enum ErrorType {
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

        private let type: ErrorType
        private let file: StaticString
        private let function: StaticString
        private let line: UInt

        /// Create a new error instance.
        ///
        /// Exposed as a static method rather than an initializer to help
        /// callsites have some context without needing to put the exhaustive
        /// (namespaced) type name at each site.
        public static func fatalArchiveError(
            _ type: ErrorType,
            _ file: StaticString = #file,
            _ function: StaticString = #function,
            _ line: UInt = #line
        ) -> FatalArchivingError {
            return FatalArchivingError(type: type, file: file, function: function, line: line)
        }

        // MARK: MessageBackupLoggableError

        public var typeLogString: String {
            return "FatalArchiveError: \(String(describing: type))"
        }

        public var idLogString: String {
            return ""
        }

        public var callsiteLogString: String {
            return "\(file):\(function):\(line)"
        }

        public var collapseKey: String? {
            // Log each of these as we see them.
            return nil
        }
    }

    /// Error restoring a frame.
    public struct RestoreFrameError<ProtoIdType: MessageBackupLoggableId>: MessageBackupLoggableError {
        public enum ErrorType {
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
                /// Could not parse an ``Aes256Key`` profile key. Includes the class
                /// of the offending proto.
                case invalidProfileKey(protoClass: Any.Type)
                /// An invalid member (group, distribution list, etc) was specified as a distribution list member.  Includes the offending proto
                case invalidDistributionListMember(protoClass: Any.Type)

                /// A ``BackupProto/Recipient`` with a missing destination.
                case recipientMissingDestination

                /// A ``BackupProto/Contact`` with no aci, pni, or e164.
                case contactWithoutIdentifiers
                /// A ``BackupProto/Contact`` for the local user. This shouldn't exist.
                case otherContactWithLocalIdentifiers
                /// A ``BackupProto/Contact`` missing info as to whether or not
                /// it is registered.
                case contactWithoutRegistrationInfo

                /// A ``BackupProto_ChatStyle/CustomChatColor`` had an unrecognized color oneof.
                case unrecognizedCustomChatStyleColor
                /// A ``BackupProto_ChatStyle/Gradient`` had less than two colors.
                case chatStyleGradientSingleOrNoColors

                /// A ``BackupProto/ChatItem`` was missing directional details.
                case chatItemMissingDirectionalDetails
                /// A ``BackupProto/ChatItem`` was missing its actual item.
                case chatItemMissingItem
                /// A directionless chat item was not an update message.
                case directionlessChatItemNotUpdateMessage
                /// A ``BackupProto/ChatItem`` has a missing or invalid dateSent.
                case chatItemInvalidDateSent

                /// A message must come from either an Aci or an E164.
                /// One in the backup did not.
                case incomingMessageNotFromAciOrE164
                /// Outgoing message's `BackupProto_SendStatus` can only be for `BackupProto_Contacts`.
                /// One in the backup was to a group, self recipient, or something else.
                case outgoingNonContactMessageRecipient
                /// A `BackupProto_SendStatus` had an unregonized `BackupProto_SendStatusStatus`.
                case unrecognizedMessageSendStatus

                /// `BackupProto_Reaction` must come from either an Aci or an E164.
                /// One in the backup did not.
                case reactionNotFromAciOrE164

                /// A ``BackupProto_StandardMessage`` had neither body text nor any attachments.
                case emptyStandardMessage

                /// A ``BackupProto_StandardMessage/longText`` was present despite an empty
                /// message body (the body text must always be a prefix of the long text)
                case longTextStandardMessageMissingBody

                /// A `BackupProto_BodyRange` with a missing or unrecognized style.
                case unrecognizedBodyRangeStyle

                /// A quoted message had no body, attachment, gift badge, or other
                /// content in its representation of the original being quoted.
                case quotedMessageEmptyContent

                /// A link preview with an empty string for the url
                case linkPreviewEmptyUrl
                /// Link preview urls must be present in the message body;
                /// this error is for when they are not.
                case linkPreviewUrlNotInBody

                /// A ``BackupProto_ContactMessage/contact`` had 0 or multiple values.
                case contactMessageNonSingularContactAttachmentCount
                /// A ``BackupProto_ContactAttachment/Phone/value`` was missing or empty.
                case contactAttachmentPhoneNumberMissingValue
                /// A ``BackupProto_ContactAttachment/Phone/type`` was unknown.
                case contactAttachmentPhoneNumberUnknownType
                /// A ``BackupProto_ContactAttachment/Email/value`` was missing or empty.
                case contactAttachmentEmailMissingValue
                /// A ``BackupProto_ContactAttachment/Email/type`` was unknown.
                case contactAttachmentEmailUnknownType
                /// A ``BackupProto_ContactAttachment/PostalAddress`` with all empty fields;
                /// at least some field has to be nonempty to be a valid address.
                case contactAttachmentEmptyAddress
                /// A ``BackupProto_ContactAttachment/PostalAddress/type`` was unknown.
                case contactAttachmentAddressUnknownType

                /// A `BackupProto_Group's` gv2 master key could not be parsed by libsignal.
                case invalidGV2MasterKey
                /// A `BackupProto_Group` was missing its group snapshot.
                case missingGV2GroupSnapshot
                /// A ``BackupProtoGroup/BackupProtoFullGroupMember/role`` was
                /// unrecognized. Includes the class of the offending proto.
                case unrecognizedGV2MemberRole(protoClass: Any.Type)
                /// A ``BackupProtoGroup/BackupProtoMemberPendingProfileKey`` was
                /// missing its member details.
                case invitedGV2MemberMissingMemberDetails
                /// We failed to build a V2 group model while restoring a group.
                case failedToBuildGV2GroupModel

                /// A `BackupProto_GroupChangeChatUpdate` ChatItem with a non-group-chat chatId.
                case groupUpdateMessageInNonGroupChat
                /// A `BackupProto_GroupChangeChatUpdate` ChatItem without any updates!
                case emptyGroupUpdates
                /// A `BackupProto_GroupSequenceOfRequestsAndCancelsUpdate` where
                /// the requester is the local user, which isn't allowed.
                case sequenceOfRequestsAndCancelsWithLocalAci
                /// An unrecognized `BackupProto_GroupChangeChatUpdate`.
                case unrecognizedGroupUpdate

                /// A frame was entirely missing its enclosed item.
                case frameMissingItem

                /// A profile key for the local user that could not be parsed into a valid aes256 key
                case invalidLocalProfileKey
                /// A profile key for the local user that could not be parsed into a valid aes256 key
                case invalidLocalUsernameLink

                /// A `BackupProto_IndividualCall` chat item update was associated
                /// with a thread that was not a contact thread.
                case individualCallNotInContactThread
                /// A `BackupProto_IndividualCall` had an unrecognized type.
                case individualCallUnrecognizedType
                /// A `BackupProto_IndividualCall` had an unrecognized direction.
                case individualCallUnrecognizedDirection
                /// A `BackupProto_IndividualCall` had an unrecognized state.
                case individualCallUnrecognizedState

                /// A `BackupProto_GroupCall` chat item update was associated with
                /// a thread that was not a group thread.
                case groupCallNotInGroupThread
                /// A `BackupProto_GroupCall` had an unrecognized state.
                case groupCallUnrecognizedState
                /// A `BackupProto_GroupCall` referenced a recipient that was not
                /// a contact or otherwise did not contain an ACI.
                case groupCallRecipientIdNotAnAci(RecipientId)

                /// `BackupProto_DistributionListItem` was missing its item
                case distributionListItemMissingItem
                /// `BackupProto_DistributionList.distributionId` was not a valid UUID
                case invalidDistributionListId
                /// `BackupProto_DistributionList.privacyMode` was missing, or contained an unknown privacy mode
                case invalidDistributionListPrivacyMode
                /// The specified `BackupProto_DistributionList.privacyMode` was missing a list of associated member IDs
                case invalidDistributionListPrivacyModeMissingRequiredMembers
                /// `BackupProto_DistributionListItem.deletionTimestamp` was invalid
                case invalidDistributionListDeletionTimestamp

                /// A ``BackupProto/ChatUpdateMessage/update`` was empty.
                case emptyChatUpdateMessage
                /// A ``BackupProto/SimpleChatUpdate/type`` was unrecognized.
                case unrecognizedSimpleChatUpdate
                /// A "verification state change" simple chat update was
                /// associated with a non-contact recipient.
                case verificationStateChangeNotFromContact
                /// A "phone number chnaged" simple chat update was associated
                /// with a non-contact recipient.
                case phoneNumberChangeNotFromContact
                /// An "identity key changed" simple chat update was associated
                /// with a non-contact recipient.
                case identityKeyChangeNotFromContact
                /// A "decryption error" simple chat update was associated with
                /// a non-contact recipient.
                case decryptionErrorNotFromContact
                /// A "payments activation request" simple chat update was
                /// associated with a recipient with no ACI.
                case paymentsActivationRequestNotFromAci
                /// A "payments activated" simple chat update was associated
                /// with a recipient with no ACI.
                case paymentsActivatedNotFromAci
                /// An "unsupported protocol version" simple chat update was
                /// associated with a recipient with no ACI.
                case unsupportedProtocolVersionNotFromAci

                /// An ArchivedPayment was unable to be crated from the
                /// restored payment information.
                case unrecognizedPaymentTransaction

                /// An "expiration timer update" was in a non-contact thread.
                /// - Note
                /// Expiration timer updates for group threads are handled via
                /// a separate "group expiration timer update" proto.
                case expirationTimerUpdateNotInContactThread
                /// An "expiration timer update" contained an expiration timer
                /// that overflowed the local type for timer updates.
                case expirationTimerUpdateOverflowedLocalType

                /// A "profile change update" contained invalid before/after
                /// profile names.
                case profileChangeUpdateInvalidNames
                /// A "profile change update" was not authored by a contact.
                case profileChangeUpdateNotFromContact

                /// A "thread merge update" was not authored by a contact.
                case threadMergeUpdateNotFromContact

                /// A "session switchover update" was not authored by a contact.
                case sessionSwitchoverUpdateNotFromContact

                /// A "learned profile update" was missing its previous name.
                case learnedProfileUpdateMissingPreviousName
                /// A "learned profile update" was not authored by a contact.
                case learnedProfileUpdateNotFromContact

                /// An incoming message, or a revision for an incoming message,
                /// were missing incoming details. (Revisions must have the same
                /// directionality as their parent.)
                case revisionOfIncomingMessageMissingIncomingDetails

                /// An outgoing message, or a revision for an outgoing message,
                /// were missing outgoing details. (Revisions must have the same
                /// directionality as their parent.)
                case revisionOfOutgoingMessageMissingOutgoingDetails

                /// A ``BackupProto_FilePointer`` had no known ``BackupProto_FilePointer/OneOf_Locator``.
                case filePointerMissingLocator
                /// A ``BackupProto_FilePointer/AttachmentLocator`` was missing its cdn number.
                case filePointerMissingTransitCdnNumber
                /// A ``BackupProto_FilePointer/AttachmentLocator`` was missing its cdn key.
                case filePointerMissingTransitCdnKey
                /// A ``BackupProto_FilePointer/BackupLocator`` was missing its media name.
                case filePointerMissingMediaName
                /// A ``BackupProto_FilePointer/AttachmentLocator`` or a
                /// ``BackupProto_FilePointer/BackupLocator`` was missing the encryption key.
                case filePointerMissingEncryptionKey
                /// A ``BackupProto_FilePointer/AttachmentLocator`` or a
                /// ``BackupProto_FilePointer/BackupLocator`` was missing the digest.
                case filePointerMissingDigest
                /// A ``BackupProto_FilePointer/AttachmentLocator`` or a
                /// ``BackupProto_FilePointer/BackupLocator`` was missing the file size.
                case filePointerMissingSize
                /// A ``BackupProto_MessageAttachment/clientUuid`` contained an invalid UUID.
                case invalidAttachmentClientUUID

                /// A ``BackupProto_GiftBadge/state`` was unrecognized.
                case unrecognizedGiftBadgeState
            }

            /// The proto contained invalid or self-contradictory data, e.g an invalid ACI.
            case invalidProtoData(InvalidProtoDataError)

            /// The object being restored depended on a TSThread that should have been created earlier but was not.
            /// This could be either a group or contact thread, we are restoring a frame that doesn't care (e.g. a ChatItem).
            case referencedChatThreadNotFound(ThreadUniqueId)
            /// The object being inserted depended on a TSGroupThread that should have been created earlier but was not.
            /// The overlap with referencedChatThreadNotFound is confusing, but this is for restoring group-specific metadata.
            case referencedGroupThreadNotFound(GroupId)

            case databaseModelMissingRowId(modelClass: AnyClass)

            case databaseInsertionFailed(RawError)

            /// We failed to derive the "upload era" identifier for attachments from the
            /// backup subscription id. See ``Attachment/uploadEra(backupSubscriptionId:)``.
            case uploadEraDerivationFailed(RawError)

            case failedToEnqueueAttachmentDownload(RawError)

            /// We failed to properly create the attachment in the DB after restoring
            case failedToCreateAttachment

            /// These should never happen; it means some invariant we could not
            /// enforce with the type system was broken. Nothing was wrong with
            /// the proto; its the iOS code that has a bug somewhere.
            case developerError(OWSAssertionError)

            // TODO: [Backups] remove once all known types are handled.
            case unimplemented
        }

        private let type: ErrorType
        private let id: ProtoIdType
        private let file: StaticString
        private let function: StaticString
        private let line: UInt

        /// Create a new error instance.
        ///
        /// Exposed as a static method rather than an initializer to help
        /// callsites have some context without needing to put the exhaustive
        /// (namespaced) type name at each site.
        public static func restoreFrameError(
            _ type: ErrorType,
            _ id: ProtoIdType,
            file: StaticString = #file,
            function: StaticString = #function,
            line: UInt = #line
        ) -> RestoreFrameError {
            return RestoreFrameError(type: type, id: id, file: file, function: function, line: line)
        }

        public var typeLogString: String {
            return "RestoreFrameError: \(String(describing: type))"
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
                        .invalidProfileKey,
                        .invalidDistributionListMember,
                        .recipientMissingDestination,
                        .contactWithoutIdentifiers,
                        .otherContactWithLocalIdentifiers,
                        .contactWithoutRegistrationInfo,
                        .chatItemMissingDirectionalDetails,
                        .chatItemMissingItem,
                        .chatItemInvalidDateSent,
                        .unrecognizedCustomChatStyleColor,
                        .chatStyleGradientSingleOrNoColors,
                        .directionlessChatItemNotUpdateMessage,
                        .incomingMessageNotFromAciOrE164,
                        .outgoingNonContactMessageRecipient,
                        .unrecognizedMessageSendStatus,
                        .reactionNotFromAciOrE164,
                        .emptyStandardMessage,
                        .longTextStandardMessageMissingBody,
                        .unrecognizedBodyRangeStyle,
                        .quotedMessageEmptyContent,
                        .linkPreviewEmptyUrl,
                        .linkPreviewUrlNotInBody,
                        .contactMessageNonSingularContactAttachmentCount,
                        .contactAttachmentPhoneNumberMissingValue,
                        .contactAttachmentPhoneNumberUnknownType,
                        .contactAttachmentEmailMissingValue,
                        .contactAttachmentEmailUnknownType,
                        .contactAttachmentEmptyAddress,
                        .contactAttachmentAddressUnknownType,
                        .invalidGV2MasterKey,
                        .missingGV2GroupSnapshot,
                        .unrecognizedGV2MemberRole,
                        .invitedGV2MemberMissingMemberDetails,
                        .failedToBuildGV2GroupModel,
                        .groupUpdateMessageInNonGroupChat,
                        .emptyGroupUpdates,
                        .sequenceOfRequestsAndCancelsWithLocalAci,
                        .unrecognizedGroupUpdate,
                        .frameMissingItem,
                        .invalidLocalProfileKey,
                        .invalidLocalUsernameLink,
                        .individualCallNotInContactThread,
                        .individualCallUnrecognizedType,
                        .individualCallUnrecognizedDirection,
                        .individualCallUnrecognizedState,
                        .groupCallNotInGroupThread,
                        .groupCallUnrecognizedState,
                        .groupCallRecipientIdNotAnAci,
                        .distributionListItemMissingItem,
                        .invalidDistributionListId,
                        .invalidDistributionListPrivacyMode,
                        .invalidDistributionListPrivacyModeMissingRequiredMembers,
                        .invalidDistributionListDeletionTimestamp,
                        .emptyChatUpdateMessage,
                        .unrecognizedSimpleChatUpdate,
                        .verificationStateChangeNotFromContact,
                        .phoneNumberChangeNotFromContact,
                        .identityKeyChangeNotFromContact,
                        .decryptionErrorNotFromContact,
                        .paymentsActivationRequestNotFromAci,
                        .paymentsActivatedNotFromAci,
                        .unrecognizedPaymentTransaction,
                        .unsupportedProtocolVersionNotFromAci,
                        .expirationTimerUpdateNotInContactThread,
                        .expirationTimerUpdateOverflowedLocalType,
                        .profileChangeUpdateInvalidNames,
                        .profileChangeUpdateNotFromContact,
                        .threadMergeUpdateNotFromContact,
                        .sessionSwitchoverUpdateNotFromContact,
                        .learnedProfileUpdateMissingPreviousName,
                        .learnedProfileUpdateNotFromContact,
                        .revisionOfIncomingMessageMissingIncomingDetails,
                        .revisionOfOutgoingMessageMissingOutgoingDetails,
                        .filePointerMissingLocator,
                        .filePointerMissingTransitCdnNumber,
                        .filePointerMissingTransitCdnKey,
                        .filePointerMissingMediaName,
                        .filePointerMissingEncryptionKey,
                        .filePointerMissingDigest,
                        .filePointerMissingSize,
                        .invalidAttachmentClientUUID,
                        .unrecognizedGiftBadgeState:
                    // Collapse all others by the id of the containing frame.
                    return idLogString
                }
            case .referencedChatThreadNotFound, .referencedGroupThreadNotFound, .failedToCreateAttachment:
                // Collapse these by the id they refer to, which is in the "type".
                return typeLogString
            case .databaseModelMissingRowId(let modelClass):
                // Collapse these by the relevant class.
                return "\(modelClass)"
            case .databaseInsertionFailed(let rawError), .uploadEraDerivationFailed(let rawError), .failedToEnqueueAttachmentDownload(let rawError):
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

            if var existingLog = collapsedLogs[collapseKey] {
                existingLog.collapse(error)
                collapsedLogs.replace(key: collapseKey, value: existingLog)
            } else {
                var newLog = CollapsedErrorLog()
                newLog.collapse(error)
                collapsedLogs.append(key: collapseKey, value: newLog)
            }
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
