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
    [items addObject:[OWSTableItem itemWithTitle:@"Backup test file @ CloudKit"
                                     actionBlock:^{
                                         [DebugUIBackup backupTestFile];
                                     }]];

    return [OWSTableSection sectionWithTitle:self.name items:items];
}

+ (void)backupTestFile
{
    DDLogInfo(@"%@ backupTestFile.", self.logTag);

    NSData *_Nullable data = [Randomness generateRandomBytes:32];
    OWSAssert(data);
    NSString *filePath = [OWSFileSystem temporaryFilePathWithFileExtension:@"pdf"];
    BOOL success = [data writeToFile:filePath atomically:YES];
    OWSAssert(success);

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

@end

NS_ASSUME_NONNULL_END
