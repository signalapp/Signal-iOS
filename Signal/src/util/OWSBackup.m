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

@property (nonatomic) OWSBackupState backupState;

@property (nonatomic) CGFloat backupProgress;

@property (nonatomic, nullable) TSThread *currentThread;

@property (nonatomic, nullable) NSString *backupPassword;

@property (nonatomic) NSString *backupDirPath;
@property (nonatomic) NSString *backupZipPath;

@end

#pragma mark -

@implementation OWSBackup

- (void)dealloc
{
    OWSAssert(self.backupDirPath.length > 0);

    DDLogInfo(@"%@ Cleaning up: %@", self.logTag, self.backupDirPath);
    [OWSFileSystem deleteFileIfExists:self.backupDirPath];
}

- (void)setBackupState:(OWSBackupState)backupState
{
    _backupState = backupState;

    [self.delegate backupStateDidChange];
}

- (void)fail
{
    if (!self.isCancelledOrFailed) {
        self.backupState = OWSBackupState_Failed;
    }
}

- (void)cancel
{
    self.backupState = OWSBackupState_Cancelled;
}

- (BOOL)isCancelledOrFailed
{
    return (self.backupState == OWSBackupState_Cancelled || self.backupState == OWSBackupState_Failed);
}

- (void)exportBackup:(nullable TSThread *)currentThread skipPassword:(BOOL)skipPassword
{
    OWSAssertIsOnMainThread();

    self.currentThread = currentThread;
    self.backupState = OWSBackupState_InProgress;

    if (skipPassword) {
        DDLogVerbose(@"%@ backup export without password", self.logTag);
    } else {
        // TODO: Should the user pick a password?
        //       If not, should probably generate something more user-friendly,
        //       e.g. case-insensitive set of hexadecimal?
        NSString *backupPassword = [NSUUID UUID].UUIDString;
        self.backupPassword = backupPassword;
        DDLogVerbose(@"%@ backup export with password: %@", self.logTag, backupPassword);
    }

    [self startExport];
}

- (void)startExport
{
    OWSAssertIsOnMainThread();

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self exportToFilesAndZip];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.isCancelledOrFailed) {
                self.backupState = OWSBackupState_Complete;
            }
            [self.delegate backupStateDidChange];
        });
    });
}

- (void)exportToFilesAndZip
{
    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *rootDirPath = [temporaryDirectory stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSString *backupDirPath = [rootDirPath stringByAppendingPathComponent:@"Contents"];

    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    [dateFormatter setLocale:[NSLocale currentLocale]];
    [dateFormatter setDateFormat:@"yyyy.MM.dd hh.mm.ss"];
    NSString *backupDateTime = [dateFormatter stringFromDate:[NSDate new]];
    NSString *backupName =
        [NSString stringWithFormat:NSLocalizedString(@"BACKUP_FILENAME_FORMAT",
                                       @"Format for backup filenames. Embeds: {{the date and time of the backup}}. "
                                       @"Should not include characters like slash (/ or \\) or colon (:)."),
                  backupDateTime];
    NSString *backupZipPath =
        [rootDirPath stringByAppendingPathComponent:[backupName stringByAppendingString:@".signalbackup"]];
    self.backupDirPath = backupDirPath;
    self.backupZipPath = backupZipPath;
    DDLogInfo(@"%@ rootDirPath: %@", self.logTag, rootDirPath);
    DDLogInfo(@"%@ backupDirPath: %@", self.logTag, backupDirPath);
    DDLogInfo(@"%@ backupZipPath: %@", self.logTag, backupZipPath);

    [OWSFileSystem ensureDirectoryExists:rootDirPath];
    [OWSFileSystem protectFolderAtPath:rootDirPath];
    [OWSFileSystem ensureDirectoryExists:backupDirPath];

    if (self.isCancelledOrFailed) {
        return;
    }

    NSData *databasePassword = [TSStorageManager sharedManager].databasePassword;

    if (![self writeData:databasePassword fileName:@"databasePassword" backupDirPath:backupDirPath]) {
        [self fail];
        return;
    }
    if (self.isCancelledOrFailed) {
        return;
    }
    if (![self writeUserDefaults:NSUserDefaults.standardUserDefaults
                        fileName:@"standardUserDefaults"
                   backupDirPath:backupDirPath]) {
        [self fail];
        return;
    }
    if (self.isCancelledOrFailed) {
        return;
    }
    if (![self writeUserDefaults:NSUserDefaults.appUserDefaults
                        fileName:@"appUserDefaults"
                   backupDirPath:backupDirPath]) {
        [self fail];
        return;
    }
    if (self.isCancelledOrFailed) {
        return;
    }
    // Use a read/write transaction to acquire a file lock on the database files.
    //
    // TODO: If we use multiple database files, lock them too.
    [TSStorageManager.sharedManager.newDatabaseConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            if (![self copyDirectory:OWSFileSystem.appDocumentDirectoryPath
                          dstDirName:@"appDocumentDirectoryPath"
                       backupDirPath:backupDirPath]) {
                [self fail];
                return;
            }
            if (self.isCancelledOrFailed) {
                return;
            }
            if (![self copyDirectory:OWSFileSystem.appSharedDataDirectoryPath
                          dstDirName:@"appSharedDataDirectoryPath"
                       backupDirPath:backupDirPath]) {
                [self fail];
                return;
            }
        }];
    if (self.isCancelledOrFailed) {
        return;
    }
    if (![self zipDirectory:backupDirPath dstFilePath:backupZipPath]) {
        [self fail];
        return;
    }

    [OWSFileSystem protectFolderAtPath:backupZipPath];

    [OWSFileSystem deleteFileIfExists:self.backupDirPath];
}

- (BOOL)writeData:(NSData *)data fileName:(NSString *)fileName backupDirPath:(NSString *)backupDirPath
{
    OWSAssert(data);
    OWSAssert(fileName.length > 0);
    OWSAssert(backupDirPath.length > 0);

    NSString *filePath = [backupDirPath stringByAppendingPathComponent:fileName];

    DDLogVerbose(@"%@ writeData: %@", self.logTag, filePath);

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

    DDLogVerbose(@"%@ copyDirectory: %@ -> %@", self.logTag, srcDirPath, dstDirPath);

    // We "manually" copy the "root" items in the src directory.
    // Can't just use [NSFileManager copyItemAtPath:...] because the shared data container
    // contains files that the app is not allowed to access.
    [OWSFileSystem ensureDirectoryExists:dstDirPath];
    NSError *error = nil;
    NSArray<NSString *> *fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:srcDirPath error:&error];
    if (error) {
        OWSFail(@"%@ failed to list directory: %@, %@", self.logTag, srcDirPath, error);
        return NO;
    }
    for (NSString *fileName in fileNames) {
        NSString *srcFilePath = [srcDirPath stringByAppendingPathComponent:fileName];
        NSString *dstFilePath = [dstDirPath stringByAppendingPathComponent:fileName];
        if ([fileName hasPrefix:@"."]) {
            DDLogVerbose(@"%@ ignoring: %@", self.logTag, srcFilePath);
            continue;
        }
        BOOL success = [[NSFileManager defaultManager] copyItemAtPath:srcFilePath toPath:dstFilePath error:&error];
        if (!success || error) {
            OWSFail(@"%@ failed to copy directory item: %@, %@", self.logTag, srcFilePath, error);
            return NO;
        }
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

    DDLogVerbose(@"%@ writeUserDefaults: %@", self.logTag, fileName);

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

    BOOL success = [SSZipArchive createZipFileAtPath:dstFilePath
                             withContentsOfDirectory:srcDirPath
                                 keepParentDirectory:NO
                                    compressionLevel:Z_DEFAULT_COMPRESSION
                                            password:self.backupPassword
                                                 AES:self.backupPassword != nil
                                     progressHandler:^(NSUInteger entryNumber, NSUInteger total) {
                                         DDLogVerbose(@"%@ Zip progress: %zd / %zd = %f",
                                             self.logTag,
                                             entryNumber,
                                             total,
                                             entryNumber / (CGFloat)total);

                                         CGFloat progress = entryNumber / (CGFloat)total;
                                         self.backupProgress = progress;
                                         [self.delegate backupProgressDidChange];
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
