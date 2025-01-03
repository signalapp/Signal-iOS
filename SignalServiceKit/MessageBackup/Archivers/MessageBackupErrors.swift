//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftProtobuf

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

            /// The object we are archiving references a custom chat color that should already have an id assigned
            /// from having been archived, but does not.
            /// e.g. we try to archive the chat style of a thread, but there is no ``MessageBackup.CustomChatColorId``.
            case referencedCustomChatColorMissing(CustomChatColor.Key)

            /// We were unable to fetch the OWSRecipientIdentity for a recipient.
            case unableToFetchRecipientIdentity(RawError)

            /// An error generating the master key for a group, causing the group to be skipped.
            case groupMasterKeyError(RawError)

            /// A contact thread has an invalid or missing address information, causing the
            /// thread to be skipped.
            case contactThreadMissingAddress

            /// Custom chat colors should never have light/dark theme. The UI
            /// disallows it and the proto cannot represent it.
            case themedCustomChatColor
            /// An unknown type of wallpaper was found that we couldn't translate to proto,
            /// causing the wallpaper to be skipped.
            case unknownWallpaper

            /// An incoming message has an invalid or missing author address information,
            /// causing the message to be skipped.
            case invalidIncomingMessageAuthor
            /// An incoming message came from the self recipient.
            case incomingMessageFromSelf
            /// An outgoing message has an invalid or missing recipient address information,
            /// causing the message to be skipped.
            case invalidOutgoingMessageRecipient
            /// An quote has an invalid or missing author address information,
            /// causing the containing message to be skipped.
            case invalidQuoteAuthor

            /// A link preview is missing its url
            case linkPreviewMissingUrl
            /// A link preview's URL isn't in the message body
            case linkPreviewUrlNotInBody

            /// A sticker message had no associated attachment for the sticker's image contents.
            case stickerMessageMissingStickerAttachment

            /// An attachment failed to be enqueued for upload, and will not be uploaded to the media tier.
            case failedToEnqueueAttachmentForUpload

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

            /// A group call record had an invalid call status.
            case groupCallRecordHadInvalidCallStatus

            /// A distribution list had no distributionId; the distribution id assigned in the error should be ignored.
            case distributionListMissingDistributionId
            /// A distribution list had ``TSThreadStoryViewMode/default``.
            case distributionListHasDefaultViewMode
            /// A custom (non-MyStory) distribution list had a ``TSThreadStoryViewMode/blocklist``.
            case customDistributionListBlocklistViewMode
            /// A distributionListIdentifier memberRecipientId was invalid
            case invalidDistributionListMemberAddress
            /// The story distribution list was marked as deleted but missing a deletion timestamp
            case distributionListMissingDeletionTimestamp

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

            /// We failed to fetch payment information for a payment message.
            case paymentInfoFetchFailed(RawError)
            /// The payment message was missing required additional payment information.
            case missingPaymentInformation

            /// A "disappearing message config update" info message was not of
            /// the expected SDS record type, ``OWSDisappearingConfigurationUpdateInfoMessage``.
            case disappearingMessageConfigUpdateNotExpectedSDSRecordType
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

            /// We failed to read the ``StoryContextAssociatedData``. Note that it can
            /// be nil (missing); this is a SQL error when we tried to read.
            case unableToReadStoryContextAssociatedData(Error)

            /// An unviewed view-once message is missing its attachment.
            case unviewedViewOnceMessageMissingAttachment
            /// An unviewed view-once message has more than one attachment.
            /// Associated value provides the number of attachments.
            case unviewedViewOnceMessageTooManyAttachments(Int)

            /// Restrictions for a call link are unknown.
            case callLinkRestrictionsUnknown

            /// An ad hoc call's ``CallRecord/conversationId`` is not a
            /// call link, which is illegal.
            case adHocCallDoesNotHaveCallLinkAsConversationId
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
            switch type {
            case .distributionListMissingDistributionId:
                return "\(id.typeLogString).{ID missing}"
            default:
                return "\(id.typeLogString).\(id.idLogString)"
            }
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
            case .referencedRecipientIdMissing, .referencedThreadIdMissing, .referencedCustomChatColorMissing:
                // Collapse these by the id they refer to, which is in the "type".
                return idLogString
            case
                    .fileIOError,
                    .groupMasterKeyError,
                    .contactThreadMissingAddress,
                    .themedCustomChatColor,
                    .unknownWallpaper,
                    .unableToFetchRecipientIdentity,
                    .distributionListMissingDistributionId,
                    .distributionListHasDefaultViewMode,
                    .customDistributionListBlocklistViewMode,
                    .distributionListMissingDeletionTimestamp,
                    .invalidDistributionListMemberAddress,
                    .invalidIncomingMessageAuthor,
                    .incomingMessageFromSelf,
                    .invalidOutgoingMessageRecipient,
                    .invalidQuoteAuthor,
                    .linkPreviewMissingUrl,
                    .linkPreviewUrlNotInBody,
                    .stickerMessageMissingStickerAttachment,
                    .failedToEnqueueAttachmentForUpload,
                    .invalidReactionAddress,
                    .emptyGroupUpdate,
                    .missingLocalProfile,
                    .missingLocalProfileKey,
                    .missingRequiredGroupMemberParams,
                    .groupCallRecordHadInvalidCallStatus,
                    .verificationStateUpdateInteractionMissingAuthor,
                    .phoneNumberChangeInteractionMissingAuthor,
                    .identityKeyChangeInteractionMissingAuthor,
                    .decryptionErrorInteractionMissingAuthor,
                    .paymentActivationRequestInteractionMissingAuthor,
                    .paymentsActivatedInteractionMissingAuthor,
                    .foundComplexChatUpdateTypeWhenExpectingSimple,
                    .verificationStateChangeNotExpectedSDSRecordType,
                    .unknownProtocolVersionNotExpectedSDSRecordType,
                    .simpleChatUpdateMessageNotInContactThread,
                    .paymentInfoFetchFailed,
                    .missingPaymentInformation,
                    .disappearingMessageConfigUpdateNotExpectedSDSRecordType,
                    .disappearingMessageConfigUpdateMissingAuthor,
                    .profileChangeUpdateMissingAuthor,
                    .profileChangeUpdateMissingNames,
                    .threadMergeUpdateMissingAuthor,
                    .sessionSwitchoverUpdateMissingAuthor,
                    .learnedProfileUpdateMissingPreviousName,
                    .learnedProfileUpdateInvalidE164,
                    .learnedProfileUpdateMissingAuthor,
                    .editHistoryFailedToFetch,
                    .unableToReadStoryContextAssociatedData,
                    .unviewedViewOnceMessageMissingAttachment,
                    .unviewedViewOnceMessageTooManyAttachments,
                    .callLinkRestrictionsUnknown,
                    .adHocCallDoesNotHaveCallLinkAsConversationId:
                // Log any others as we see them.
                return nil
            }
        }

        public var logLevel: MessageBackup.LogLevel {
            switch type {
            case
                    .protoSerializationError,
                    .referencedRecipientIdMissing,
                    .referencedThreadIdMissing,
                    .referencedCustomChatColorMissing,
                    .unableToFetchRecipientIdentity,
                    .fileIOError,
                    .groupMasterKeyError,
                    .themedCustomChatColor,
                    .unknownWallpaper,
                    .distributionListMissingDistributionId,
                    .distributionListHasDefaultViewMode,
                    .customDistributionListBlocklistViewMode,
                    .distributionListMissingDeletionTimestamp,
                    .invalidDistributionListMemberAddress,
                    .invalidIncomingMessageAuthor,
                    .invalidOutgoingMessageRecipient,
                    .invalidQuoteAuthor,
                    .linkPreviewMissingUrl,
                    .stickerMessageMissingStickerAttachment,
                    .failedToEnqueueAttachmentForUpload,
                    .invalidReactionAddress,
                    .emptyGroupUpdate,
                    .missingLocalProfile,
                    .missingLocalProfileKey,
                    .missingRequiredGroupMemberParams,
                    .groupCallRecordHadInvalidCallStatus,
                    .verificationStateUpdateInteractionMissingAuthor,
                    .phoneNumberChangeInteractionMissingAuthor,
                    .identityKeyChangeInteractionMissingAuthor,
                    .decryptionErrorInteractionMissingAuthor,
                    .paymentActivationRequestInteractionMissingAuthor,
                    .paymentsActivatedInteractionMissingAuthor,
                    .foundComplexChatUpdateTypeWhenExpectingSimple,
                    .verificationStateChangeNotExpectedSDSRecordType,
                    .unknownProtocolVersionNotExpectedSDSRecordType,
                    .simpleChatUpdateMessageNotInContactThread,
                    .paymentInfoFetchFailed,
                    .missingPaymentInformation,
                    .disappearingMessageConfigUpdateNotExpectedSDSRecordType,
                    .disappearingMessageConfigUpdateMissingAuthor,
                    .profileChangeUpdateMissingAuthor,
                    .threadMergeUpdateMissingAuthor,
                    .sessionSwitchoverUpdateMissingAuthor,
                    .learnedProfileUpdateMissingPreviousName,
                    .learnedProfileUpdateInvalidE164,
                    .learnedProfileUpdateMissingAuthor,
                    .editHistoryFailedToFetch,
                    .unableToReadStoryContextAssociatedData,
                    .unviewedViewOnceMessageMissingAttachment,
                    .unviewedViewOnceMessageTooManyAttachments,
                    .callLinkRestrictionsUnknown,
                    .adHocCallDoesNotHaveCallLinkAsConversationId:
                return .error
            case .contactThreadMissingAddress:
                // We've seen real-world databases with TSContactThreads that
                // have no contact identifiers (aci/pni/e64).
                // These cause us to drop the TSThread from the backup, but
                // we can mark these as warnings. If these threads have
                // any messages in them, those will fail at log level error.
                return .warning
            case .profileChangeUpdateMissingNames:
                // We've seen real world databases with profileChange TSInfoMessages
                // that don't have names on them. We filter these at render time
                // (see `hasRenderableChanges`), so drop them from the backup
                // with a warning but not an error.
                return .warning
            case .linkPreviewUrlNotInBody:
                // We've seen real world databases with invalid link previews; we
                // just drop these on export and just issue a warning.
                return .warning
            case .incomingMessageFromSelf:
                // We've seen real world databases with messages from self; we
                // fudge these into outgoing messages on export and issue a warning.
                return .warning
            }
        }
    }

    /// Error archiving an entire category of frames; not attributable to a
    /// single frame.
    public struct FatalArchivingError: MessageBackupLoggableError {
        public enum ErrorType {
            /// Error iterating over all SignalRecipients for backup purposes.
            case recipientIteratorError(RawError)

            /// Error iterating over all threads for backup purposes.
            case threadIteratorError(RawError)
            /// We fetched a thread (via the iterator) with no sqlite row id.
            case fetchedThreadMissingRowId

            /// Some unrecognized thread was found when iterating over all threads.
            case unrecognizedThreadType

            /// Error iterating over all interactions for backup purposes.
            case interactionIteratorError(RawError)
            /// We fetched an interaction (via the iterator) with no sqlite row id.
            case fetchedInteractionMissingRowId

            /// Error fetching reactions for a message.
            case reactionIteratorError(RawError)

            /// Error iterating over all sticker packs for backup purposes.
            case stickerPackIteratorError(RawError)

            /// Error iterating over all call link records for backup purposes.
            case callLinkRecordIteratorError(RawError)

            /// Error iterating over all ad hoc calls for backup purposes.
            case adHocCallIteratorError(RawError)

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

        public var logLevel: MessageBackup.LogLevel {
            // All of these are hard errors.
            return .error
        }
    }

    /// Error restoring a frame.
    public struct RestoreFrameError<ProtoIdType: MessageBackupLoggableId>: MessageBackupLoggableError {
        public enum ErrorType {
            public enum InvalidProtoDataError {
                /// No ``BackupProto_BackupInfo`` header found.
                case missingBackupInfoHeader
                /// The ``BackupProto_BackupInfo`` has an unsupported version.
                case unsupportedBackupInfoVersion
                /// The ``BackupProto_BackupInfo`` had a missing or invalid MediaRootBackupKey.
                case invalidMediaRootBackupKey

                /// The AccountData frame was missing or not present before other frames.
                case accountDataNotFound
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
                /// Could not parse an ``IdentityKey`` from a contact.
                case invalidContactIdentityKey
                /// An invalid member (group, distribution list, etc) was specified as a distribution list member.  Includes the offending proto
                case invalidDistributionListMember(protoClass: Any.Type)

                /// A ``BackupProto/Recipient`` with a missing destination.
                case recipientMissingDestination

                /// A ``BackupProto_Contact`` with unknown identityState.
                case unknownContactIdentityState

                /// A ``BackupProto/Contact`` with no aci, pni, or e164.
                case contactWithoutIdentifiers
                /// A ``BackupProto/Contact`` for the local user. This shouldn't exist.
                case otherContactWithLocalIdentifiers
                /// A ``BackupProto/Contact`` missing info as to whether or not
                /// it is registered.
                case contactWithoutRegistrationInfo

                /// A ``BackupProto_ChatStyle/BubbleColorPreset`` had an unrecognized case.
                case unrecognizedChatStyleBubbleColorPreset
                /// Some custom chat color identifier being referenced was not present earlier in the backup file.
                case customChatColorNotFound(CustomChatColorId)
                /// A ``BackupProto_ChatStyle/CustomChatColor`` had an unrecognized color oneof.
                case unrecognizedCustomChatStyleColor
                /// A ``BackupProto_ChatStyle/Gradient`` had less than two colors.
                case chatStyleGradientSingleOrNoColors
                /// A ``BackupProto_ChatStyle/WallpaperPreset`` had an unrecognized case.
                case unrecognizedChatStyleWallpaperPreset

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
                /// A custom (non-MyStory) distribution list had ``BackupProto_DistributionList/PrivacyMode/all``
                /// or ``BackupProto_DistributionList/PrivacyMode/allExcept``, which are only allowed
                /// for My Story.
                case customDistributionListPrivacyModeAllOrAllExcept
                /// `BackupProto_DistributionListItem.deletionTimestamp` was invalid
                case invalidDistributionListDeletionTimestamp

                /// ``BackupProto_DistributionListItem`` was used as a recipient for
                /// a ``BackupProto_Chat``; this isn't allowed.
                case distributionListUsedAsChatRecipient
                /// ``BackupProto_CallLink`` was used as a recipient for something
                /// other than a ``BackupProto_AdHocCall``; this isn't allowed.
                case callLinkUsedAsChatRecipient

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
                /// An "end session" simple chat update was associated with a
                /// non-contact recipient.
                case endSessionNotFromContact
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
                /// associated with a non-contact recipient.
                case unsupportedProtocolVersionNotFromContact

                /// An ArchivedPayment was unable to be crated from the
                /// restored payment information.
                case unrecognizedPaymentTransaction

                /// An "expiration timer update" was in a non-contact thread.
                /// - Note
                /// Expiration timer updates for group threads are handled via
                /// a separate "group expiration timer update" proto.
                case expirationTimerUpdateNotInContactThread

                /// An "expiration timer" field contained a value that
                /// overflowed the local type for expiration timers.
                case expirationTimerOverflowedLocalType

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
                /// A ``BackupProto_MessageAttachment/clientUuid`` contained an invalid UUID.
                case invalidAttachmentClientUUID

                /// A ``BackupProto_GiftBadge/state`` was unrecognized.
                case unrecognizedGiftBadgeState

                /// A ``BackupProto_CallLink/rootKey`` was invalid.
                case callLinkInvalidRootKey
                /// A ``BackupProto_CallLink/restrictions`` was unrecognized.
                case callLinkRestrictionsUnrecognizedType

                /// A ``BackupProto_AdHocCall/state`` was unknown.
                case adHocCallUnknownState
                /// A ``BackupProto_AdHocCall/state`` was unrecognized.
                case adHocCallUnrecognizedState
                /// The recipient on an ad hoc call was not a call link. No other
                /// recipient types are valid for an ad hoc call.
                case recipientOfAdHocCallWasNotCallLink
            }

            /// The proto contained invalid or self-contradictory data, e.g an invalid ACI.
            case invalidProtoData(InvalidProtoDataError)

            /// The object being restored depended on a TSThread that should have been created earlier but was not.
            /// This could be either a group or contact thread, we are restoring a frame that doesn't care (e.g. a ChatItem).
            case referencedChatThreadNotFound(ThreadUniqueId)
            /// The object being inserted depended on a TSGroupThread that should have been created earlier but was not.
            /// The overlap with referencedChatThreadNotFound is confusing, but this is for restoring group-specific metadata.
            case referencedGroupThreadNotFound(GroupId)

            /// The object being inserted depended on a CustomChatColor that should have been created earlier but was not.
            case referencedCustomChatColorNotFound(CustomChatColor.Key)

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
                case
                        .missingBackupInfoHeader,
                        .unsupportedBackupInfoVersion,
                        .invalidMediaRootBackupKey,
                        .accountDataNotFound,
                        .recipientIdNotFound,
                        .chatIdNotFound:
                    // Collapse these by the id they refer to, which is in the "type".
                    return typeLogString
                case .customChatColorNotFound(let id):
                    return id.idLogString
                case
                        .invalidAci,
                        .invalidPni,
                        .invalidServiceId,
                        .invalidE164,
                        .invalidProfileKey,
                        .invalidContactIdentityKey,
                        .invalidDistributionListMember,
                        .recipientMissingDestination,
                        .unknownContactIdentityState,
                        .contactWithoutIdentifiers,
                        .otherContactWithLocalIdentifiers,
                        .contactWithoutRegistrationInfo,
                        .chatItemMissingDirectionalDetails,
                        .chatItemMissingItem,
                        .chatItemInvalidDateSent,
                        .unrecognizedChatStyleBubbleColorPreset,
                        .unrecognizedCustomChatStyleColor,
                        .chatStyleGradientSingleOrNoColors,
                        .unrecognizedChatStyleWallpaperPreset,
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
                        .customDistributionListPrivacyModeAllOrAllExcept,
                        .invalidDistributionListDeletionTimestamp,
                        .distributionListUsedAsChatRecipient,
                        .emptyChatUpdateMessage,
                        .unrecognizedSimpleChatUpdate,
                        .verificationStateChangeNotFromContact,
                        .phoneNumberChangeNotFromContact,
                        .endSessionNotFromContact,
                        .decryptionErrorNotFromContact,
                        .paymentsActivationRequestNotFromAci,
                        .paymentsActivatedNotFromAci,
                        .unrecognizedPaymentTransaction,
                        .unsupportedProtocolVersionNotFromContact,
                        .expirationTimerUpdateNotInContactThread,
                        .expirationTimerOverflowedLocalType,
                        .profileChangeUpdateInvalidNames,
                        .profileChangeUpdateNotFromContact,
                        .threadMergeUpdateNotFromContact,
                        .sessionSwitchoverUpdateNotFromContact,
                        .learnedProfileUpdateMissingPreviousName,
                        .learnedProfileUpdateNotFromContact,
                        .revisionOfIncomingMessageMissingIncomingDetails,
                        .revisionOfOutgoingMessageMissingOutgoingDetails,
                        .filePointerMissingTransitCdnKey,
                        .filePointerMissingMediaName,
                        .filePointerMissingEncryptionKey,
                        .filePointerMissingDigest,
                        .invalidAttachmentClientUUID,
                        .unrecognizedGiftBadgeState,
                        .callLinkInvalidRootKey,
                        .callLinkRestrictionsUnrecognizedType,
                        .callLinkUsedAsChatRecipient,
                        .adHocCallUnknownState,
                        .adHocCallUnrecognizedState,
                        .recipientOfAdHocCallWasNotCallLink:
                    // Collapse all others by the id of the containing frame.
                    return idLogString
                }
            case .referencedChatThreadNotFound, .referencedGroupThreadNotFound, .failedToCreateAttachment:
                // Collapse these by the id they refer to, which is in the "type".
                return typeLogString
            case .referencedCustomChatColorNotFound(let key):
                // Collapse these by the key that isn't found.
                return key.rawValue
            case .databaseModelMissingRowId(let modelClass):
                // Collapse these by the relevant class.
                return "\(modelClass)"
            case
                .databaseInsertionFailed(let rawError),
                .uploadEraDerivationFailed(let rawError),
                .failedToEnqueueAttachmentDownload(let rawError):
                // We don't want to re-log every instance of this we see if they repeat.
                // Collapse them by the raw error itself.
                return "\(rawError)"
            case .developerError:
                // Log each of these as we see them.
                return nil
            }
        }

        public var logLevel: MessageBackup.LogLevel {
            switch type {
            case .invalidProtoData(let invalidProtoDataError):
                switch invalidProtoDataError {
                case
                        .missingBackupInfoHeader,
                        .unsupportedBackupInfoVersion,
                        .invalidMediaRootBackupKey,
                        .accountDataNotFound,
                        .recipientIdNotFound,
                        .chatIdNotFound,
                        .invalidAci,
                        .invalidPni,
                        .invalidServiceId,
                        .invalidE164,
                        .invalidProfileKey,
                        .invalidContactIdentityKey,
                        .invalidDistributionListMember,
                        .recipientMissingDestination,
                        .unknownContactIdentityState,
                        .contactWithoutIdentifiers,
                        .otherContactWithLocalIdentifiers,
                        .contactWithoutRegistrationInfo,
                        .chatItemMissingDirectionalDetails,
                        .chatItemMissingItem,
                        .chatItemInvalidDateSent,
                        .unrecognizedChatStyleBubbleColorPreset,
                        .unrecognizedCustomChatStyleColor,
                        .chatStyleGradientSingleOrNoColors,
                        .customChatColorNotFound,
                        .unrecognizedChatStyleWallpaperPreset,
                        .directionlessChatItemNotUpdateMessage,
                        .incomingMessageNotFromAciOrE164,
                        .outgoingNonContactMessageRecipient,
                        .unrecognizedMessageSendStatus,
                        .reactionNotFromAciOrE164,
                        .emptyStandardMessage,
                        .longTextStandardMessageMissingBody,
                        .unrecognizedBodyRangeStyle,
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
                        .customDistributionListPrivacyModeAllOrAllExcept,
                        .invalidDistributionListDeletionTimestamp,
                        .distributionListUsedAsChatRecipient,
                        .emptyChatUpdateMessage,
                        .unrecognizedSimpleChatUpdate,
                        .verificationStateChangeNotFromContact,
                        .phoneNumberChangeNotFromContact,
                        .endSessionNotFromContact,
                        .decryptionErrorNotFromContact,
                        .paymentsActivationRequestNotFromAci,
                        .paymentsActivatedNotFromAci,
                        .unrecognizedPaymentTransaction,
                        .unsupportedProtocolVersionNotFromContact,
                        .expirationTimerUpdateNotInContactThread,
                        .expirationTimerOverflowedLocalType,
                        .profileChangeUpdateInvalidNames,
                        .profileChangeUpdateNotFromContact,
                        .threadMergeUpdateNotFromContact,
                        .sessionSwitchoverUpdateNotFromContact,
                        .learnedProfileUpdateMissingPreviousName,
                        .learnedProfileUpdateNotFromContact,
                        .revisionOfIncomingMessageMissingIncomingDetails,
                        .revisionOfOutgoingMessageMissingOutgoingDetails,
                        .filePointerMissingTransitCdnKey,
                        .filePointerMissingMediaName,
                        .filePointerMissingEncryptionKey,
                        .filePointerMissingDigest,
                        .invalidAttachmentClientUUID,
                        .unrecognizedGiftBadgeState,
                        .callLinkInvalidRootKey,
                        .callLinkRestrictionsUnrecognizedType,
                        .callLinkUsedAsChatRecipient,
                        .adHocCallUnknownState,
                        .adHocCallUnrecognizedState,
                        .recipientOfAdHocCallWasNotCallLink:
                    return .error
                case .quotedMessageEmptyContent:
                    // It was historically possible to end up with a quote that
                    // had no contents (no body, no OWSAttachmentInfo, not view-once
                    // or a gift badge). The way this renders is as a quote of an
                    // attachment with no preview, just the text "Attachment".
                    return .warning
                }
            case
                    .referencedChatThreadNotFound,
                    .referencedGroupThreadNotFound,
                    .failedToCreateAttachment,
                    .referencedCustomChatColorNotFound,
                    .databaseModelMissingRowId,
                    .databaseInsertionFailed,
                    .uploadEraDerivationFailed,
                    .failedToEnqueueAttachmentDownload,
                    .developerError:
                return .error
            }
        }
    }
}

// MARK: - Log Collapsing

extension MessageBackup {

    public enum LogLevel: Int {
        /// Log these, but don't pull up the internal
        /// dialog if all errors are warnings.
        case warning
        /// Log these and show the internal dialog if these happen.
        case error
    }
}

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

    var logLevel: MessageBackup.LogLevel { get }
}

extension MessageBackup {

    internal struct LoggableErrorAndProto {
        let error: any MessageBackupLoggableError
        let wasFatal: Bool
        /// Nil for archiving, if we fail to even parse the proto on restore,
        /// or if the feature flag is disabled such that this would be unused.
        let protoJson: String?

        init(
            error: any MessageBackupLoggableError,
            wasFatal: Bool,
            protoFrame: SwiftProtobuf.Message? = nil
        ) {
            self.error = error
            self.wasFatal = wasFatal
            // Don't serialize proto frames if we aren't displaying errors.
            if let protoFrame, FeatureFlags.messageBackupErrorDisplay {
                do {
                    self.protoJson = try String(
                        data: JSONSerialization.data(
                            withJSONObject: JSONSerialization.jsonObject(
                                with: protoFrame.jsonUTF8Data(),
                                options: .mutableContainers
                            ),
                            options: .prettyPrinted
                        ),
                        encoding: .utf8
                    )
                } catch let jsonError {
                    self.protoJson = "Unable to json encode proto: \(jsonError)"
                }
            } else {
                self.protoJson = nil
            }
        }
    }

    internal static func collapse(_ errors: [LoggableErrorAndProto]) -> [CollapsedErrorLog] {
        var collapsedLogs = OrderedDictionary<String, CollapsedErrorLog>()
        for error in errors {
            let collapseKey = error.error.collapseKey ?? UUID().uuidString

            if var existingLog = collapsedLogs[collapseKey] {
                existingLog.collapse(error)
                collapsedLogs.replace(key: collapseKey, value: existingLog)
            } else {
                let newLog = CollapsedErrorLog(error)
                collapsedLogs.append(key: collapseKey, value: newLog)
            }
        }
        return Array(collapsedLogs.orderedValues)
    }

    fileprivate static let maxCollapsedIdLogCount = 10

    public struct CollapsedErrorLog {
        public private(set) var typeLogString: String
        public private(set) var exampleCallsiteString: String
        public private(set) var exampleProtoFrameJson: String?
        public private(set) var errorCount: UInt = 0
        public private(set) var idLogStrings: [String] = []
        public private(set) var wasFatal: Bool
        public private(set) var logLevel: MessageBackup.LogLevel

        init(_ error: LoggableErrorAndProto) {
            self.typeLogString = error.error.typeLogString
            self.exampleCallsiteString = error.error.callsiteLogString
            self.exampleProtoFrameJson = error.protoJson
            self.wasFatal = error.wasFatal
            self.logLevel = error.error.logLevel
            self.collapse(error)
        }

        mutating func collapse(_ error: LoggableErrorAndProto) {
            self.errorCount += 1
            self.wasFatal = wasFatal || error.wasFatal
            self.logLevel = LogLevel(rawValue: max(self.logLevel.rawValue, error.error.logLevel.rawValue))!
            if exampleProtoFrameJson == nil, let protoJson = error.protoJson {
                self.exampleProtoFrameJson = protoJson
            }
            if idLogStrings.count < MessageBackup.maxCollapsedIdLogCount {
                idLogStrings.append(error.error.idLogString)
            }
        }

        internal func log() {
            let logString =
                (typeLogString) + " "
                + "WasFatal? \(wasFatal). "
                + "Repeated \(errorCount) times. "
                + "from: \(idLogStrings) "
                + "example callsite: \(exampleCallsiteString)"
            switch logLevel {
            case .warning:
                Logger.warn(logString)
            case .error:
                Logger.error(logString)
            }
        }
    }
}
