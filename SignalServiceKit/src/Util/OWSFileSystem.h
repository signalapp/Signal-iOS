//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSFileSystem : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (void)protectFolderAtPath:(NSString *)path;

+ (NSString *)appDocumentDirectoryPath;

+ (NSString *)appSharedDataDirectoryPath;

+ (void)moveAppFilePath:(NSString *)oldFilePath
     sharedDataFilePath:(NSString *)newFilePath
          exceptionName:(NSString *)exceptionName;

@end

NS_ASSUME_NONNULL_END
