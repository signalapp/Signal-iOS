//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSFileSystem : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (BOOL)protectFileOrFolderAtPath:(NSString *)path;

+ (NSString *)appDocumentDirectoryPath;

+ (NSString *)appSharedDataDirectoryPath;

+ (NSString *)cachesDirectoryPath;

+ (void)moveAppFilePath:(NSString *)oldFilePath
     sharedDataFilePath:(NSString *)newFilePath
          exceptionName:(NSString *)exceptionName;

// Returns NO IFF the directory does not exist and could not be created.
+ (BOOL)ensureDirectoryExists:(NSString *)dirPath;

+ (void)deleteFile:(NSString *)filePath;

+ (void)deleteFileIfExists:(NSString *)filePath;

+ (NSArray<NSString *> *_Nullable)allFilesInDirectoryRecursive:(NSString *)dirPath error:(NSError **)error;

+ (NSString *)temporaryFilePath;
+ (NSString *)temporaryFilePathWithFileExtension:(NSString *_Nullable)fileExtension;

// Returns nil on failure.
+ (nullable NSString *)writeDataToTemporaryFile:(NSData *)data fileExtension:(NSString *_Nullable)fileExtension;

@end

NS_ASSUME_NONNULL_END
