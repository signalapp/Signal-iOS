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

    __block int fileCount = 0;
    __block long long totalFileSize = 0;
    NSMutableSet *diskFilePaths = [NSMutableSet new];
    __unsafe_unretained __block void (^visitAttachmentFilesRecursable)(NSString *);
    void (^visitAttachmentFiles)(NSString *);
    visitAttachmentFiles = ^(NSString *dirPath) {
        NSError *error;
        NSArray<NSString *> *fileNames =
            [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirPath error:&error];
        if (error) {
            OWSFail(@"contentsOfDirectoryAtPath error: %@", error);
        }
        for (NSString *fileName in fileNames) {
            NSString *filePath = [dirPath stringByAppendingPathComponent:fileName];
            BOOL isDirectory;
            [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory];
            if (isDirectory) {
                visitAttachmentFilesRecursable(filePath);
            } else {
                NSNumber *fileSize =
                    [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error][NSFileSize];
                if (error) {
                    OWSFail(@"attributesOfItemAtPath: %@ error: %@", filePath, error);
                }
                totalFileSize += fileSize.longLongValue;
                fileCount++;
                [diskFilePaths addObject:filePath];
            }
        }
    };
    visitAttachmentFilesRecursable = visitAttachmentFiles;
    visitAttachmentFiles(attachmentsFolder);

    __block int attachmentStreamCount = 0;
    NSMutableSet *attachmentFilePaths = [NSMutableSet new];
    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    [storageManager.newDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [transaction enumerateKeysAndObjectsInCollection:TSAttachmentStream.collection
                                              usingBlock:^(NSString *key, TSAttachment *attachment, BOOL *stop) {
                                                  if (![attachment isKindOfClass:[TSAttachmentStream class]]) {
                                                      return;
                                                  }
                                                  TSAttachmentStream *attachmentStream
                                                      = (TSAttachmentStream *)attachment;
                                                  attachmentStreamCount++;
                                                  NSString *_Nullable filePath = [attachmentStream filePath];
                                                  OWSAssert(filePath);
                                                  [attachmentFilePaths addObject:filePath];
                                              }];
    }];

    DDLogError(@"fileCount: %d", fileCount);
    DDLogError(@"totalFileSize: %lld", totalFileSize);
    DDLogError(@"attachmentStreams: %d", attachmentStreamCount);
    DDLogError(@"attachmentStreams with file paths: %zd", attachmentFilePaths.count);

    NSMutableSet *orphanDiskFilePaths = [diskFilePaths mutableCopy];
    [orphanDiskFilePaths minusSet:attachmentFilePaths];
    NSMutableSet *missingAttachmentFilePaths = [attachmentFilePaths mutableCopy];
    [missingAttachmentFilePaths minusSet:diskFilePaths];

    DDLogError(@"orphan disk file paths: %zd", orphanDiskFilePaths.count);
    DDLogError(@"missing attachment file paths: %zd", missingAttachmentFilePaths.count);

    [self printPaths:orphanDiskFilePaths.allObjects label:@"orphan disk file paths"];
    [self printPaths:missingAttachmentFilePaths.allObjects label:@"missing attachment file paths"];
}

+ (void)printPaths:(NSArray<NSString *> *)paths label:(NSString *)label
{
    for (NSString *path in [paths sortedArrayUsingSelector:@selector(compare:)]) {
        DDLogError(@"%@: %@", label, path);
    }
}

@end

NS_ASSUME_NONNULL_END
