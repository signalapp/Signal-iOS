//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugUIBackup.h"
#import "OWSBackup.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import <Curve25519Kit/Randomness.h>

@import CloudKit;

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIBackup

#pragma mark - Factory Methods

- (NSString *)name
{
    return @"Backup";
}

- (nullable OWSTableSection *)sectionForThread:(nullable TSThread *)thread
{
    NSMutableArray<OWSTableItem *> *items = [NSMutableArray new];
    [items addObject:[OWSTableItem itemWithTitle:@"Backup test file to CloudKit"
                                     actionBlock:^{
                                         [DebugUIBackup backupTestFile];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Check for CloudKit backup"
                                     actionBlock:^{
                                         [DebugUIBackup checkForBackup];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Log CloudKit backup records"
                                     actionBlock:^{
                                         [DebugUIBackup logBackupRecords];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Restore CloudKit backup"
                                     actionBlock:^{
                                         [DebugUIBackup tryToImportBackup];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Log Database Size Stats"
                                     actionBlock:^{
                                         [DebugUIBackup logDatabaseSizeStats];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Clear All CloudKit Records"
                                     actionBlock:^{
                                         [DebugUIBackup clearAllCloudKitRecords];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Clear Backup Metadata Cache"
                                     actionBlock:^{
                                         [DebugUIBackup clearBackupMetadataCache];
                                     }]];

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (void)backupTestFile
{
    OWSLogInfo(@"backupTestFile.");

    NSData *_Nullable data = [Randomness generateRandomBytes:32];
    OWSAssertDebug(data);
    NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:@"pdf"];
    BOOL success = [data writeToFile:filePath atomically:YES];
    OWSAssertDebug(success);

    [OWSBackupAPI checkCloudKitAccessWithCompletion:^(BOOL hasAccess) {
        if (hasAccess) {
            [OWSBackupAPI saveTestFileToCloudWithFileUrl:[NSURL fileURLWithPath:filePath]
                                                 success:^(NSString *recordName) {
                                                     // Do nothing, the API method will log for us.
                                                 }
                                                 failure:^(NSError *error){
                                                     // Do nothing, the API method will log for us.
                                                 }];
        }
    }];
}

+ (void)checkForBackup
{
    OWSLogInfo(@"checkForBackup.");

    [OWSBackup.sharedManager
        checkCanImportBackup:^(BOOL value) {
            OWSLogInfo(@"has backup available  for import? %d", value);
        }
                     failure:^(NSError *error){
                         // Do nothing.
                     }];
}

+ (void)logBackupRecords
{
    OWSLogInfo(@"logBackupRecords.");

    [OWSBackup.sharedManager logBackupRecords];
}

+ (void)tryToImportBackup
{
    OWSLogInfo(@"tryToImportBackup.");

    UIAlertController *controller =
        [UIAlertController alertControllerWithTitle:@"Restore CloudKit Backup"
                                            message:@"This will delete all of your database contents."
                                     preferredStyle:UIAlertControllerStyleAlert];

    [controller addAction:[UIAlertAction actionWithTitle:@"Restore"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                     [OWSBackup.sharedManager tryToImportBackup];
                                                 }]];
    [controller addAction:[OWSAlerts cancelAction]];
    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentViewController:controller animated:YES completion:nil];
}

+ (void)logDatabaseSizeStats
{
    OWSLogInfo(@"logDatabaseSizeStats.");

    __block unsigned long long interactionCount = 0;
    __block unsigned long long interactionSizeTotal = 0;
    __block unsigned long long attachmentCount = 0;
    __block unsigned long long attachmentSizeTotal = 0;
    [[OWSPrimaryStorage.sharedManager newDatabaseConnection] readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [transaction enumerateKeysAndObjectsInCollection:[TSInteraction collection]
                                              usingBlock:^(NSString *key, id object, BOOL *stop) {
                                                  TSInteraction *interaction = object;
                                                  interactionCount++;
                                                  NSData *_Nullable data =
                                                      [NSKeyedArchiver archivedDataWithRootObject:interaction];
                                                  OWSAssertDebug(data);
                                                  ows_add_overflow(
                                                      interactionSizeTotal, data.length, &interactionSizeTotal);
                                              }];
        [transaction enumerateKeysAndObjectsInCollection:[TSAttachment collection]
                                              usingBlock:^(NSString *key, id object, BOOL *stop) {
                                                  TSAttachment *attachment = object;
                                                  attachmentCount++;
                                                  NSData *_Nullable data =
                                                      [NSKeyedArchiver archivedDataWithRootObject:attachment];
                                                  OWSAssertDebug(data);
                                                  ows_add_overflow(
                                                      attachmentSizeTotal, data.length, &attachmentSizeTotal);
                                              }];
    }];

    OWSLogInfo(@"interactionCount: %llu", interactionCount);
    OWSLogInfo(@"interactionSizeTotal: %llu", interactionSizeTotal);
    if (interactionCount > 0) {
        OWSLogInfo(@"interaction average size: %f", interactionSizeTotal / (double)interactionCount);
    }
    OWSLogInfo(@"attachmentCount: %llu", attachmentCount);
    OWSLogInfo(@"attachmentSizeTotal: %llu", attachmentSizeTotal);
    if (attachmentCount > 0) {
        OWSLogInfo(@"attachment average size: %f", attachmentSizeTotal / (double)attachmentCount);
    }
}

+ (void)clearAllCloudKitRecords
{
    OWSLogInfo(@"clearAllCloudKitRecords.");

    [OWSBackup.sharedManager clearAllCloudKitRecords];
}

+ (void)clearBackupMetadataCache
{
    OWSLogInfo(@"ClearBackupMetadataCache.");

    [OWSPrimaryStorage.sharedManager.newDatabaseConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [transaction removeAllObjectsInCollection:[OWSBackupFragment collection]];
        }];
}

@end

NS_ASSUME_NONNULL_END
