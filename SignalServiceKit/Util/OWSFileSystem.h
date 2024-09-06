//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSFileSystem : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (BOOL)protectFileOrFolderAtPath:(NSString *)path;
+ (BOOL)protectFileOrFolderAtPath:(NSString *)path fileProtectionType:(NSFileProtectionType)fileProtectionType;

+ (BOOL)protectRecursiveContentsAtPath:(NSString *)path;

+ (NSString *)appDocumentDirectoryPath;

+ (NSString *)appLibraryDirectoryPath;

+ (NSURL *)appSharedDataDirectoryURL;
+ (NSString *)appSharedDataDirectoryPath;

+ (NSString *)cachesDirectoryPath;

+ (nullable NSError *)renameFilePathUsingRandomExtension:(NSString *)oldFilePath;

+ (BOOL)moveFilePath:(NSString *)oldFilePath toFilePath:(NSString *)newFilePath error:(NSError **)error;

+ (BOOL)ensureFileExists:(NSString *)filePath;

+ (void)deleteContentsOfDirectory:(NSString *)dirPath;

+ (nullable NSNumber *)fileSizeOfPath:(NSString *)filePath;

+ (nullable NSNumber *)fileSizeOfUrl:(NSURL *)fileUrl;

@end

NS_ASSUME_NONNULL_END
