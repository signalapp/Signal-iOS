//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSFailedAttachmentDownloadsJob.h"
#import "OWSPrimaryStorage.h"
#import "TSAttachmentPointer.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseQuery.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const OWSFailedAttachmentDownloadsJobAttachmentStateColumn = @"state";
static NSString *const OWSFailedAttachmentDownloadsJobAttachmentStateIndex = @"index_attachment_downloads_on_state";

@interface OWSFailedAttachmentDownloadsJob ()

@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;

@end

#pragma mark -

@implementation OWSFailedAttachmentDownloadsJob

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];
    if (!self) {
        return self;
    }

    _primaryStorage = primaryStorage;

    return self;
}

- (NSArray<NSString *> *)fetchAttemptingOutAttachmentIdsWithTransaction:
    (YapDatabaseReadWriteTransaction *_Nonnull)transaction
{
    OWSAssertDebug(transaction);

    NSMutableArray<NSString *> *attachmentIds = [NSMutableArray new];

    NSString *formattedString = [NSString stringWithFormat:@"WHERE %@ != %d",
                                          OWSFailedAttachmentDownloadsJobAttachmentStateColumn,
                                          (int)TSAttachmentPointerStateFailed];
    YapDatabaseQuery *query = [YapDatabaseQuery queryWithFormat:formattedString];
    [[transaction ext:OWSFailedAttachmentDownloadsJobAttachmentStateIndex]
        enumerateKeysMatchingQuery:query
                        usingBlock:^void(NSString *collection, NSString *key, BOOL *stop) {
                            [attachmentIds addObject:key];
                        }];

    return [attachmentIds copy];
}

- (void)enumerateAttemptingOutAttachmentsWithBlock:(void (^_Nonnull)(TSAttachmentPointer *attachment))block
                                       transaction:(YapDatabaseReadWriteTransaction *_Nonnull)transaction
{
    OWSAssertDebug(transaction);

    // Since we can't directly mutate the enumerated attachments, we store only their ids in hopes
    // of saving a little memory and then enumerate the (larger) TSAttachment objects one at a time.
    for (NSString *attachmentId in [self fetchAttemptingOutAttachmentIdsWithTransaction:transaction]) {
        TSAttachmentPointer *_Nullable attachment =
            [TSAttachmentPointer anyFetchAttachmentPointerWithUniqueId:attachmentId transaction:transaction.asAnyRead];
        if (attachment == nil) {
            OWSFailDebug(@"Missing attachment.");
            continue;
        }
        block(attachment);
    }
}

- (void)run
{
    __block uint count = 0;
    [[self.primaryStorage newDatabaseConnection]
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            [self enumerateAttemptingOutAttachmentsWithBlock:^(TSAttachmentPointer *attachment) {
                // sanity check
                if (attachment.state != TSAttachmentPointerStateFailed) {
                    [attachment anyUpdateAttachmentPointerWithTransaction:transaction.asAnyWrite
                                                                    block:^(TSAttachmentPointer *attachment) {
                                                                        attachment.state
                                                                            = TSAttachmentPointerStateFailed;
                                                                    }];
                    count++;
                }
            }
                                                 transaction:transaction];
        }];

    OWSLogDebug(@"Marked %u attachments as unsent", count);
}

#pragma mark - YapDatabaseExtension

+ (YapDatabaseSecondaryIndex *)indexDatabaseExtension
{
    YapDatabaseSecondaryIndexSetup *setup = [YapDatabaseSecondaryIndexSetup new];
    [setup addColumn:OWSFailedAttachmentDownloadsJobAttachmentStateColumn
            withType:YapDatabaseSecondaryIndexTypeInteger];

    YapDatabaseSecondaryIndexHandler *handler =
        [YapDatabaseSecondaryIndexHandler withObjectBlock:^(YapDatabaseReadTransaction *transaction,
            NSMutableDictionary *dict,
            NSString *collection,
            NSString *key,
            id object) {
            if (![object isKindOfClass:[TSAttachmentPointer class]]) {
                return;
            }
            TSAttachmentPointer *attachment = (TSAttachmentPointer *)object;
            dict[OWSFailedAttachmentDownloadsJobAttachmentStateColumn] = @(attachment.state);
        }];

    return [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler versionTag:nil];
}

#ifdef DEBUG
// Useful for tests, don't use in app startup path because it's slow.
- (void)blockingRegisterDatabaseExtensions
{
    [self.primaryStorage registerExtension:[self.class indexDatabaseExtension]
                                  withName:OWSFailedAttachmentDownloadsJobAttachmentStateIndex];
}
#endif

+ (NSString *)databaseExtensionName
{
    return OWSFailedAttachmentDownloadsJobAttachmentStateIndex;
}

+ (void)asyncRegisterDatabaseExtensionsWithPrimaryStorage:(OWSStorage *)storage
{
    [storage asyncRegisterExtension:[self indexDatabaseExtension]
                           withName:OWSFailedAttachmentDownloadsJobAttachmentStateIndex];
}

@end

NS_ASSUME_NONNULL_END
