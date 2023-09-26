//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSInvalidIdentityKeyErrorMessage.h"
#import "OWSError.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSInvalidIdentityKeyErrorMessage

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

- (SignalServiceAddress *)theirSignalAddress
{
    OWSAbstractMethod();
    return nil;
}

- (instancetype)initWithGrdbId:(int64_t)grdbId
                        uniqueId:(NSString *)uniqueId
             receivedAtTimestamp:(uint64_t)receivedAtTimestamp
                          sortId:(uint64_t)sortId
                       timestamp:(uint64_t)timestamp
                  uniqueThreadId:(NSString *)uniqueThreadId
                   attachmentIds:(NSArray<NSString *> *)attachmentIds
                            body:(nullable NSString *)body
                      bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                    contactShare:(nullable OWSContact *)contactShare
                       editState:(TSEditState)editState
                 expireStartedAt:(uint64_t)expireStartedAt
                       expiresAt:(uint64_t)expiresAt
                expiresInSeconds:(unsigned int)expiresInSeconds
                       giftBadge:(nullable OWSGiftBadge *)giftBadge
               isGroupStoryReply:(BOOL)isGroupStoryReply
              isViewOnceComplete:(BOOL)isViewOnceComplete
               isViewOnceMessage:(BOOL)isViewOnceMessage
                     linkPreview:(nullable OWSLinkPreview *)linkPreview
                  messageSticker:(nullable MessageSticker *)messageSticker
                   quotedMessage:(nullable TSQuotedMessage *)quotedMessage
    storedShouldStartExpireTimer:(BOOL)storedShouldStartExpireTimer
           storyAuthorUuidString:(nullable NSString *)storyAuthorUuidString
              storyReactionEmoji:(nullable NSString *)storyReactionEmoji
                  storyTimestamp:(nullable NSNumber *)storyTimestamp
              wasRemotelyDeleted:(BOOL)wasRemotelyDeleted
                       errorType:(TSErrorMessageType)errorType
                            read:(BOOL)read
                recipientAddress:(nullable SignalServiceAddress *)recipientAddress
                          sender:(nullable SignalServiceAddress *)sender
             wasIdentityVerified:(BOOL)wasIdentityVerified
{
    self = [super initWithGrdbId:grdbId
                            uniqueId:uniqueId
                 receivedAtTimestamp:receivedAtTimestamp
                              sortId:sortId
                           timestamp:timestamp
                      uniqueThreadId:uniqueThreadId
                       attachmentIds:attachmentIds
                                body:body
                          bodyRanges:bodyRanges
                        contactShare:contactShare
                           editState:editState
                     expireStartedAt:expireStartedAt
                           expiresAt:expiresAt
                    expiresInSeconds:expiresInSeconds
                           giftBadge:giftBadge
                   isGroupStoryReply:isGroupStoryReply
                  isViewOnceComplete:isViewOnceComplete
                   isViewOnceMessage:isViewOnceMessage
                         linkPreview:linkPreview
                      messageSticker:messageSticker
                       quotedMessage:quotedMessage
        storedShouldStartExpireTimer:storedShouldStartExpireTimer
               storyAuthorUuidString:storyAuthorUuidString
                  storyReactionEmoji:storyReactionEmoji
                      storyTimestamp:storyTimestamp
                  wasRemotelyDeleted:wasRemotelyDeleted
                           errorType:errorType
                                read:read
                    recipientAddress:recipientAddress
                              sender:sender
                 wasIdentityVerified:wasIdentityVerified];
    return self;
}

@end

NS_ASSUME_NONNULL_END
