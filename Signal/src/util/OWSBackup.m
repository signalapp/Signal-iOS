//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackup.h"
#import "NSUserDefaults+OWS.h"
#import "Signal-Swift.h"
#import "zlib.h"
#import <SSZipArchive/SSZipArchive.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSStorageManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSStorage (OWSBackup)

- (NSData *)databasePassword;

@end

#pragma mark -

@interface OWSBackup ()

@property (nonatomic) NSString *password;
@property (nonatomic) NSString *rootDirPath;
@property (atomic) BOOL cancelled;

@end

#pragma mark -

@implementation OWSBackup

- (void)dealloc
{
    OWSAssert(self.rootDirPath.length > 0);

    DDLogInfo(@"%@ Cleaning up: %@", self.logTag, self.rootDirPath);
    [OWSFileSystem deleteFileIfExists:self.rootDirPath];
}

+ (void)exportDatabase
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OWSBackup new] showBackupUI];
    });
}

- (void)showBackupUI
{
    // TODO: Should the user pick a password?
    NSString *password = [NSUUID UUID].UUIDString;
    self.password = password;
    DDLogVerbose(@"%@ backup export complete; password: %@", self.logTag, password);

    [self showExportProgressUI:^(UIAlertController *exportProgressAlert) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self exportDatabase];

            dispatch_async(dispatch_get_main_queue(), ^{
                [exportProgressAlert
                    dismissViewControllerAnimated:YES
                                       completion:^{
                                           [self showExportCompleteUI:^(UIAlertController *exportCompleteAlert){
                                           }];
                                       }];
            });
        });
    }];
}

- (void)showExportProgressUI:(void (^_Nonnull)(UIAlertController *))completion
{
    OWSAssert(completion);
    OWSAssert(self.password.length > 0);

    NSString *title = NSLocalizedString(
        @"BACKUP_EXPORT_IN_PROGRESS_ALERT_TITLE", @"Title for the 'backup export in progress' alert.");
    NSString *message = [NSString
        stringWithFormat:
            NSLocalizedString(@"BACKUP_EXPORT_IN_PROGRESS_MESSAGE_ALERT_FORMAT",
                @"Format for message for the 'backup export in progress' alert. Embeds: {{the backup password}}"),
        self.password];
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[CommonStrings cancelButton]
                                                           style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction *_Nonnull action) {
                                                             self.cancelled = YES;
                                                         }];
    [alert addAction:cancelAction];

    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentViewController:alert
                                     animated:YES
                                   completion:^(void) {
                                       completion(alert);
                                   }];
}

- (void)showExportCompleteUI:(void (^_Nonnull)(UIAlertController *))completion
{
    OWSAssert(completion);
    OWSAssert(self.password.length > 0);

    NSString *title
        = NSLocalizedString(@"BACKUP_EXPORT_COMPLETE_ALERT_TITLE", @"Title for the 'backup export complete' alert.");
    NSString *message = [NSString
        stringWithFormat:
            NSLocalizedString(@"BACKUP_EXPORT_COMPLETE_ALERT_MESSAGE_FORMAT",
                @"Format for message for the 'backup export complete' alert. Embeds: {{the backup password}}"),
        self.password];
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:[CommonStrings dismissButton]
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                              self.cancelled = YES;
                                                          }];
    [alert addAction:dismissAction];

    UIViewController *fromViewController = [[UIApplication sharedApplication] frontmostViewController];
    [fromViewController presentViewController:alert
                                     animated:YES
                                   completion:^(void) {
                                       completion(alert);
                                   }];
}

- (void)exportDatabase
{
    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *backupName = [NSUUID UUID].UUIDString;
    NSString *rootDirPath = [temporaryDirectory stringByAppendingPathComponent:backupName];
    self.rootDirPath = rootDirPath;
    NSString *backupDirPath = [rootDirPath stringByAppendingPathComponent:@"Contents"];
    NSString *backupZipPath = [rootDirPath stringByAppendingPathComponent:[backupName stringByAppendingString:@".zip"]];
    DDLogInfo(@"%@ rootDirPath: %@", self.logTag, rootDirPath);
    DDLogInfo(@"%@ backupDirPath: %@", self.logTag, backupDirPath);
    DDLogInfo(@"%@ backupZipPath: %@", self.logTag, backupZipPath);

    [OWSFileSystem ensureDirectoryExists:rootDirPath];
    [OWSFileSystem protectFolderAtPath:rootDirPath];
    [OWSFileSystem ensureDirectoryExists:backupDirPath];

    NSData *databasePassword = [TSStorageManager sharedManager].databasePassword;

    if (![self writeData:databasePassword fileName:@"databasePassword" backupDirPath:backupDirPath]) {
        return;
    }
    if (![self writeUserDefaults:NSUserDefaults.standardUserDefaults
                        fileName:@"standardUserDefaults"
                   backupDirPath:backupDirPath]) {
        return;
    }
    if (![self writeUserDefaults:NSUserDefaults.appUserDefaults
                        fileName:@"appUserDefaults"
                   backupDirPath:backupDirPath]) {
        return;
    }
    if (![self copyDirectory:OWSFileSystem.appDocumentDirectoryPath
                  dstDirName:@"appDocumentDirectoryPath"
               backupDirPath:backupDirPath]) {
        return;
    }
    if (![self copyDirectory:OWSFileSystem.appSharedDataDirectoryPath
                  dstDirName:@"appSharedDataDirectoryPath"
               backupDirPath:backupDirPath]) {
        return;
    }
    if (![self zipDirectory:backupDirPath dstFilePath:backupZipPath]) {
        return;
    }

    [OWSFileSystem protectFolderAtPath:backupZipPath];
}

- (BOOL)writeData:(NSData *)data fileName:(NSString *)fileName backupDirPath:(NSString *)backupDirPath
{
    OWSAssert(data);
    OWSAssert(fileName.length > 0);
    OWSAssert(backupDirPath.length > 0);

    NSString *filePath = [backupDirPath stringByAppendingPathComponent:fileName];
    NSError *error;
    BOOL success = [data writeToFile:filePath options:NSDataWritingAtomic error:&error];
    if (!success || error) {
        OWSFail(@"%@ failed to write user defaults: %@", self.logTag, error);
        return NO;
    }
    return YES;
}

- (BOOL)copyDirectory:(NSString *)srcDirPath dstDirName:(NSString *)dstDirName backupDirPath:(NSString *)backupDirPath
{
    OWSAssert(srcDirPath.length > 0);
    OWSAssert(dstDirName.length > 0);
    OWSAssert(backupDirPath.length > 0);

    NSString *dstDirPath = [backupDirPath stringByAppendingPathComponent:dstDirName];

    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] copyItemAtPath:srcDirPath toPath:dstDirPath error:&error];
    if (!success || error) {
        OWSFail(@"%@ failed to copy directory: %@, %@", self.logTag, dstDirName, error);
        return NO;
    }
    return YES;
}

- (BOOL)writeUserDefaults:(NSUserDefaults *)userDefaults
                 fileName:(NSString *)fileName
            backupDirPath:(NSString *)backupDirPath
{
    OWSAssert(userDefaults);
    OWSAssert(fileName.length > 0);
    OWSAssert(backupDirPath.length > 0);

    NSDictionary<NSString *, id> *dictionary = userDefaults.dictionaryRepresentation;
    if (!dictionary) {
        OWSFail(@"%@ failed to extract user defaults", self.logTag);
        return NO;
    }
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:dictionary];
    if (!data) {
        OWSFail(@"%@ failed to archive user defaults", self.logTag);
        return NO;
    }

    return [self writeData:data fileName:fileName backupDirPath:backupDirPath];
}

- (BOOL)zipDirectory:(NSString *)srcDirPath dstFilePath:(NSString *)dstFilePath
{
    OWSAssert(srcDirPath.length > 0);
    OWSAssert(dstFilePath.length > 0);
    OWSAssert(self.password.length > 0);

    BOOL success = [SSZipArchive createZipFileAtPath:dstFilePath
                             withContentsOfDirectory:srcDirPath
                                 keepParentDirectory:NO
                                    compressionLevel:Z_DEFAULT_COMPRESSION
                                            password:self.password
                                                 AES:YES
                                     progressHandler:^(NSUInteger entryNumber, NSUInteger total) {
                                         DDLogVerbose(@"%@ Zip progress: %zd / %zd = %f",
                                             self.logTag,
                                             entryNumber,
                                             total,
                                             entryNumber / (CGFloat)total);
                                         // TODO:
                                     }];

    if (!success) {
        OWSFail(@"%@ failed to write zip backup", self.logTag);
        return NO;
    }

    NSError *error;
    NSNumber *fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:dstFilePath error:&error][NSFileSize];
    if (error) {
        OWSFail(@"%@ failed to get zip file size: %@", self.logTag, error);
        return NO;
    }
    DDLogVerbose(@"%@ Zip file size: %@", self.logTag, fileSize);

    return YES;
}

@end

NS_ASSUME_NONNULL_END
