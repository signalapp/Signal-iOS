//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// Use instead of NSTemporaryDirectory()
// prefer the more restrictice OWSTemporaryDirectory,
// unless the temp data may need to be accessed while the device is locked.
NSString *OWSTemporaryDirectory(void);
NSString *OWSTemporaryDirectoryAccessibleAfterFirstAuth(void);
void ClearOldTemporaryDirectories(void);

@interface OWSFileSystem : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (BOOL)fileOrFolderExistsAtPath:(NSString *)path;

+ (BOOL)protectFileOrFolderAtPath:(NSString *)path;
+ (BOOL)protectFileOrFolderAtPath:(NSString *)path fileProtectionType:(NSFileProtectionType)fileProtectionType;

+ (BOOL)protectRecursiveContentsAtPath:(NSString *)path;

+ (NSString *)appDocumentDirectoryPath;

+ (NSString *)appLibraryDirectoryPath;

+ (NSString *)appSharedDataDirectoryPath;

+ (NSString *)cachesDirectoryPath;

+ (nullable NSError *)renameFilePathUsingRandomExtension:(NSString *)oldFilePath;

+ (nullable NSError *)moveAppFilePath:(NSString *)oldFilePath sharedDataFilePath:(NSString *)newFilePath;

+ (BOOL)moveFilePath:(NSString *)oldFilePath toFilePath:(NSString *)newFilePath;

// Returns NO IFF the directory does not exist and could not be created.
+ (BOOL)ensureDirectoryExists:(NSString *)dirPath;

+ (BOOL)ensureFileExists:(NSString *)filePath;

+ (BOOL)deleteFile:(NSString *)filePath;

+ (BOOL)deleteFileIfExists:(NSString *)filePath;

+ (void)deleteContentsOfDirectory:(NSString *)dirPath;

+ (NSArray<NSString *> *_Nullable)allFilesInDirectoryRecursive:(NSString *)dirPath error:(NSError **)error;

+ (NSString *)temporaryFilePath;
+ (NSURL *)temporaryFileURLWithFileExtension:(NSString *_Nullable)fileExtension NS_SWIFT_NAME(temporaryFileUrl(fileExtension:));
+ (NSString *)temporaryFilePathWithFileExtension:(NSString *_Nullable)fileExtension;

// Returns nil on failure.
+ (nullable NSString *)writeDataToTemporaryFile:(NSData *)data fileExtension:(NSString *_Nullable)fileExtension;

+ (nullable NSNumber *)fileSizeOfPath:(NSString *)filePath;

+ (nullable NSNumber *)fileSizeOfUrl:(NSURL *)fileUrl;

+ (void)logAttributesOfItemAtPathRecursively:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
