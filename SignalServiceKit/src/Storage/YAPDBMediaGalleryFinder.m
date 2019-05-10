//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "YAPDBMediaGalleryFinder.h"
#import "OWSStorage.h"
#import "TSAttachmentStream.h"
#import "TSMessage.h"
#import "TSThread.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import <YapDatabase/YapDatabaseViewTypes.h>
#import <YapDatabase/YapWhitelistBlacklist.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const YAPDBMediaGalleryFinderExtensionName = @"YAPDBMediaGalleryFinderExtensionName";

@interface YAPDBMediaGalleryFinder ()

@property (nonatomic, readonly) TSThread *thread;

@end

@implementation YAPDBMediaGalleryFinder

- (instancetype)initWithThread:(TSThread *)thread
{
    self = [super init];
    if (!self) {
        return self;
    }

    _thread = thread;

    return self;
}

#pragma mark - Public Finder Methods

- (NSUInteger)mediaCountWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [[self galleryExtensionWithTransaction:transaction] numberOfItemsInGroup:self.mediaGroup];
}

- (nullable NSNumber *)mediaIndexForAttachment:(TSAttachment *)attachment
                                   transaction:(YapDatabaseReadTransaction *)transaction
{
    NSString *groupId;
    NSUInteger index;

    BOOL wasFound = [[self galleryExtensionWithTransaction:transaction] getGroup:&groupId
                                                                           index:&index
                                                                          forKey:attachment.uniqueId
                                                                    inCollection:[TSAttachment collection]];

    if (!wasFound) {
        return nil;
    }

    OWSAssertDebug([self.mediaGroup isEqual:groupId]);

    return @(index);
}

- (nullable TSAttachment *)oldestMediaAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [[self galleryExtensionWithTransaction:transaction] firstObjectInGroup:self.mediaGroup];
}

- (nullable TSAttachment *)mostRecentMediaAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    return [[self galleryExtensionWithTransaction:transaction] lastObjectInGroup:self.mediaGroup];
}

- (void)enumerateMediaAttachmentsWithRange:(NSRange)range
                               transaction:(YapDatabaseReadTransaction *)transaction
                                     block:(void (^)(TSAttachment *))attachmentBlock
{

    [[self galleryExtensionWithTransaction:transaction]
        enumerateKeysAndObjectsInGroup:self.mediaGroup
                           withOptions:0
                                 range:range
                            usingBlock:^(NSString *_Nonnull collection,
                                NSString *_Nonnull key,
                                id _Nonnull object,
                                NSUInteger index,
                                BOOL *_Nonnull stop) {
                                OWSAssertDebug([object isKindOfClass:[TSAttachment class]]);
                                attachmentBlock((TSAttachment *)object);
                            }];
}

- (BOOL)hasMediaChangesInNotifications:(NSArray<NSNotification *> *)notifications
                          dbConnection:(YapDatabaseConnection *)dbConnection
{
    YapDatabaseAutoViewConnection *extConnection = [dbConnection ext:YAPDBMediaGalleryFinderExtensionName];
    OWSAssert(extConnection);

    return [extConnection hasChangesForGroup:self.mediaGroup inNotifications:notifications];
}

#pragma mark - Util

- (YapDatabaseAutoViewTransaction *)galleryExtensionWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    YapDatabaseAutoViewTransaction *extension = [transaction extension:YAPDBMediaGalleryFinderExtensionName];
    OWSAssertDebug(extension);

    return extension;
}

+ (NSString *)mediaGroupWithThreadId:(NSString *)threadId
{
    return [NSString stringWithFormat:@"%@-media", threadId];
}

- (NSString *)mediaGroup
{
    return [[self class] mediaGroupWithThreadId:self.thread.uniqueId];
}

#pragma mark - Extension registration

+ (NSString *)databaseExtensionName
{
    return YAPDBMediaGalleryFinderExtensionName;
}

+ (void)asyncRegisterDatabaseExtensionsWithPrimaryStorage:(OWSStorage *)storage
{
    [storage asyncRegisterExtension:[self mediaGalleryDatabaseExtension] withName:YAPDBMediaGalleryFinderExtensionName];
}

+ (YapDatabaseAutoView *)mediaGalleryDatabaseExtension
{
    YapDatabaseViewSorting *sorting =
        [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult(YapDatabaseReadTransaction *_Nonnull transaction,
            NSString *_Nonnull group,
            NSString *_Nonnull collection1,
            NSString *_Nonnull key1,
            id _Nonnull object1,
            NSString *_Nonnull collection2,
            NSString *_Nonnull key2,
            id _Nonnull object2) {
            if (![object1 isKindOfClass:[TSAttachment class]]) {
                OWSFailDebug(@"Unexpected object while sorting: %@", [object1 class]);
                return NSOrderedSame;
            }
            TSAttachment *attachment1 = (TSAttachment *)object1;

            if (![object2 isKindOfClass:[TSAttachment class]]) {
                OWSFailDebug(@"Unexpected object while sorting: %@", [object2 class]);
                return NSOrderedSame;
            }
            TSAttachment *attachment2 = (TSAttachment *)object2;

            TSMessage *_Nullable message1 = [attachment1 fetchAlbumMessageWithTransaction:transaction.asAnyRead];
            TSMessage *_Nullable message2 = [attachment2 fetchAlbumMessageWithTransaction:transaction.asAnyRead];
            if (message1 == nil || message2 == nil) {
                OWSFailDebug(@"couldn't find albumMessage");
                return NSOrderedSame;
            }

            if ([message1.uniqueId isEqualToString:message2.uniqueId]) {
                NSUInteger index1 = [message1.attachmentIds indexOfObject:attachment1.uniqueId];
                NSUInteger index2 = [message1.attachmentIds indexOfObject:attachment2.uniqueId];

                if (index1 == NSNotFound || index2 == NSNotFound) {
                    OWSFailDebug(@"couldn't find attachmentId in it's albumMessage");
                    return NSOrderedSame;
                }
                return [@(index1) compare:@(index2)];
            } else {
                return [message1 compareForSorting:message2];
            }
        }];

    YapDatabaseViewGrouping *grouping =
        [YapDatabaseViewGrouping withObjectBlock:^NSString *_Nullable(YapDatabaseReadTransaction *_Nonnull transaction,
            NSString *_Nonnull collection,
            NSString *_Nonnull key,
            id _Nonnull object) {
            // Don't include nil or not yet downloaded attachments.
            if (![object isKindOfClass:[TSAttachmentStream class]]) {
                return nil;
            }

            TSAttachmentStream *attachment = (TSAttachmentStream *)object;
            if (attachment.albumMessageId == nil) {
                return nil;
            }

            if (!attachment.isValidVisualMedia) {
                return nil;
            }

            TSMessage *message = [attachment fetchAlbumMessageWithTransaction:transaction.asAnyRead];
            if (message == nil) {
                OWSFailDebug(@"message was unexpectedly nil");
                return nil;
            }

            return [self mediaGroupWithThreadId:message.uniqueThreadId];
        }];

    YapDatabaseViewOptions *options = [YapDatabaseViewOptions new];
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:TSAttachment.collection]];

    return [[YapDatabaseAutoView alloc] initWithGrouping:grouping sorting:sorting versionTag:@"4" options:options];
}

@end

NS_ASSUME_NONNULL_END
