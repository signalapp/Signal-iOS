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

@property (nonatomic) OWSAttachmentInfoReference attachmentType;
@property (nonatomic) NSString *rawAttachmentId;

/// rawAttachmentId, above, is Mantel-decoded and transforms nil values into empty strings
/// (Mantle provides "reasonable" defaults). This undoes that; empty string values are reverted to nil.
@property (nonatomic, readonly, nullable) NSString *attachmentId;

/// Only should be read for "stub" quoted reply attachments (those without thumbnail-able attachments)
@property (nonatomic, readonly, nullable) NSString *stubMimeType;
/// Only should be read for "stub" quoted reply attachments (those without thumbnail-able attachments)
@property (nonatomic, readonly, nullable) NSString *stubSourceFilename;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initStubWithMimeType:(NSString *)mimeType sourceFilename:(NSString *_Nullable)sourceFilename;

- (instancetype)initForV2ThumbnailReference;

- (instancetype)initWithLegacyAttachmentId:(NSString *)attachmentId ofType:(OWSAttachmentInfoReference)attachmentType;


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

- (nullable OWSAttachmentInfo *)attachmentInfo;

- (void)setLegacyThumbnailAttachmentStream:(TSAttachment *)thumbnailAttachmentStream;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// used when sending quoted messages
- (instancetype)initWithTimestamp:(nullable NSNumber *)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
       quotedAttachmentForSending:(nullable OWSAttachmentInfo *)attachmentInfo
                      isGiftBadge:(BOOL)isGiftBadge;

// used when receiving quoted messages. Do not call directly outside AttachmentManager.
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                       bodySource:(TSQuotedMessageContentSource)bodySource
     receivedQuotedAttachmentInfo:(nullable OWSAttachmentInfo *)attachmentInfo
                      isGiftBadge:(BOOL)isGiftBadge;

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
