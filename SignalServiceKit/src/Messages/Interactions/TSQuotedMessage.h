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

@interface OWSAttachmentInfo : MTLModel

@property (nonatomic, readonly, nullable) NSString *contentType;
@property (nonatomic, readonly, nullable) NSString *sourceFilename;

// This is only set when sending a new attachment so we have a way
// to reference the original attachment when generating a thumbnail.
// We don't want to do this until the message is saved, when the user sends
// the message so as not to end up with an orphaned file.
@property (nonatomic, readonly, nullable) NSString *attachmentId;

// References a yet-to-be downloaded thumbnail file
@property (atomic, nullable) NSString *thumbnailAttachmentPointerId;

// References an already downloaded or locally generated thumbnail file
@property (atomic, nullable) NSString *thumbnailAttachmentStreamId;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithAttachmentId:(nullable NSString *)attachmentId
                         contentType:(NSString *)contentType
                      sourceFilename:(NSString *)sourceFilename NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithAttachmentStream:(TSAttachmentStream *)attachmentStream;

- (instancetype)initWithAttachmentId:(nullable NSString *)attachmentId
                         contentType:(NSString *)contentType
                      sourceFilename:(NSString *)sourceFilename
        thumbnailAttachmentPointerId:(nullable NSString *)thumbnailAttachmentPointerId
         thumbnailAttachmentStreamId:(nullable NSString *)thumbnailAttachmentStreamId NS_DESIGNATED_INITIALIZER;

@end

#pragma mark -

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

// This is a MIME type.
//
// This property should be set IFF we are quoting an attachment message.
- (nullable NSString *)contentType;
- (nullable NSString *)sourceFilename;

// References a yet-to-be downloaded thumbnail file
- (nullable NSString *)thumbnailAttachmentPointerId;

// References an already downloaded or locally generated thumbnail file
- (nullable NSString *)thumbnailAttachmentStreamId;
- (void)setThumbnailAttachmentStream:(TSAttachment *)thumbnailAttachmentStream;

// currently only used by orphan attachment cleaner
- (NSArray<NSString *> *)thumbnailAttachmentStreamIds;

@property (atomic, readonly) NSArray<OWSAttachmentInfo *> *quotedAttachments;

// Before sending, persist a thumbnail attachment derived from the quoted attachment
- (NSArray<TSAttachmentStream *> *)createThumbnailAttachmentsIfNecessaryWithTransaction:
    (SDSAnyWriteTransaction *)transaction;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// used when receiving quoted messages
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                       bodySource:(TSQuotedMessageContentSource)bodySource
    receivedQuotedAttachmentInfos:(NSArray<OWSAttachmentInfo *> *)attachmentInfos;

// used when sending quoted messages
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
      quotedAttachmentsForSending:(NSArray<TSAttachment *> *)attachments;


+ (nullable instancetype)quotedMessageForDataMessage:(SSKProtoDataMessage *)dataMessage
                                              thread:(TSThread *)thread
                                         transaction:(SDSAnyWriteTransaction *)transaction;

@end

#pragma mark -

NS_ASSUME_NONNULL_END
