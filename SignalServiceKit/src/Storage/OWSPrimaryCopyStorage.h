//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryCopyStorage : OWSStorage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDirName:(NSString *)dirName NS_DESIGNATED_INITIALIZER;

+ (NSString *)databaseCopiesDirPath;

+ (NSString *)databaseCopyFilePathForDirName:(NSString *)dirName;

+ (NSDictionary<NSString *, Class> *)primaryCopyCollections;

@end

NS_ASSUME_NONNULL_END
