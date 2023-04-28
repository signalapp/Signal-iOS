//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSFileSystem.h"
#import "OWSError.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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

    return success;
}

+ (BOOL)protectFileOrFolderAtPath:(NSString *)path
{
    return
        [self protectFileOrFolderAtPath:path fileProtectionType:NSFileProtectionCompleteUntilFirstUserAuthentication];
}

+ (BOOL)protectFileOrFolderAtPath:(NSString *)path fileProtectionType:(NSFileProtectionType)fileProtectionType
{
    if (!SSKDebugFlags.reduceLogChatter) {
        OWSLogVerbose(@"protecting file at path: %@", path);
    }
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return NO;
    }

    NSError *_Nullable error;
    NSDictionary *fileProtection = @{ NSFileProtectionKey : fileProtectionType };
    BOOL success = [[NSFileManager defaultManager] setAttributes:fileProtection ofItemAtPath:path error:&error];
    if (error || !success) {
        if (error != nil && [error.domain isEqualToString:NSCocoaErrorDomain]
            && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError)) {
            // We sometimes protect files async, so races around short-lived
            // temporarily files can cause these errors.
            OWSLogWarn(@"Could not protect file or folder: %@", error.shortDescription);
            return NO;
        }
        OWSFailDebug(@"Could not protect file or folder: %@", error.shortDescription);
        OWSProdCritical([OWSAnalyticsEvents storageErrorFileProtection]);
        return NO;
    }

    NSDictionary *resourcesAttrs = @{ NSURLIsExcludedFromBackupKey : @YES };

    NSURL *resourceURL = [NSURL fileURLWithPath:path];
    success = [resourceURL setResourceValues:resourcesAttrs error:&error];

    if (error || !success) {
        if (error != nil && [error.domain isEqualToString:NSCocoaErrorDomain]
            && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError)) {
            // We sometimes protect files async, so races around short-lived
            // temporarily files can cause these errors.
            OWSLogWarn(@"Could not protect file or folder: %@", error.shortDescription);
            return NO;
        }
        OWSFailDebug(@"Could not protect file or folder: %@", error.shortDescription);
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
        for (NSString *dirPath in directoryEnumerator) {
            OWSLogDebug(@"path: %@ has attributes: %@", dirPath, directoryEnumerator.fileAttributes);
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

+ (NSURL *)appSharedDataDirectoryURL
{
    return [NSURL fileURLWithPath:self.appSharedDataDirectoryPath];
}

+ (NSString *)appSharedDataDirectoryPath
{
    return CurrentAppContext().appSharedDataDirectoryPath;
}

+ (NSString *)cachesDirectoryPath
{
    static NSString *result;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        OWSAssert(paths.count >= 1);
        result = paths[0];
    });
    return result;
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
        return [OWSError withError:OWSErrorCodeMoveFileToSharedDataContainerError
                       description:@"Can't move file; destination already exists."
                       isRetryable:NO];
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

+ (BOOL)moveFilePath:(NSString *)oldFilePath toFilePath:(NSString *)newFilePath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:oldFilePath]) {
        OWSFailDebug(@"Can't move file or directory; source missing.");
        return NO;
    }

    if ([fileManager fileExistsAtPath:newFilePath]) {
        OWSFailDebug(@"Can't move file or directory; destination already exists.");
        return NO;
    }

    NSError *_Nullable error;
    BOOL success = [fileManager moveItemAtPath:oldFilePath toPath:newFilePath error:&error];
    if (!success || error) {
        OWSFailDebug(@"Could not move file or directory with error: %@", error.shortDescription);
        return NO;
    }

    // Ensure all files moved have the proper data protection class.
    // On large directories this can take a while, so we dispatch async
    // since we're in the launch path.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self protectRecursiveContentsAtPath:newFilePath];
    });

    return YES;
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

+ (void)deleteContentsOfDirectory:(NSString *)dirPath
{
    NSArray<NSString *> *_Nullable filePaths = [self recursiveFilesInDirectory:dirPath error:NULL];
    if (filePaths == nil) {
        OWSFailDebug(@"Could not retrieve files in directory.");
        return;
    }
    for (NSString *filePath in filePaths) {
        [self deleteFileIfExists:filePath];
    }
}

+ (nullable NSNumber *)fileSizeOfPath:(NSString *)filePath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *_Nullable error;
    unsigned long long fileSize =
        [[fileManager attributesOfItemAtPath:filePath error:&error][NSFileSize] unsignedLongLongValue];
    if (error) {
        OWSLogError(@"Couldn't fetch file size: %@", error.shortDescription);
        return nil;
    } else {
        return @(fileSize);
    }
}

+ (nullable NSNumber *)fileSizeOfUrl:(NSURL *)fileUrl
{
    return [self fileSizeOfPath:fileUrl.path];
}

@end

#pragma mark -

NSString *OWSTemporaryDirectory(void)
{
    static NSString *dirPath;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *dirName = [NSString stringWithFormat:@"ows_temp_%@", NSUUID.UUID.UUIDString];
        dirPath = [NSTemporaryDirectory() stringByAppendingPathComponent:dirName];
        BOOL success = [OWSFileSystem ensureDirectoryExists:dirPath fileProtectionType:NSFileProtectionComplete];
        OWSCAssert(success);
    });
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

static void ClearOldTemporaryDirectoriesSync(void)
{
    // Ignore the "current" temp directory.
    NSString *currentTempDirName = OWSTemporaryDirectory().lastPathComponent;

    NSDate *thresholdDate = CurrentAppContext().appLaunchTime;
    NSString *dirPath = NSTemporaryDirectory();
    NSError *error;
    NSArray<NSString *> *fileNames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirPath error:&error];
    if (error) {
        OWSCFailDebug(@"contentsOfDirectoryAtPath error: %@", error);
        return;
    }
    for (NSString *fileName in fileNames) {
        if (!CurrentAppContext().isAppForegroundAndActive) {
            // Abort if app not active.
            return;
        }
        if ([fileName isEqualToString:currentTempDirName]) {
            continue;
        }

        NSString *filePath = [dirPath stringByAppendingPathComponent:fileName];

        // Delete files with either:
        //
        // a) "ows_temp" name prefix.
        // b) modified time before app launch time.
        if (![fileName hasPrefix:@"ows_temp"]) {
            NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
            if (!attributes || error) {
                // This is fine; the file may have been deleted since we found it.
                OWSLogError(@"Could not get attributes of file or directory at: %@", filePath);
                continue;
            }
            // Don't delete files which were created in the last N minutes.
            NSDate *creationDate = attributes.fileModificationDate;
            if ([creationDate isAfterDate:thresholdDate]) {
                OWSLogVerbose(@"Skipping file due to age: %f", fabs([creationDate timeIntervalSinceNow]));
                continue;
            }
        }

        OWSLogVerbose(@"Removing temp file or directory: %@", filePath);
        if (![OWSFileSystem deleteFileIfExists:filePath]) {
            // This can happen if the app launches before the phone is unlocked.
            // Clean up will occur when app becomes active.
            OWSLogWarn(@"Could not delete old temp directory: %@", filePath);
        }
    }
}

// NOTE: We need to call this method on launch _and_ every time the app becomes active,
//       since file protection may prevent it from succeeding in the background.
void ClearOldTemporaryDirectories(void)
{
    // We use the lowest priority queue for this, and wait N seconds
    // to avoid interfering with app startup.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.f * NSEC_PER_SEC)),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),
        ^{
            ClearOldTemporaryDirectoriesSync();
        });
}

NS_ASSUME_NONNULL_END
