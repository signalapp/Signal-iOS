//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

// In the main app, TSStorageManager is backed by the "primary" database and
// OWSPrimaryCopyStorage is backed by the "primary copy" database.
//
// In the SAE, TSStorageManager is backed by the "primary copy" database.
@interface OWSPrimaryCopyStorage : OWSStorage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithDirName:(NSString *)dirName NS_DESIGNATED_INITIALIZER;

+ (NSString *)databaseCopiesDirPath;

+ (NSString *)databaseCopyFilePathForDirName:(NSString *)dirName;

@end

NS_ASSUME_NONNULL_END
