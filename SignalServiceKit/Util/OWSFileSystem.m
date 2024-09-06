//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSFileSystem.h"
#import "OWSError.h"
#import <SignalServiceKit/NSDate+OWS.h>
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
        success = [self protectFileOrFolderAtPath:filePath] && success;
    }

    return success;
}

+ (BOOL)protectFileOrFolderAtPath:(NSString *)path
{
    return [self protectFileOrFolderAtPath:path
                        fileProtectionType:NSFileProtectionCompleteUntilFirstUserAuthentication];
}

+ (BOOL)protectFileOrFolderAtPath:(NSString *)path fileProtectionType:(NSFileProtectionType)fileProtectionType
{
    NSError *_Nullable error;
    NSDictionary *fileProtection = @{ NSFileProtectionKey : fileProtectionType };
    BOOL success = [[NSFileManager defaultManager] setAttributes:fileProtection ofItemAtPath:path error:&error];
    if (!success) {
        if (error != nil && [error.domain isEqualToString:NSCocoaErrorDomain]
            && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError)) {
            return NO;
        }
        OWSFailDebug(@"Could not protect file or folder: %@", error.shortDescription);
        return NO;
    }

    NSDictionary *resourcesAttrs = @{ NSURLIsExcludedFromBackupKey : @YES };

    NSURL *resourceURL = [NSURL fileURLWithPath:path];
    success = [resourceURL setResourceValues:resourcesAttrs error:&error];

    if (!success) {
        if (error != nil && [error.domain isEqualToString:NSCocoaErrorDomain]
            && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError)) {
            return NO;
        }
        OWSFailDebug(@"Could not protect file or folder: %@", error.shortDescription);
        return NO;
    }
    return YES;
}

+ (NSString *)appLibraryDirectoryPath
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *documentDirectoryURL = [[fileManager URLsForDirectory:NSLibraryDirectory
                                                       inDomains:NSUserDomainMask] lastObject];
    return [documentDirectoryURL path];
}

+ (NSString *)appDocumentDirectoryPath
{
    return AppContextObjCBridge.shared.appDocumentDirectoryPath;
}

+ (NSURL *)appSharedDataDirectoryURL
{
    return [NSURL fileURLWithPath:self.appSharedDataDirectoryPath];
}

+ (NSString *)appSharedDataDirectoryPath
{
    return AppContextObjCBridge.shared.appSharedDataDirectoryPath;
}

+ (NSString *)cachesDirectoryPath
{
    static NSString *result;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        OWSPrecondition(paths.count >= 1);
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
        OWSFailDebug(@"Could not move file or directory with error: %@", error);
        return error;
    }
    return nil;
}

+ (BOOL)moveFilePath:(NSString *)oldFilePath toFilePath:(NSString *)newFilePath error:(NSError **)error
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if (![fileManager moveItemAtPath:oldFilePath toPath:newFilePath error:error]) {
        return NO;
    }

    // Ensure all files moved have the proper data protection class.
    // On large directories this can take a while, so we dispatch async
    // since we're in the launch path.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{ [self protectRecursiveContentsAtPath:newFilePath]; });

    return YES;
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
    unsigned long long fileSize = [[fileManager attributesOfItemAtPath:filePath
                                                                 error:&error][NSFileSize] unsignedLongLongValue];
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

NS_ASSUME_NONNULL_END
