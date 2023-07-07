//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>
#import <SignalServiceKit/TSAttachmentPointer.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeySendingErrorMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@class MessageBodyRanges;

// This header exposes private properties for SDS serialization.

@interface TSThread (SDS)

@property (nonatomic, copy, nullable, readonly) NSString *messageDraft;
@property (nonatomic, readonly, nullable) MessageBodyRanges *messageDraftBodyRanges;

@end

#pragma mark -

@interface TSMessage (SDS)

// This property is only intended to be used by GRDB queries.
@property (nonatomic, readonly) BOOL storedShouldStartExpireTimer;

@end

#pragma mark -

@interface TSInfoMessage (SDS)

@property (nonatomic, getter=wasRead) BOOL read;

@end

#pragma mark -

@interface TSErrorMessage (SDS)

@property (nonatomic, getter=wasRead) BOOL read;

@end

#pragma mark -

@interface TSOutgoingMessage (SDS)

@property (nonatomic, readonly) TSOutgoingMessageState legacyMessageState;
@property (nonatomic, readonly) BOOL legacyWasDelivered;
@property (nonatomic, readonly) BOOL hasLegacyMessageState;
@property (atomic, nullable, readonly)
    NSDictionary<SignalServiceAddress *, TSOutgoingMessageRecipientState *> *recipientAddressStates;
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

@end

#pragma mark -

@interface TSIncomingMessage (SDS)

@property (nonatomic, getter=wasRead) BOOL read;

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
@property (atomic, nullable, readonly) NSNumber *isAnimatedCached;

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

@interface TSContactThread (SDS)

@property (nonatomic, nullable) NSString *contactPhoneNumber;
@property (nonatomic, nullable) NSString *contactUUID;

@end

#pragma mark -

@interface OWSUserProfile (SDS)

@property (atomic, nullable) NSString *recipientPhoneNumber;
@property (atomic, nullable) NSString *recipientUUID;
@property (atomic, nullable, readonly) NSString *profileName;

@end

#pragma mark -

@interface OWSGroupCallMessage (SDS)

@property (nonatomic, getter=wasRead) BOOL read;
@property (nonatomic, readonly, nullable) NSString *eraId;
@property (nonatomic, nullable) NSArray<NSString *> *joinedMemberUuids;
@property (nonatomic, nullable) NSString *creatorUuid;
@property (nonatomic, readonly) BOOL hasEnded;

@end

NS_ASSUME_NONNULL_END
