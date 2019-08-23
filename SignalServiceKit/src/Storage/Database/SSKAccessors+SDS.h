//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// This header exposes private properties for SDS serialization.

@interface TSThread (SDS)

@property (nonatomic, nullable, readonly) NSNumber *archivedAsOfMessageSortId;
@property (nonatomic, copy, nullable, readonly) NSString *messageDraft;

@property (nonatomic, nullable, readonly) NSDate *lastMessageDate DEPRECATED_ATTRIBUTE;
@property (nonatomic, nullable, readonly) NSDate *archivalDate DEPRECATED_ATTRIBUTE;

@end

#pragma mark -

@interface TSMessage (SDS)

@property (nonatomic, readonly) NSUInteger schemaVersion;

// This property is only intended to be used by GRDB queries.
@property (nonatomic, readonly) BOOL storedShouldStartExpireTimer;

@end

#pragma mark -

@interface TSInfoMessage (SDS)

@property (nonatomic, readonly) NSUInteger infoMessageSchemaVersion;

@property (nonatomic, getter=wasRead) BOOL read;

@end

#pragma mark -

@interface TSErrorMessage (SDS)

@property (nonatomic, getter=wasRead) BOOL read;

@property (nonatomic, readonly) NSUInteger errorMessageSchemaVersion;

@end

#pragma mark -

@interface TSOutgoingMessage (SDS)

@property (nonatomic, readonly) TSOutgoingMessageState legacyMessageState;
@property (nonatomic, readonly) BOOL legacyWasDelivered;
@property (nonatomic, readonly) BOOL hasLegacyMessageState;
@property (atomic, readonly)
    NSDictionary<SignalServiceAddress *, TSOutgoingMessageRecipientState *> *recipientAddressStates;
@property (nonatomic, readonly) NSUInteger outgoingMessageSchemaVersion;
@property (nonatomic, readonly) TSOutgoingMessageState storedMessageState;

@end

#pragma mark -

@interface OWSDisappearingConfigurationUpdateInfoMessage (SDS)

@property (nonatomic, readonly) uint32_t configurationDurationSeconds;

@property (nonatomic, readonly, nullable) NSString *createdByRemoteName;
@property (nonatomic, readonly) BOOL createdInExistingGroup;

@end

#pragma mark -

@interface TSCall (SDS)

@property (nonatomic, getter=wasRead) BOOL read;

@property (nonatomic, readonly) NSUInteger callSchemaVersion;

@end

#pragma mark -

@interface TSIncomingMessage (SDS)

@property (nonatomic, getter=wasRead) BOOL read;
@property (nonatomic, readonly) NSUInteger incomingMessageSchemaVersion;

@end

#pragma mark -

@interface TSAttachment (SDS)

@property (nonatomic, readonly) NSUInteger attachmentSchemaVersion;

@end

#pragma mark -

@interface TSAttachmentPointer (SDS)

@property (nonatomic, nullable, readonly) NSString *lazyRestoreFragmentId;

@end

#pragma mark -

@interface TSAttachmentStream (SDS)

@property (nullable, nonatomic, readonly) NSString *localRelativeFilePath;

@property (nullable, nonatomic, readonly) NSNumber *cachedImageWidth;
@property (nullable, nonatomic, readonly) NSNumber *cachedImageHeight;

@property (nullable, nonatomic, readonly) NSNumber *cachedAudioDurationSeconds;

@property (atomic, nullable, readonly) NSNumber *isValidImageCached;
@property (atomic, nullable, readonly) NSNumber *isValidVideoCached;

@end

#pragma mark -

@interface TSInvalidIdentityKeySendingErrorMessage (SDS)

@property (nonatomic, readonly) PreKeyBundle *preKeyBundle;

@end

#pragma mark -

@interface OWSOutgoingSentMessageTranscript (SDS)

@property (nonatomic, readonly) TSOutgoingMessage *message;

@property (nonatomic, readonly, nullable) NSString *sentRecipientId;

@property (nonatomic, readonly) BOOL isRecipientUpdate;

@end

#pragma mark -

@interface TSInvalidIdentityKeyReceivingErrorMessage (SDS)

@property (nonatomic, readonly, copy) NSString *authorId;

@property (atomic, readonly, nullable) NSData *envelopeData;

@end

#pragma mark -

@interface SignalAccount (SDS)

@property (nonatomic, readonly) NSUInteger accountSchemaVersion;

@end

#pragma mark -

@interface SignalRecipient (SDS)

@property (nonatomic, readonly) NSUInteger recipientSchemaVersion;

@end

#pragma mark -

@interface TSContactThread (SDS)

@property (nonatomic, nullable, readonly) NSString *contactPhoneNumber;
@property (nonatomic, nullable, readonly) NSString *contactUUID;
@property (nonatomic, readonly) NSUInteger contactThreadSchemaVersion;

@end

#pragma mark -

@interface OWSUserProfile (SDS)

@property (atomic, readonly) NSUInteger userProfileSchemaVersion;
@property (atomic, nullable, readonly) NSString *recipientPhoneNumber;
@property (atomic, nullable, readonly) NSString *recipientUUID;

@end

#pragma mark -

@interface OWSLinkedDeviceReadReceipt (SDS)

@property (nonatomic, nullable, readonly) NSString *senderPhoneNumber;
@property (nonatomic, nullable, readonly) NSString *senderUUID;
@property (nonatomic, readonly) NSUInteger linkedDeviceReadReceiptSchemaVersion;

@end

#pragma mark -

@interface OWSRecipientIdentity (SDS)

@property (nonatomic, readonly) NSUInteger recipientIdentitySchemaVersion;

@end

#pragma mark -

@interface TSGroupModel (SDS)

@property (nonatomic, readonly) NSUInteger groupModelSchemaVersion;

@end

#pragma mark -

@interface TSRecipientReadReceipt (SDS)

@property (nonatomic, readonly) NSUInteger recipientReadReceiptSchemaVersion;

@end

#pragma mark -

@interface OWSUnknownProtocolVersionMessage (SDS)

@property (nonatomic, readonly) NSUInteger unknownProtocolVersionMessageSchemaVersion;

@end

#pragma mark -

NS_ASSUME_NONNULL_END
