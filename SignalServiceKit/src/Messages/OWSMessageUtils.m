//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageUtils.h"
#import "AppContext.h"
#import "OWSPrimaryStorage.h"
#import "TSAccountManager.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSDatabaseView.h"
#import "TSIncomingMessage.h"
#import "TSMessage.h"
#import "TSOutgoingMessage.h"
#import "TSQuotedMessage.h"
#import "TSThread.h"
#import "UIImage+OWS.h"
#import <YapDatabase/YapDatabase.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSMessageUtils ()

@property (nonatomic, readonly) YapDatabaseConnection *dbConnection;

@end

#pragma mark -

@implementation OWSMessageUtils

+ (instancetype)sharedManager
{
    static OWSMessageUtils *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    OWSPrimaryStorage *primaryStorage = [OWSPrimaryStorage sharedManager];

    return [self initWithPrimaryStorage:primaryStorage];
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];

    if (!self) {
        return self;
    }

    _dbConnection = primaryStorage.newDatabaseConnection;

    OWSSingletonAssert();

    return self;
}

- (NSUInteger)unreadMessagesCount
{
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        numberOfItems = [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInAllGroups];
    }];

    return numberOfItems;
}

- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread
{
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        id databaseView = [transaction ext:TSUnreadDatabaseViewExtensionName];
        OWSAssert(databaseView);
        numberOfItems = ([databaseView numberOfItemsInAllGroups] - [databaseView numberOfItemsInGroup:thread.uniqueId]);
    }];

    return numberOfItems;
}

- (void)updateApplicationBadgeCount
{
    if (!CurrentAppContext().isMainApp) {
        return;
    }

    NSUInteger numberOfItems = [self unreadMessagesCount];
    [CurrentAppContext() setMainAppBadgeNumber:numberOfItems];
}

- (NSUInteger)unreadMessagesInThread:(TSThread *)thread
{
    __block NSUInteger numberOfItems;
    [self.dbConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        numberOfItems = [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInGroup:thread.uniqueId];
    }];
    return numberOfItems;
}

+ (nullable TSQuotedMessage *)quotedMessageForMessage:(TSMessage *)message
                                          transaction:(YapDatabaseReadTransaction *)transaction;
{
    OWSAssert(message);
    OWSAssert(transaction);

    TSThread *thread = [message threadWithTransaction:transaction];

    NSString *_Nullable authorId = ^{
        if ([message isKindOfClass:[TSOutgoingMessage class]]) {
            return [TSAccountManager localNumber];
        } else if ([message isKindOfClass:[TSIncomingMessage class]]) {
            return [(TSIncomingMessage *)message authorId];
        } else {
            OWSFail(@"%@ Unexpected message type: %@", self.logTag, message.class);
            return (NSString * _Nullable) nil;
        }
    }();
    OWSAssert(authorId.length > 0);

    return [self quotedMessageForMessage:message authorId:authorId thread:thread transaction:transaction];
}

+ (nullable TSQuotedMessage *)quotedMessageForMessage:(TSMessage *)message
                                             authorId:(NSString *)authorId
                                               thread:(TSThread *)thread
                                          transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(message);
    OWSAssert(authorId.length > 0);
    OWSAssert(thread);
    OWSAssert(transaction);

    uint64_t timestamp = message.timestamp;
    NSString *_Nullable body = message.body;
    BOOL hasText = body.length > 0;
    BOOL hasAttachment = NO;
    NSString *_Nullable sourceFilename = nil;
    NSData *_Nullable thumbnailData = nil;
    NSString *_Nullable contentType = nil;

    if (message.attachmentIds.count > 0) {
        NSString *attachmentId = message.attachmentIds[0];
        TSAttachment *_Nullable attachment =
            [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
        if (attachment) {
            sourceFilename = attachment.sourceFilename;
            contentType = attachment.contentType;
            // Try to generate a thumbnail, if possible.
            thumbnailData = [self thumbnailDataForAttachment:attachment];
            hasAttachment = YES;
        }
    }

    if (!hasText && !hasAttachment) {
        OWSFail(@"%@ quoted message has neither text nor attachment", self.logTag);
        return nil;
    }

    TSQuotedMessage *quotedMessage = [[TSQuotedMessage alloc] initWithTimestamp:timestamp
                                                                       authorId:authorId
                                                                           body:body
                                                                 sourceFilename:sourceFilename
                                                                  thumbnailData:thumbnailData
                                                                    contentType:contentType];
    return quotedMessage;
}

+ (nullable NSData *)thumbnailDataForAttachment:(TSAttachment *)attachment
{
    OWSAssert(attachment);

    // Try to generate a thumbnail, if possible.
    if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
        return nil;
    }

    TSAttachmentStream *attachmentStream = (TSAttachmentStream *)attachment;
    UIImage *_Nullable attachmentImage = [attachmentStream image];
    if (!attachmentImage) {
        return nil;
    }

    CGSize attachmentImageSizePx;
    attachmentImageSizePx.width = CGImageGetWidth(attachmentImage.CGImage);
    attachmentImageSizePx.height = CGImageGetHeight(attachmentImage.CGImage);
    if (attachmentImageSizePx.width <= 0 || attachmentImageSizePx.height <= 0) {
        DDLogError(@"%@ attachment thumbnail has invalid size.", self.logTag);
        return nil;
    }

    // TODO: Revisit this value.
    const int kMaxThumbnailSizePx = 100;

    // Try to resize image to thumbnail if necessary.
    if (attachmentImageSizePx.width > kMaxThumbnailSizePx || attachmentImageSizePx.height > kMaxThumbnailSizePx) {
        const CGFloat widthFactor = kMaxThumbnailSizePx / attachmentImageSizePx.width;
        const CGFloat heightFactor = kMaxThumbnailSizePx / attachmentImageSizePx.height;
        const CGFloat scalingFactor = MIN(widthFactor, heightFactor);
        const CGFloat scaledWidthPx = (CGFloat)round(attachmentImageSizePx.width * scalingFactor);
        const CGFloat scaledHeightPx = (CGFloat)round(attachmentImageSizePx.height * scalingFactor);

        if (scaledWidthPx <= 0 || scaledHeightPx <= 0) {
            DDLogError(@"%@ can't determined desired size for attachment thumbnail.", self.logTag);
            return nil;
        }

        if (scaledWidthPx > 0 && scaledHeightPx > 0) {
            attachmentImage = [attachmentImage resizedImageToSize:CGSizeMake(scaledWidthPx, scaledHeightPx)];
            if (!attachmentImage) {
                DDLogError(@"%@ attachment thumbnail could not be resized.", self.logTag);
                return nil;
            }

            attachmentImageSizePx.width = CGImageGetWidth(attachmentImage.CGImage);
            attachmentImageSizePx.height = CGImageGetHeight(attachmentImage.CGImage);
        }
    }

    if (attachmentImageSizePx.width <= 0 || attachmentImageSizePx.height <= 0) {
        DDLogError(@"%@ resized attachment thumbnail has invalid size.", self.logTag);
        return nil;
    }

    NSData *_Nullable attachmentImageData = UIImagePNGRepresentation(attachmentImage);
    if (!attachmentImage) {
        OWSFail(@"%@ attachment thumbnail could not be written to PNG.", self.logTag);
        return nil;
    }
    return attachmentImageData;
}

@end

NS_ASSUME_NONNULL_END
