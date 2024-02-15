//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <Mantle/MTLModel.h>

NS_ASSUME_NONNULL_BEGIN

@class DisplayableQuotedThumbnailAttachment;
@class MessageBodyRanges;
@class QuotedThumbnailAttachmentMetadata;
@class SDSAnyReadTransaction;
@class SDSAnyWriteTransaction;
@class SSKProtoDataMessage;
@class SignalServiceAddress;
@class TSAttachment;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSMessage;
@class TSQuotedMessage;
@class TSThread;

@protocol QuotedMessageAttachmentHelper;

/// Note that ContentSource is NOT the same as OWSAttachmentInfoReference;
/// this tells us where we got the quote from (whether it has an attachment or not)
/// and doesn't ever change, including after downloading any attachments.
typedef NS_ENUM(NSUInteger, TSQuotedMessageContentSource) {
    TSQuotedMessageContentSourceUnknown,
    TSQuotedMessageContentSourceLocal,
    TSQuotedMessageContentSourceRemote,
    TSQuotedMessageContentSourceStory
};

/// Indicates the sort of attachment ID included in the attachment info
typedef NS_ENUM(NSUInteger, OWSAttachmentInfoReference) {
    OWSAttachmentInfoReferenceUnset = 0,
    /// An original attachment for a quoted reply draft. This needs to be thumbnailed before it is sent.
    OWSAttachmentInfoReferenceOriginalForSend = 1,
    /// A reference to an original attachment in a quoted reply we've received. If this ever manifests as a stream
    /// we should clone it as a private thumbnail
    OWSAttachmentInfoReferenceOriginal,
    /// A private thumbnail that we (the quoted reply) have ownership of
    OWSAttachmentInfoReferenceThumbnail,
    /// An untrusted pointer to a thumbnail. This was included in the proto of a message we've received.
    OWSAttachmentInfoReferenceUntrustedPointer,
    /// A v2 attachment; the reference is kept in the AttachmentReferences table.
    /// TODO: eliminate other reference types
    OWSAttachmentInfoReferenceV2,
};

@interface OWSAttachmentInfo : MTLModel
@property (class, nonatomic, readonly) NSUInteger currentSchemaVersion;
@property (nonatomic, readonly) NSUInteger schemaVersion;

@property (nonatomic, readonly, nullable) NSString *contentType;
@property (nonatomic, readonly, nullable) NSString *sourceFilename;
@property (nonatomic) OWSAttachmentInfoReference attachmentType;
@property (nonatomic) NSString *rawAttachmentId;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
@end


@interface TSQuotedMessage : MTLModel

@property (nullable, nonatomic, readonly) NSNumber *timestampValue;
@property (nonatomic, readonly) SignalServiceAddress *authorAddress;
@property (nonatomic, readonly) TSQuotedMessageContentSource bodySource;

// This property should be set IFF we are quoting a text message
// or attachment with caption.
@property (nullable, nonatomic, readonly) NSString *body;
@property (nonatomic, readonly, nullable) MessageBodyRanges *bodyRanges;

@property (nonatomic, readonly) BOOL isGiftBadge;

#pragma mark - Attachments

- (id<QuotedMessageAttachmentHelper>)attachmentHelper;

- (nullable NSString *)fetchThumbnailAttachmentIdForParentMessage:(TSMessage *)message
                                                      transaction:(SDSAnyReadTransaction *)transaction;

- (nullable QuotedThumbnailAttachmentMetadata *)
    fetchThumbnailAttachmentMetadataForParentMessage:(TSMessage *)message
                                         transaction:(SDSAnyReadTransaction *)transaction;

- (nullable DisplayableQuotedThumbnailAttachment *)
    displayableThumbnailAttachmentForMetadata:(QuotedThumbnailAttachmentMetadata *)metadata
                                parentMessage:(TSMessage *)message
                                  transaction:(SDSAnyReadTransaction *)transaction;

- (nullable NSString *)attachmentPointerIdForDownloadingWithParentMessage:(TSMessage *)message
                                                              transaction:(SDSAnyReadTransaction *)transaction;

- (void)setDownloadedAttachmentStream:(TSAttachmentStream *)attachmentStream
                        parentMessage:(TSMessage *)message
                          transaction:(SDSAnyWriteTransaction *)transaction;

- (void)setLegacyThumbnailAttachmentStream:(TSAttachment *)thumbnailAttachmentStream;

- (nullable TSAttachmentStream *)createThumbnailAndUpdateMessageIfNecessaryWithParentMessage:(TSMessage *)message
                                                                                 transaction:(SDSAnyWriteTransaction *)
                                                                                                 transaction;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// used when sending quoted messages
- (instancetype)initWithTimestamp:(nullable NSNumber *)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
       quotedAttachmentForSending:(nullable TSAttachment *)attachment
                      isGiftBadge:(BOOL)isGiftBadge;

// used when receiving quoted messages
+ (nullable instancetype)quotedMessageForDataMessage:(SSKProtoDataMessage *)dataMessage
                                              thread:(TSThread *)thread
                                         transaction:(SDSAnyWriteTransaction *)transaction;

// used when restoring quoted messages from backups
// TODO: attachments should be here too, once they are body can be made nullable.
+ (instancetype)quotedMessageWithTargetMessageTimestamp:(nullable NSNumber *)timestamp
                                          authorAddress:(SignalServiceAddress *)authorAddress
                                                   body:(NSString *)body
                                             bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                                             bodySource:(TSQuotedMessageContentSource)bodySource
                                            isGiftBadge:(BOOL)isGiftBadge;

@end

#pragma mark -

NS_ASSUME_NONNULL_END
