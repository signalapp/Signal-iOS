//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/TSQuotedMessage.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ConversationViewItem;

@class SDSAnyReadTransaction;
@class SignalServiceAddress;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSMessage;

// View model which has already fetched any attachments.
@interface OWSQuotedReplyModel : NSObject

@property (nonatomic, readonly) uint64_t timestamp;
@property (nonatomic, readonly) SignalServiceAddress *authorAddress;
@property (nonatomic, readonly, nullable) TSAttachmentStream *attachmentStream;
@property (nonatomic, readonly, nullable) TSAttachmentPointer *thumbnailAttachmentPointer;
@property (nonatomic, readonly) BOOL thumbnailDownloadFailed;

// This property should be set IFF we are quoting a text message
// or attachment with caption.
@property (nullable, nonatomic, readonly) NSString *body;
@property (nonatomic, readonly) BOOL isRemotelySourced;

#pragma mark - Attachments

// This is a MIME type.
//
// This property should be set IFF we are quoting an attachment message.
@property (nonatomic, readonly, nullable) NSString *contentType;
@property (nonatomic, readonly, nullable) NSString *sourceFilename;
@property (nonatomic, readonly, nullable) UIImage *thumbnailImage;

- (instancetype)init NS_UNAVAILABLE;

// Used for persisted quoted replies, both incoming and outgoing.
+ (instancetype)quotedReplyWithQuotedMessage:(TSQuotedMessage *)quotedMessage
                                 transaction:(SDSAnyReadTransaction *)transaction;

// Builds a not-yet-sent QuotedReplyModel
+ (nullable instancetype)quotedReplyForSendingWithConversationViewItem:(id<ConversationViewItem>)conversationItem
                                                           transaction:(SDSAnyReadTransaction *)transaction;

- (TSQuotedMessage *)buildQuotedMessageForSending;


@end

NS_ASSUME_NONNULL_END
