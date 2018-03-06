//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DebugUIBackup.h"
#import "OWSBackup.h"

//#import "OWSCountryMetadata.h"
#import "OWSTableViewController.h"

//#import "RegistrationViewController.h"
#import "Signal-Swift.h"

//#import "ThreadUtil.h"
//#import <AxolotlKit/PreKeyBundle.h>
//#import <SignalMessaging/AttachmentSharing.h>
//#import <SignalMessaging/Environment.h>
//#import <SignalMessaging/UIImage+OWS.h>
//#import <SignalServiceKit/OWSDisappearingConfigurationUpdateInfoMessage.h>
//#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
//#import <SignalServiceKit/OWSPrimaryStorage+SessionStore.h>
//#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
//#import <SignalServiceKit/SecurityUtils.h>
//#import <SignalServiceKit/TSCall.h>
//#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
//#import <SignalServiceKit/TSThread.h>
//#import <CloudKit/CloudKit.h>
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
                                              completion:^(NSError *_Nullable error){
                                                  // Do nothing, the API method will log for us.
                                              }];
        }
    }];
}

@end

NS_ASSUME_NONNULL_END
