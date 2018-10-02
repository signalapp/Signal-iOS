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
        OWSLogDebug(@"path: %@ had attributes: %@", filePath, directoryEnumerator.fileAttributes);

        success = success && [self protectFileOrFolderAtPath:filePath];
    }

    OWSLogInfo(@"protected contents at path: %@", path);
    return success;
}

+ (BOOL)protectFileOrFolderAtPath:(NSString *)path
{
    return
        [self protectFileOrFolderAtPath:path fileProtectionType:NSFileProtectionCompleteUntilFirstUserAuthentication];
}

+ (BOOL)protectFileOrFolderAtPath:(NSString *)path fileProtectionType:(NSFileProtectionType)fileProtectionType
{
    OWSLogVerbose(@"protecting file at path: %@", path);
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
        OWSFailDebug(@"Could not protect file or folder: %@", error);
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
        OWSFailDebug(@"error retrieving file attributes for missing file");
        return;
    }

    if (isDirectory) {
        NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:(NSString *)path];
        for (NSString *path in directoryEnumerator) {
            OWSLogDebug(@"path: %@ has attributes: %@", path, directoryEnumerator.fileAttributes);
        }
    } else {
        NSError *error;
        NSDictionary<NSFileAttributeKey, id> *_Nullable attributes =
            [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
        if (error) {
            OWSFailDebug(@"error retrieving file attributes: %@", error);
        } else {
            OWSLogDebug(@"path: %@ has attributes: %@", path, attributes);
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
    return CurrentAppContext().appDocumentDirectoryPath;
}

+ (NSString *)appSharedDataDirectoryPath
{
    return CurrentAppContext().appSharedDataDirectoryPath;
}

+ (NSString *)cachesDirectoryPath
{
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    OWSAssertDebug(paths.count >= 1);
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

    OWSLogInfo(@"Moving file or directory from: %@ to: %@", oldFilePath, newFilePath);

    NSError *_Nullable error;
    BOOL success = [fileManager moveItemAtPath:oldFilePath toPath:newFilePath error:&error];
    if (!success || error) {
        OWSLogDebug(@"Could not move file or directory from: %@ to: %@, error: %@", oldFilePath, newFilePath, error);
        OWSFailDebug(@"Could not move file or directory with error: %@", error);
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

    OWSLogInfo(@"Moving file or directory from: %@ to: %@", oldFilePath, newFilePath);

    if ([fileManager fileExistsAtPath:newFilePath]) {
        // If a file/directory already exists at the destination,
        // try to move it "aside" by renaming it with an extension.
        NSError *_Nullable error = [self renameFilePathUsingRandomExtension:newFilePath];
        if (error) {
            return error;
        }
    }

    if ([fileManager fileExistsAtPath:newFilePath]) {
        OWSLogDebug(
            @"Can't move file or directory from: %@ to: %@; destination already exists.", oldFilePath, newFilePath);
        OWSFailDebug(@"Can't move file or directory; destination already exists.");
        return OWSErrorWithCodeDescription(
            OWSErrorCodeMoveFileToSharedDataContainerError, @"Can't move file; destination already exists.");
    }
    
    NSDate *startDate = [NSDate new];
    
    NSError *_Nullable error;
    BOOL success = [fileManager moveItemAtPath:oldFilePath toPath:newFilePath error:&error];
    if (!success || error) {
        OWSLogDebug(@"Could not move file or directory from: %@ to: %@, error: %@", oldFilePath, newFilePath, error);
        OWSFailDebug(@"Could not move file or directory with error: %@", error);
        return error;
    }

    OWSLogInfo(@"Moved file or directory in: %f", fabs([startDate timeIntervalSinceNow]));
    OWSLogDebug(@"Moved file or directory from: %@ to: %@ in: %f",
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
    return [self ensureDirectoryExists:dirPath fileProtectionType:NSFileProtectionCompleteUntilFirstUserAuthentication];
}

+ (BOOL)ensureDirectoryExists:(NSString *)dirPath fileProtectionType:(NSFileProtectionType)fileProtectionType
{
    BOOL isDirectory;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:dirPath isDirectory:&isDirectory];
    if (exists) {
        OWSAssertDebug(isDirectory);

        return [self protectFileOrFolderAtPath:dirPath fileProtectionType:fileProtectionType];
    } else {
        OWSLogInfo(@"Creating directory at: %@", dirPath);

        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:dirPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
        if (error) {
            OWSFailDebug(@"Failed to create directory: %@, error: %@", dirPath, error);
            return NO;
        }
        return [self protectFileOrFolderAtPath:dirPath fileProtectionType:fileProtectionType];
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
            OWSFailDebug(@"Failed to create file.");
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
        OWSLogError(@"Failed to delete file: %@", error.description);
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
    OWSAssertDebug(dirPath.length > 0);

    *error = nil;

    NSArray<NSString *> *filenames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirPath error:error];
    if (*error) {
        OWSFailDebug(@"could not find files in directory: %@", *error);
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
    NSString *temporaryDirectory = OWSTemporaryDirectory();
    NSString *tempFileName = NSUUID.UUID.UUIDString;
    if (fileExtension.length > 0) {
        tempFileName = [[tempFileName stringByAppendingString:@"."] stringByAppendingString:fileExtension];
    }
    NSString *tempFilePath = [temporaryDirectory stringByAppendingPathComponent:tempFileName];

    return tempFilePath;
}

+ (nullable NSString *)writeDataToTemporaryFile:(NSData *)data fileExtension:(NSString *_Nullable)fileExtension
{
    OWSAssertDebug(data);

    NSString *tempFilePath = [self temporaryFilePathWithFileExtension:fileExtension];
    NSError *error;
    BOOL success = [data writeToFile:tempFilePath options:NSDataWritingAtomic error:&error];
    if (!success || error) {
        OWSFailDebug(@"could not write to temporary file: %@", error);
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
        OWSLogError(@"Couldn't fetch file size[%@]: %@", filePath, error);
        return nil;
    } else {
        return @(fileSize);
    }
}

@end

NSString *OWSTemporaryDirectory(void)
{
    NSString *dirName = @"ows_temp";
    NSString *dirPath = [NSTemporaryDirectory() stringByAppendingPathComponent:dirName];
    BOOL success = [OWSFileSystem ensureDirectoryExists:dirPath fileProtectionType:NSFileProtectionComplete];
    OWSCAssert(success);
    return dirPath;
}

NSString *OWSTemporaryDirectoryAccessibleAfterFirstAuth(void)
{
    NSString *dirPath = NSTemporaryDirectory();
    BOOL success = [OWSFileSystem ensureDirectoryExists:dirPath
                                     fileProtectionType:NSFileProtectionCompleteUntilFirstUserAuthentication];
    OWSCAssert(success);
    return dirPath;
}

NS_ASSUME_NONNULL_END
