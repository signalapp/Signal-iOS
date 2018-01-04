//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackup.h"
#import "NSUserDefaults+OWS.h"
#import "zlib.h"
#import <SSZipArchive/SSZipArchive.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/TSStorageManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSStorage (OWSBackup)

- (NSData *)databasePassword;

@end

#pragma mark -

@interface OWSBackup ()

@property (nonatomic) NSString *rootDirPath;

@end

#pragma mark -

@implementation OWSBackup

- (void)dealloc
{
    OWSAssert(self.rootDirPath.length > 0);

    DDLogInfo(@"%@ Cleaning up: %@", self.logTag, self.rootDirPath);
    [OWSFileSystem deleteFile:self.rootDirPath];
}

+ (void)exportDatabase
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[OWSBackup new] exportDatabase];
    });
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

    // TODO:
    NSString *password = [NSUUID UUID].UUIDString;

    BOOL success = [SSZipArchive createZipFileAtPath:dstFilePath
                             withContentsOfDirectory:srcDirPath
                                 keepParentDirectory:NO
                                    compressionLevel:Z_DEFAULT_COMPRESSION
                                            password:password
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

//- (BOOL)zipDirectory:(NSString *)srcDirPath
//      rootSrcDirPath:(NSString *)rootSrcDirPath
//         zipFile:(OZZipFile *)zipFile
//{
//    OWSAssert(srcDirPath.length > 0);
//    OWSAssert(rootSrcDirPath.length > 0);
//    OWSAssert(zipFile);
//
//    NSFileManager *fileManager = [NSFileManager defaultManager] ;
//    NSError *error;
//    NSArray <NSString *> *filenames =[fileManager contentsOfDirectoryAtPath:srcDirPath error:&error];
//    if (error) {
//        OWSFail(@"%@ failed to get directory contents: %@", self.logTag, error);
//        return NO;
//    }
//    for (NSString *fileName in filenames) {
//
//    }
//
//    //    OZZipWriteStream *stream= [zipFile writeFileInZipWithName:@"abc.txt"
//    //                                             compressionLevel:OZZipCompressionLevelBest];
//    //
//    //    [stream writeData:abcData];
//    //    [stream finishedWriting];}
//    //
//    // NSData *fileData= // Your file data
//    // uint32_t crc= [fileData crc32];
//    //
//    // OZZipWriteStream *stream= [zipFile writeFileInZipWithName:@"abc.txt"
//    //                                         compressionLevel:OZZipCompressionLevelBest
//    //                                                 password:@"password"
//    //                                                    crc32:crc];
//    //
//    //[stream writeData:fileData];
//    [stream finishedWriting];
//
//    return YES;
//}

@end

NS_ASSUME_NONNULL_END
