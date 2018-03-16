//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMediaGalleryFinder.h"
#import "OWSStorage.h"
#import "TSAttachmentStream.h"
#import "TSMessage.h"
#import "TSThread.h"
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseTransaction.h>
#import <YapDatabase/YapDatabaseViewTypes.h>
#import <YapDatabase/YapWhitelistBlacklist.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const OWSMediaGalleryFinderExtensionName = @"OWSMediaGalleryFinderExtensionName";

@implementation OWSMediaGalleryFinder

#pragma mark - Public Finder Methods

-  (NSUInteger)mediaCountForThread:(TSThread *)thread transaction:(YapDatabaseReadTransaction *)transaction
{
    NSString *group = [self mediaGroupWithThreadId:thread.uniqueId];
    return [[self galleryExtensionWithTransaction:transaction] numberOfItemsInGroup:group];
}

- (NSUInteger)mediaIndexForMessage:(TSMessage *)message transaction:(YapDatabaseReadTransaction *)transaction
{
    NSString *groupId;
    NSUInteger index;

    BOOL wasFound = [[self galleryExtensionWithTransaction:transaction] getGroup:&groupId
                                                                           index:&index
                                                                          forKey:message.uniqueId
                                                                    inCollection:[TSMessage collection]];

    OWSAssert(wasFound);

    return index;
}

- (void)enumerateMediaMessagesWithThread:(TSThread *)thread
                             transaction:(YapDatabaseReadTransaction *)transaction
                                   block:(void (^)(TSMessage *))messageBlock
{
    NSString *group = [self mediaGroupWithThreadId:thread.uniqueId];
    [[self galleryExtensionWithTransaction:transaction]
        enumerateKeysAndObjectsInGroup:group
                            usingBlock:^(NSString *_Nonnull collection,
                                NSString *_Nonnull key,
                                id _Nonnull object,
                                NSUInteger index,
                                BOOL *_Nonnull stop) {
                                OWSAssert([object isKindOfClass:[TSMessage class]]);
                                messageBlock((TSMessage *)object);
                            }];
}

#pragma mark - Util

- (YapDatabaseAutoViewTransaction *)galleryExtensionWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    YapDatabaseAutoViewTransaction *extension = [transaction extension:OWSMediaGalleryFinderExtensionName];
    OWSAssert(extension);
    
    return extension;
}

+ (NSString *)mediaGroupWithThreadId:(NSString *)threadId
{
    return [NSString stringWithFormat:@"%@-media", threadId];
}

- (NSString *)mediaGroupWithThreadId:(NSString *)threadId
{
    return [[self class] mediaGroupWithThreadId:threadId];
}

#pragma mark - Extension registration

+ (void)asyncRegisterDatabaseExtensionsWithPrimaryStorage:(OWSStorage *)storage
{
    [storage asyncRegisterExtension:[self mediaGalleryDatabaseExtension]
                           withName:OWSMediaGalleryFinderExtensionName];
}

+ (YapDatabaseAutoView *)mediaGalleryDatabaseExtension
{
    YapDatabaseViewSorting *sorting = [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult(YapDatabaseReadTransaction * _Nonnull transaction, NSString * _Nonnull group, NSString * _Nonnull collection1, NSString * _Nonnull key1, id  _Nonnull object1, NSString * _Nonnull collection2, NSString * _Nonnull key2, id  _Nonnull object2) {
        
        if (![object1 isKindOfClass:[TSMessage class]]) {
            OWSFail(@"%@ Unexpected object while sorting: %@", self.logTag, [object1 class]);
            return NSOrderedSame;
        }
        TSMessage *message1 = (TSMessage *)object1;
        
        if (![object2 isKindOfClass:[TSMessage class]]) {
            OWSFail(@"%@ Unexpected object while sorting: %@", self.logTag, [object2 class]);
            return NSOrderedSame;
        }
        TSMessage *message2 = (TSMessage *)object2;
        
        return [@(message1.timestampForSorting) compare:@(message2.timestampForSorting)];
    }];
    
    YapDatabaseViewGrouping *grouping = [YapDatabaseViewGrouping withObjectBlock:^NSString * _Nullable(YapDatabaseReadTransaction * _Nonnull transaction, NSString * _Nonnull collection, NSString * _Nonnull key, id  _Nonnull object) {
        
        if (![object isKindOfClass:[TSMessage class]]) {
            return nil;
        }
        TSMessage *message = (TSMessage *)object;
        
        OWSAssert(message.attachmentIds.count <= 1);
        NSString *attachmentId = message.attachmentIds.firstObject;
        if (attachmentId.length == 0) {
            return nil;
        }
        
        if ([self attachmentIdShouldAppearInMediaGallery:attachmentId transaction:transaction]) {
            return [self mediaGroupWithThreadId:message.uniqueThreadId];
        }
        
        return nil;
    }];
    
    YapDatabaseViewOptions *options = [YapDatabaseViewOptions new];
    options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:TSMessage.collection]];
    
    return [[YapDatabaseAutoView alloc] initWithGrouping:grouping sorting:sorting versionTag:@"1" options:options];
}

+ (BOOL)attachmentIdShouldAppearInMediaGallery:(NSString *)attachmentId transaction:(YapDatabaseReadTransaction *)transaction
{
    TSAttachmentStream *attachment = [TSAttachmentStream fetchObjectWithUniqueID:attachmentId
                                                                     transaction:transaction];

    // Don't include nil or not yet downloaded attachments.
    if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
        return NO;
    }
    
    return attachment.isImage || attachment.isVideo || attachment.isAnimated;
}

@end

NS_ASSUME_NONNULL_END
