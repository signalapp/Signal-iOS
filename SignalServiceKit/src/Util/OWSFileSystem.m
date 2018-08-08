//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSFileSystem.h"
#import "OWSError.h"
#import "TSConstants.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSFileSystem

+ (BOOL)protectRecursiveContentsAtPath:(NSString *)path
{
    BOOL isDirectory;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory]) {
        return NO;
    }

    if (!isDirectory) {
        return [self protectFileOrFolderAtPath:path];
    }
    NSString *dirPath = path;

    BOOL success = YES;
    NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:dirPath];

    for (NSString *relativePath in directoryEnumerator) {
        NSString *filePath = [dirPath stringByAppendingPathComponent:relativePath];
        DDLogDebug(@"%@ path: %@ had attributes: %@", self.logTag, filePath, directoryEnumerator.fileAttributes);

        success = success && [self protectFileOrFolderAtPath:filePath];
    }

    DDLogInfo(@"%@ protected contents at path: %@", self.logTag, path);
    return success;
}

+ (BOOL)protectFileOrFolderAtPath:(NSString *)path
{
    return
        [self protectFileOrFolderAtPath:path fileProtectionType:NSFileProtectionCompleteUntilFirstUserAuthentication];
}

+ (BOOL)protectFileOrFolderAtPath:(NSString *)path fileProtectionType:(NSFileProtectionType)fileProtectionType
{
    DDLogVerbose(@"%@ protecting file at path: %@", self.logTag, path);
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return NO;
    }

    NSError *error;
    NSDictionary *fileProtection = @{ NSFileProtectionKey : fileProtectionType };
    [[NSFileManager defaultManager] setAttributes:fileProtection ofItemAtPath:path error:&error];

    NSDictionary *resourcesAttrs = @{ NSURLIsExcludedFromBackupKey : @YES };

    NSURL *ressourceURL = [NSURL fileURLWithPath:path];
    BOOL success = [ressourceURL setResourceValues:resourcesAttrs error:&error];

    if (error || !success) {
        OWSFail(@"Could not protect file or folder: %@", error);
        OWSProdCritical([OWSAnalyticsEvents storageErrorFileProtection]);
        return NO;
    }
    return YES;
}

+ (void)logAttributesOfItemAtPathRecursively:(NSString *)path
{
    BOOL isDirectory;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory];
    if (!exists) {
        OWSFail(@"%@ error retrieving file attributes for missing file", self.logTag);
        return;
    }

    if (isDirectory) {
        NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:(NSString *)path];
        for (NSString *path in directoryEnumerator) {
            DDLogDebug(@"%@ path: %@ has attributes: %@", self.logTag, path, directoryEnumerator.fileAttributes);
        }
    } else {
        NSError *error;
        NSDictionary<NSFileAttributeKey, id> *_Nullable attributes =
            [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
        if (error) {
            OWSFail(@"%@ error retrieving file attributes: %@", self.logTag, error);
        } else {
            DDLogDebug(@"%@ path: %@ has attributes: %@", self.logTag, path, attributes);
        }
    }
}

+ (NSString *)appLibraryDirectoryPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *documentDirectoryURL =
        [[fileManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask] lastObject];
    return [documentDirectoryURL path];
}

+ (NSString *)appDocumentDirectoryPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *documentDirectoryURL =
        [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    return [documentDirectoryURL path];
}

+ (NSString *)appSharedDataDirectoryPath
{
    NSURL *groupContainerDirectoryURL =
        [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:SignalApplicationGroup];
    return [groupContainerDirectoryURL path];
}

+ (NSString *)cachesDirectoryPath
{
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    OWSAssert(paths.count >= 1);
    return paths[0];
}

+ (nullable NSError *)renameFilePathUsingRandomExtension:(NSString *)oldFilePath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:oldFilePath]) {
        return nil;
    }

    NSString *newFilePath =
        [[oldFilePath stringByAppendingString:@"."] stringByAppendingString:[NSUUID UUID].UUIDString];

    DDLogInfo(@"%@ Moving file or directory from: %@ to: %@", self.logTag, oldFilePath, newFilePath);

    NSError *_Nullable error;
    BOOL success = [fileManager moveItemAtPath:oldFilePath toPath:newFilePath error:&error];
    if (!success || error) {
        DDLogDebug(@"%@ Could not move file or directory from: %@ to: %@, error: %@",
            self.logTag,
            oldFilePath,
            newFilePath,
            error);
        OWSFail(@"%@ Could not move file or directory with error: %@", self.logTag, error);
        return error;
    }
    return nil;
}

+ (nullable NSError *)moveAppFilePath:(NSString *)oldFilePath sharedDataFilePath:(NSString *)newFilePath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:oldFilePath]) {
        return nil;
    }

    DDLogInfo(@"%@ Moving file or directory from: %@ to: %@", self.logTag, oldFilePath, newFilePath);

    if ([fileManager fileExistsAtPath:newFilePath]) {
        // If a file/directory already exists at the destination,
        // try to move it "aside" by renaming it with an extension.
        NSError *_Nullable error = [self renameFilePathUsingRandomExtension:newFilePath];
        if (error) {
            return error;
        }
    }

    if ([fileManager fileExistsAtPath:newFilePath]) {
        DDLogDebug(@"%@ Can't move file or directory from: %@ to: %@; destination already exists.",
            self.logTag,
            oldFilePath,
            newFilePath);
        OWSFail(@"%@ Can't move file or directory; destination already exists.", self.logTag);
        return OWSErrorWithCodeDescription(
            OWSErrorCodeMoveFileToSharedDataContainerError, @"Can't move file; destination already exists.");
    }
    
    NSDate *startDate = [NSDate new];
    
    NSError *_Nullable error;
    BOOL success = [fileManager moveItemAtPath:oldFilePath toPath:newFilePath error:&error];
    if (!success || error) {
        DDLogDebug(@"%@ Could not move file or directory from: %@ to: %@, error: %@",
            self.logTag,
            oldFilePath,
            newFilePath,
            error);
        OWSFail(@"%@ Could not move file or directory with error: %@", self.logTag, error);
        return error;
    }

    DDLogInfo(@"%@ Moved file or directory in: %f", self.logTag, fabs([startDate timeIntervalSinceNow]));
    DDLogDebug(@"%@ Moved file or directory from: %@ to: %@ in: %f",
        self.logTag,
        oldFilePath,
        newFilePath,
        fabs([startDate timeIntervalSinceNow]));

    // Ensure all files moved have the proper data protection class.
    // On large directories this can take a while, so we dispatch async
    // since we're in the launch path.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self protectRecursiveContentsAtPath:newFilePath];
    });

    return nil;
}

+ (BOOL)ensureDirectoryExists:(NSString *)dirPath
{
    BOOL isDirectory;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:dirPath isDirectory:&isDirectory];
    if (exists) {
        OWSAssert(isDirectory);

        return [self protectFileOrFolderAtPath:dirPath];
    } else {
        DDLogInfo(@"%@ Creating directory at: %@", self.logTag, dirPath);

        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:dirPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
        if (error) {
            OWSFail(@"%@ Failed to create directory: %@, error: %@", self.logTag, dirPath, error);
            return NO;
        }
        return [self protectFileOrFolderAtPath:dirPath];
    }
}

+ (BOOL)ensureFileExists:(NSString *)filePath
{
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:filePath];
    if (exists) {
        return [self protectFileOrFolderAtPath:filePath];
    } else {
        BOOL success = [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
        if (!success) {
            OWSFail(@"%@ Failed to create file.", self.logTag);
            return NO;
        }
        return [self protectFileOrFolderAtPath:filePath];
    }
}

+ (BOOL)deleteFile:(NSString *)filePath
{
    NSError *error;
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
    if (!success || error) {
        DDLogError(@"%@ Failed to delete file: %@", self.logTag, error.description);
        return NO;
    }
    return YES;
}

+ (BOOL)deleteFileIfExists:(NSString *)filePath
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        return YES;
    }
    return [self deleteFile:filePath];
}

+ (NSArray<NSString *> *_Nullable)allFilesInDirectoryRecursive:(NSString *)dirPath error:(NSError **)error
{
    OWSAssert(dirPath.length > 0);

    *error = nil;

    NSArray<NSString *> *filenames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirPath error:error];
    if (*error) {
        OWSFail(@"%@ could not find files in directory: %@", self.logTag, *error);
        return nil;
    }

    NSMutableArray<NSString *> *filePaths = [NSMutableArray new];

    for (NSString *filename in filenames) {
        NSString *filePath = [dirPath stringByAppendingPathComponent:filename];

        BOOL isDirectory;
        [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory];
        if (isDirectory) {
            [filePaths addObjectsFromArray:[self allFilesInDirectoryRecursive:filePath error:error]];
            if (*error) {
                return nil;
            }
        } else {
            [filePaths addObject:filePath];
        }
    }

    return filePaths;
}

+ (NSString *)temporaryFilePath
{
    return [self temporaryFilePathWithFileExtension:nil];
}

+ (NSString *)temporaryFilePathWithFileExtension:(NSString *_Nullable)fileExtension
{
    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *tempFileName = NSUUID.UUID.UUIDString;
    if (fileExtension.length > 0) {
        tempFileName = [[tempFileName stringByAppendingString:@"."] stringByAppendingString:fileExtension];
    }
    NSString *tempFilePath = [temporaryDirectory stringByAppendingPathComponent:tempFileName];

    return tempFilePath;
}

+ (nullable NSString *)writeDataToTemporaryFile:(NSData *)data fileExtension:(NSString *_Nullable)fileExtension
{
    OWSAssert(data);

    NSString *tempFilePath = [self temporaryFilePathWithFileExtension:fileExtension];
    NSError *error;
    BOOL success = [data writeToFile:tempFilePath options:NSDataWritingAtomic error:&error];
    if (!success || error) {
        OWSFail(@"%@ could not write to temporary file: %@", self.logTag, error);
        return nil;
    }

    [self protectFileOrFolderAtPath:tempFilePath];

    return tempFilePath;
}

+ (nullable NSNumber *)fileSizeOfPath:(NSString *)filePath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *_Nullable error;
    unsigned long long fileSize =
        [[fileManager attributesOfItemAtPath:filePath error:&error][NSFileSize] unsignedLongLongValue];
    if (error) {
        DDLogError(@"%@ Couldn't fetch file size[%@]: %@", self.logTag, filePath, error);
        return nil;
    } else {
        return @(fileSize);
    }
}

@end

NS_ASSUME_NONNULL_END
