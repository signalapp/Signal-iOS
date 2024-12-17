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

@interface OWSAttachmentInfo : MTLModel
@property (class, nonatomic, readonly) NSUInteger currentSchemaVersion;
@property (nonatomic, readonly) NSUInteger schemaVersion;

/// rawAttachmentId, above, is Mantel-decoded and transforms nil values into empty strings
/// (Mantle provides "reasonable" defaults). This undoes that; empty string values are reverted to nil.
@property (nonatomic, readonly, nullable) NSString *attachmentId;

/// The mime type of an attachment that was quoted.
///
/// - Important
/// This should not be confused with the mime type of the thumbnail of this
/// attachment that is owned by the quote itself!
///
/// - Important
/// This value may be set based on an incoming proto, and may not be accurate.
/// If the attachment itself is available, prefer reading the mime type from it
/// directly.
@property (nonatomic, readonly, nullable) NSString *originalAttachmentMimeType;

/// The source filename of an attachment that was quoted.
///
/// - Important
/// This should not be confused with the mime type of the thumbnail of this
/// attachment that is owned by the quote itself!
///
/// - Important
/// This value may be set based on an incoming proto, and may not be accurate.
/// If the attachment itself is available, prefer reading the source filename
/// from it directly.
@property (nonatomic, readonly, nullable) NSString *originalAttachmentSourceFilename;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)stubWithOriginalAttachmentMimeType:(NSString *)originalAttachmentMimeType
                  originalAttachmentSourceFilename:(NSString *_Nullable)originalAttachmentSourceFilename;

+ (instancetype)forThumbnailReferenceWithOriginalAttachmentMimeType:(NSString *)originalAttachmentMimeType
                                   originalAttachmentSourceFilename:
                                       (NSString *_Nullable)originalAttachmentSourceFilename;

#if TESTABLE_BUILD
/// Do not use this constructor directly! Instead, use the static constructors.
/// Legacy data may contain a `nil` content type, so this constructor is exposed
/// to facilitate testing the deserialization of that legacy data.
+ (instancetype)stubWithNullableOriginalAttachmentMimeType:(NSString *_Nullable)originalAttachmentMimeType
                          originalAttachmentSourceFilename:(NSString *_Nullable)originalAttachmentSourceFilename;
#endif

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
/// If we found the target message at receive time (TSQuotedMessageContentSourceLocal),
/// true if that target message was view once.
/// If we did not find the target message (TSQuotedMessageContentSourceRemote), will always
/// be false because we do not know if the target message was view-once. In these cases, we
/// take the body off the Quote proto we receive.
/// At send time, we always set the body of the outgoing Quote proto as the localized string
/// that indicates this was a reply to a view-once message.
@property (nonatomic, readonly) BOOL isTargetMessageViewOnce;

#pragma mark - Attachments

- (nullable OWSAttachmentInfo *)attachmentInfo;

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

// used when sending quoted messages
- (instancetype)initWithTimestamp:(nullable NSNumber *)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
       quotedAttachmentForSending:(nullable OWSAttachmentInfo *)attachmentInfo
                      isGiftBadge:(BOOL)isGiftBadge
          isTargetMessageViewOnce:(BOOL)isTargetMessageViewOnce;

// used when receiving quoted messages. Do not call directly outside AttachmentManager.
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                    authorAddress:(SignalServiceAddress *)authorAddress
                             body:(nullable NSString *)body
                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                       bodySource:(TSQuotedMessageContentSource)bodySource
     receivedQuotedAttachmentInfo:(nullable OWSAttachmentInfo *)attachmentInfo
                      isGiftBadge:(BOOL)isGiftBadge
          isTargetMessageViewOnce:(BOOL)isTargetMessageViewOnce;

// used when restoring quoted messages from backups
+ (instancetype)quotedMessageFromBackupWithTargetMessageTimestamp:(nullable NSNumber *)timestamp
                                                    authorAddress:(SignalServiceAddress *)authorAddress
                                                             body:(nullable NSString *)body
                                                       bodyRanges:(nullable MessageBodyRanges *)bodyRanges
                                                       bodySource:(TSQuotedMessageContentSource)bodySource
                                             quotedAttachmentInfo:(nullable OWSAttachmentInfo *)attachmentInfo
                                                      isGiftBadge:(BOOL)isGiftBadge
                                          isTargetMessageViewOnce:(BOOL)isTargetMessageViewOnce;

@end

#pragma mark -

NS_ASSUME_NONNULL_END
