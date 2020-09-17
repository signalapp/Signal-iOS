//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "DebugUIBackup.h"
#import "OWSBackup.h"
#import "OWSTableViewController.h"
#import "Signal-Swift.h"
#import <CloudKit/CloudKit.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/Randomness.h>

#ifdef DEBUG

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIBackup

#pragma mark - Dependencies

+ (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

+ (OWSBackup *)backup
{
    OWSAssertDebug(AppEnvironment.shared.backup);

    return AppEnvironment.shared.backup;
}

+ (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

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
    [items addObject:[OWSTableItem itemWithTitle:@"Log CloudKit backup manifests"
                                     actionBlock:^{
                                         [DebugUIBackup logBackupManifests];
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
    [items addObject:[OWSTableItem itemWithTitle:@"Log Backup Metadata Cache"
                                     actionBlock:^{
                                         [DebugUIBackup logBackupMetadataCache];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Lazy Restore Attachments"
                                     actionBlock:^{
                                         [AppEnvironment.shared.backupLazyRestore runIfNecessary];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Upload 100 CK records"
                                     actionBlock:^{
                                         [DebugUIBackup uploadCKBatch:100];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Upload 1,000 CK records"
                                     actionBlock:^{
                                         [DebugUIBackup uploadCKBatch:1000];
                                     }]];
    [items addObject:[OWSTableItem itemWithTitle:@"Upload 10,000 CK records"
                                     actionBlock:^{
                                         [DebugUIBackup uploadCKBatch:10000];
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

    NSString *recipientId = self.tsAccountManager.localNumber;
    NSString *recordName = [OWSBackupAPI recordNameForTestFileWithRecipientId:recipientId];
    CKRecord *record = [OWSBackupAPI recordForFileUrl:[NSURL fileURLWithPath:filePath] recordName:recordName];

    [self.backup ensureCloudKitAccess].thenInBackground(^{
        return [OWSBackupAPI saveRecordsToCloudObjcWithRecords:@[ record ]];
    });
}

+ (void)checkForBackup
{
    OWSLogInfo(@"checkForBackup.");

    [OWSBackup.shared
        checkCanImportBackup:^(BOOL value) { OWSLogInfo(@"has backup available for import? %d", value); }
                     failure:^(NSError *error) {
                         // Do nothing.
                     }];
}

+ (void)logBackupRecords
{
    OWSLogInfo(@"logBackupRecords.");

    [OWSBackup.shared logBackupRecords];
}

+ (void)logBackupManifests
{
    OWSLogInfo(@"logBackupManifests.");

    [OWSBackup.shared
        allRecipientIdsWithManifestsInCloud:^(
            NSArray<NSString *> *recipientIds) { OWSLogInfo(@"recipientIds: %@", recipientIds); }
        failure:^(NSError *error) { OWSLogError(@"error: %@", error); }];
}

+ (void)tryToImportBackup
{
    OWSLogInfo(@"tryToImportBackup.");

    ActionSheetController *alert =
        [[ActionSheetController alloc] initWithTitle:@"Restore CloudKit Backup"
                                             message:@"This will delete all of your database contents."];

    [alert addAction:[[ActionSheetAction alloc] initWithTitle:@"Restore"
                                                        style:ActionSheetActionStyleDefault
                                                      handler:^(ActionSheetAction *_Nonnull action) {
                                                          [OWSBackup.shared tryToImportBackup];
                                                      }]];
    [alert addAction:[OWSActionSheets cancelAction]];
    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentActionSheet:alert];
}

+ (void)logDatabaseSizeStats
{
    OWSLogInfo(@"logDatabaseSizeStats.");

    __block unsigned long long interactionCount = 0;
    __block unsigned long long interactionSizeTotal = 0;
    __block unsigned long long attachmentCount = 0;
    __block unsigned long long attachmentSizeTotal = 0;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        [TSInteraction
            anyEnumerateWithTransaction:transaction
                                batched:YES
                                  block:^(TSInteraction *interaction, BOOL *stop) {
                                      interactionCount++;
                                      NSData *_Nullable data = [NSKeyedArchiver archivedDataWithRootObject:interaction];
                                      OWSAssertDebug(data);
                                      ows_add_overflow(interactionSizeTotal, data.length, &interactionSizeTotal);
                                  }];
        [TSAttachment
            anyEnumerateWithTransaction:transaction
                                batched:YES
                                  block:^(TSAttachment *attachment, BOOL *stop) {
                                      attachmentCount++;
                                      NSData *_Nullable data = [NSKeyedArchiver archivedDataWithRootObject:attachment];
                                      OWSAssertDebug(data);
                                      ows_add_overflow(attachmentSizeTotal, data.length, &attachmentSizeTotal);
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
    OWSLogInfo(@"");

    [OWSBackup.shared clearAllCloudKitRecords];
}

+ (void)clearBackupMetadataCache
{
    OWSLogInfo(@"");

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [OWSBackupFragment anyRemoveAllWithInstantationWithTransaction:transaction];
    });
}

+ (void)logBackupMetadataCache
{
    [self.backup logBackupMetadataCache];
}

+ (void)uploadCKBatch:(NSUInteger)count
{
    NSMutableArray<CKRecord *> *records = [NSMutableArray new];
    for (NSUInteger i = 0; i < count; i++) {
        NSData *_Nullable data = [Randomness generateRandomBytes:32];
        OWSAssertDebug(data);
        NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:@"pdf"];
        BOOL success = [data writeToFile:filePath atomically:YES];
        OWSAssertDebug(success);

        NSString *recipientId = self.tsAccountManager.localNumber;
        NSString *recordName = [OWSBackupAPI recordNameForTestFileWithRecipientId:recipientId];
        CKRecord *record = [OWSBackupAPI recordForFileUrl:[NSURL fileURLWithPath:filePath] recordName:recordName];
        [records addObject:record];
    }
    [OWSBackupAPI saveRecordsToCloudObjcWithRecords:records].thenInBackground(^{
        OWSLogVerbose(@"success.");
    });
}

@end

NS_ASSUME_NONNULL_END

#endif
