//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosAttachmentPointerBuilder;

@interface TSOutgoingMessage : TSMessage

typedef NS_ENUM(NSInteger, TSOutgoingMessageState) {
    TSOutgoingMessageStateAttemptingOut,
    TSOutgoingMessageStateUnsent,
    TSOutgoingMessageStateSent,
    TSOutgoingMessageStateDelivered
};

@property (nonatomic) TSOutgoingMessageState messageState;
@property BOOL hasSyncedTranscript;

/**
 * Signal Identifier (e.g. e164 number) or nil if in a group thread.
 */
- (nullable NSString *)recipientIdentifier;

/**
 * The data representation of this message, to be encrypted, before being sent.
 */
- (NSData *)buildPlainTextData;

/**
 * Should this message be synced to the users other registered devices? This is
 * generally always true, except in the case of the sync messages themseleves
 * (so we don't end up in an infinite loop).
 */
- (BOOL)shouldSyncTranscript;

/**
 * @param attachmentStream
 *   Containing the meta data used when populating the attachment proto
 *
 * @return
 *      An attachment builder suitable for including in various container protobuf builders
 */
- (OWSSignalServiceProtosAttachmentPointerBuilder *)attachmentBuilderForAttachmentId:(NSString *)attachmentId;

@end

NS_ASSUME_NONNULL_END
