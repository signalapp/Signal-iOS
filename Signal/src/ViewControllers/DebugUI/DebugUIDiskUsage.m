//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUIDiskUsage.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/TSStorageManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIDiskUsage

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Disk Usage";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    return [OWSTableSection sectionWithTitle:self.name
                                       items:@[
                                           [OWSTableItem itemWithTitle:@"Log Disk Usage Stats"
                                                           actionBlock:^{
                                                               [DebugUIDiskUsage logDiskUsageStats];
                                                           }],
                                       ]];
}

+ (void)logDiskUsageStats
{
    NSString *attachmentsFolder = [TSAttachmentStream attachmentsFolder];
    DDLogError(@"attachmentsFolder: %@", attachmentsFolder);

    //    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    //    [storageManager.newDatabaseConnection
    //     readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
    //         [transaction enumerateKeysAndObjectsInCollection:TSAttachmentStream.collection
    //                                               usingBlock:^(NSString *key, TSAttachment *attachment, BOOL *stop) {
    //                                                   if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
    //                                                       return;
    //                                                   }
    //                                                   TSAttachmentStream *attachmentStream = (TSAttachmentStream
    //                                                   *)attachment; [attachmentStreams addObject:attachmentStream];
    //                                               }];
    //     }];
}

@end

NS_ASSUME_NONNULL_END
