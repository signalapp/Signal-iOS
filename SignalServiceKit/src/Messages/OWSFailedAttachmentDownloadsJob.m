//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSFailedAttachmentDownloadsJob.h"
#import "TSAttachmentPointer.h"
#import "TSStorageManager.h"
#import <YapDatabase/YapDatabaseConnection.h>
#import <YapDatabase/YapDatabaseQuery.h>
#import <YapDatabase/YapDatabaseSecondaryIndex.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const OWSFailedAttachmentDownloadsJobAttachmentStateColumn = @"state";
static NSString *const OWSFailedAttachmentDownloadsJobAttachmentStateIndex = @"index_attachment_downloads_on_state";

@interface OWSFailedAttachmentDownloadsJob ()

@property (nonatomic, readonly) TSStorageManager *storageManager;

@end

#pragma mark -

@implementation OWSFailedAttachmentDownloadsJob

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _storageManager = storageManager;

    return self;
}

- (NSArray<NSString *> *)fetchAttemptingOutAttachmentIdsWithTransaction:
    (YapDatabaseReadWriteTransaction *_Nonnull)transaction
{
    OWSAssert(transaction);

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
    OWSAssert(transaction);

    // Since we can't directly mutate the enumerated attachments, we store only their ids in hopes
    // of saving a little memory and then enumerate the (larger) TSAttachment objects one at a time.
    for (NSString *attachmentId in [self fetchAttemptingOutAttachmentIdsWithTransaction:transaction]) {
        TSAttachmentPointer *_Nullable attachment =
            [TSAttachmentPointer fetchObjectWithUniqueID:attachmentId transaction:transaction];
        if ([attachment isKindOfClass:[TSAttachmentPointer class]]) {
            block(attachment);
        } else {
            DDLogError(@"%@ unexpected object: %@", self.tag, attachment);
        }
    }
}

- (void)run
{
    __block uint count = 0;
    [[self.storageManager newDatabaseConnection]
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            [self enumerateAttemptingOutAttachmentsWithBlock:^(TSAttachmentPointer *attachment) {
                // sanity check
                if (attachment.state != TSAttachmentPointerStateFailed) {
                    DDLogDebug(@"%@ marking attachment as failed", self.tag);
                    attachment.state = TSAttachmentPointerStateFailed;
                    [attachment saveWithTransaction:transaction];
                    count++;
                }
            }
                                                 transaction:transaction];
        }];

    DDLogDebug(@"%@ Marked %u attachments as unsent", self.tag, count);
}

#pragma mark - YapDatabaseExtension

- (YapDatabaseSecondaryIndex *)indexDatabaseExtension
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

    return [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup handler:handler];
}

// Useful for tests, don't use in app startup path because it's slow.
- (void)blockingRegisterDatabaseExtensions
{
    [self.storageManager.database registerExtension:[self indexDatabaseExtension]
                                           withName:OWSFailedAttachmentDownloadsJobAttachmentStateIndex];
}

- (void)asyncRegisterDatabaseExtensions
{
    [self.storageManager.database asyncRegisterExtension:[self indexDatabaseExtension]
                                                withName:OWSFailedAttachmentDownloadsJobAttachmentStateIndex
                                         completionBlock:^(BOOL ready) {
                                             if (ready) {
                                                 DDLogDebug(@"%@ completed registering extension async.", self.tag);
                                             } else {
                                                 DDLogError(@"%@ failed registering extension async.", self.tag);
                                             }
                                         }];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
