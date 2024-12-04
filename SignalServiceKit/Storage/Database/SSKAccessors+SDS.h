//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Foundation/Foundation.h>
#import <SignalServiceKit/TSCall.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSIncomingMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSInvalidIdentityKeySendingErrorMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@class MessageBodyRanges;

// This header exposes private properties for SDS serialization.

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
@property (nonatomic, readonly) TSOutgoingMessageState storedMessageState;

@end

#pragma mark -

@interface OWSDisappearingConfigurationUpdateInfoMessage (SDS)

@property (nonatomic, readonly) uint32_t configurationDurationSeconds;

@property (nonatomic, readonly, nullable) NSString *createdByRemoteName;
@property (nonatomic, readonly) BOOL createdInExistingGroup;

@end

#pragma mark -

@interface TSIncomingMessage (SDS)

@property (nonatomic, getter=wasRead) BOOL read;

@end

#pragma mark -

@interface TSInvalidIdentityKeySendingErrorMessage (SDS)

@property (nonatomic, readonly) NSData *preKeyBundle;

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

NS_ASSUME_NONNULL_END
