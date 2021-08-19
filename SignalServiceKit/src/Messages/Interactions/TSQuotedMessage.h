//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <Mantle/MTLModel.h>

NS_ASSUME_NONNULL_BEGIN

@class MessageBodyRanges;
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
    TSQuotedMessageContentSourceRemote
};

@interface TSQuotedMessage : MTLModel

@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly) SignalServiceAddress *authorAddress;
@property (nonatomic, readonly) TSQuotedMessageContentSource bodySource;

// This property should be set IFF we are quoting a text message
// or attachment with caption.
@property (nullable, nonatomic, readonly) NSString *body;
@property (nonatomic, readonly, nullable) MessageBodyRanges *bodyRanges;

#pragma mark - Attachments

/// Is the quoted thumbnail currently owned by the quoted message model? Or is it referencing an existing attachment
@property (nonatomic, readonly) NSString *thumbnailAttachmentId;
@property (nonatomic, readonly) BOOL isThumbnailOwned;
@property (nonatomic, readonly) NSString *contentType;
@property (nonatomic, readonly) NSString *sourceFilename;
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
       quotedAttachmentForSending:(nullable TSAttachment *)attachment;

// used when receiving quoted messages
+ (nullable instancetype)quotedMessageForDataMessage:(SSKProtoDataMessage *)dataMessage
                                              thread:(TSThread *)thread
                                         transaction:(SDSAnyWriteTransaction *)transaction;

@end

#pragma mark -

NS_ASSUME_NONNULL_END
