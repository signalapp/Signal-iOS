//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Mantle/MTLModel.h>

NS_ASSUME_NONNULL_BEGIN

@class MessageBodyRanges;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SSKProtoDataMessage;
@class SignalServiceAddress;
@class TSAttachment;
@class TSAttachmentStream;
@class TSQuotedMessage;
@class TSThread;

typedef NS_ENUM(NSUInteger, TSQuotedMessageContentSource) {
    TSQuotedMessageContentSourceUnknown,
    TSQuotedMessageContentSourceLocal,
    TSQuotedMessageContentSourceRemote,
    TSQuotedMessageContentSourceStory
};

@interface TSQuotedMessage : MTLModel

@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly) SignalServiceAddress *authorAddress;
@property (nonatomic, readonly) TSQuotedMessageContentSource bodySource;

// This property should be set IFF we are quoting a text message
// or attachment with caption.
@property (nullable, nonatomic, readonly) NSString *body;
@property (nonatomic, readonly, nullable) MessageBodyRanges *bodyRanges;

@property (nonatomic, readonly) BOOL isGiftBadge;

#pragma mark - Attachments

@property (nonatomic, readonly) BOOL hasAttachment;

/// Returns YES if the thumbnail is something maintained by the quoted reply itself (as opposed to to media in some
/// other message)
@property (nonatomic, readonly) BOOL isThumbnailOwned;
@property (nonatomic, readonly, nullable) NSString *thumbnailAttachmentId;
@property (nonatomic, readonly, nullable) NSString *contentType;
@property (nonatomic, readonly, nullable) NSString *sourceFilename;

// Should only be called by TSMessage. May perform a sneaky write if necessary
- (nullable TSAttachment *)fetchThumbnailWithTransaction:(SDSAnyReadTransaction *)transaction;

// References an already downloaded or locally generated thumbnail file
- (void)setThumbnailAttachmentStream:(TSAttachment *)thumbnailAttachmentStream;

// Before sending, persist a thumbnail attachment derived from the quoted attachment
- (nullable TSAttachmentStream *)createThumbnailIfNecessaryWithTransaction:(SDSAnyWriteTransaction *)transaction;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// used when sending quoted messages
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
       quotedAttachmentForSending:(nullable TSAttachment *)attachment
                      isGiftBadge:(BOOL)isGiftBadge;

// used when receiving quoted messages
+ (nullable instancetype)quotedMessageForDataMessage:(SSKProtoDataMessage *)dataMessage
                                              thread:(TSThread *)thread
                                         transaction:(SDSAnyWriteTransaction *)transaction;

@end

#pragma mark -

NS_ASSUME_NONNULL_END
